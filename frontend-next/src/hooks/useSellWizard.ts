"use client";

import { useCallback, useMemo, useState } from "react";
import { toast } from "sonner";
import { firmaUploadFoto } from "@/app/vendi/actions";
import { getSupabaseClient } from "@/lib/supabase/client";
import { createCellarService } from "@/services/cellar-service";
import { createListingService } from "@/services/listing-service";
import type { DatiNuovaBottiglia, DatiVenditaDaCantina } from "@/services/types";
import type { Wine } from "@/data/wines";

export type Modalita = "privata" | "pubblica" | "vendita";

/**
 * Una fotografia caricata: `percorso` è ciò che finisce in
 * `listings.immagini`, `anteprima` è l'URL locale (blob:) usato solo per
 * mostrarla nel wizard prima che l'annuncio esista.
 */
export type FotoCaricata = { percorso: string; anteprima: string };

type SellWizardOptions = {
  initialMode: Modalita;
  onNavigate: (path: string) => void;
  /**
   * Unità già in cantina che si sta mettendo in vendita (Fase 6c-2), presa da
   * `?bottiglia=` e passata dal pulsante "Metti in vendita" della cantina.
   * Quando c'è, il wizard non descrive più un vino: lo ha già.
   */
  bottleUnitId?: string | null;
  /**
   * Da chiamare quando il wizard ha cambiato la cantina, cioè quando ha coniato
   * una bottiglia nuova o cambiato lo stato di un annuncio.
   *
   * Serve perché il wizard scrive attraverso `ListingService` mentre la cantina
   * la tiene lo store: senza avviso, chi crea una bottiglia e viene riportato in
   * cantina non la troverebbe fino al ricaricamento della pagina. In `frontend/`
   * il problema non esiste perché lì la pubblicazione è un toast che non scrive
   * nulla e la cantina non cambia mai.
   */
  onCantinaCambiata?: () => void | Promise<void>;
};

const VENDITA_STEPS = [
  "Modalità",
  "Foto",
  "Identificazione",
  "Condizioni",
  "Provenienza",
  "Prezzo",
  "Consegna",
  "Anteprima",
];

const CATALOGAZIONE_STEPS = [
  "Modalità",
  "Foto",
  "Identificazione",
  "Condizioni",
  "Provenienza",
  "Anteprima",
];

export const MAX_FOTO = 6;

/**
 * Wizard /vendi, portato da frontend/src/hooks/useSellWizard.ts.
 *
 * Quattro differenze rispetto all'originale, tutte conseguenza del fatto che
 * qui la pubblicazione scrive davvero:
 *
 * 1. `askListingAI` / `applyAiSuggestion` non ci sono: chiamavano
 *    /api/ai/listing-suggestion sul backend FastAPI, e il dominio AI è Fase 10.
 *    Stessa esclusione già decisa per l'assistente Sommelier in Fase 3.
 * 2. Le fotografie si caricano sul serio: bucket privato `cantina` per la
 *    catalogazione, bucket pubblico `annunci` per la vendita.
 * 3. `pubblica` e `salvaBozza` sono asincroni e possono fallire: il messaggio
 *    che arriva dal database è già leggibile e viene mostrato così com'è.
 * 4. `sellerStatus` non è più un parametro. In frontend/ blocca la
 *    pubblicazione finché la verifica venditore non è completa; qui il ruolo
 *    `seller_enabled` non è applicato (decisione di Fase 6a) e
 *    /verifica-venditore non è ancora portata, quindi il blocco non avrebbe
 *    né una verifica da controllare né una pagina dove mandare l'utente.
 *
 * Dalla 6d-2a privata/pubblica creano direttamente una bottle_unit senza
 * annuncio; la vendita è raggiungibile solo dopo averne scelta una esistente.
 * `salvaBozza` seguito da `pubblica` non crea due annunci: l'id della bozza
 * resta in memoria e la pubblicazione riusa quello.
 */
export function useSellWizard({
  initialMode,
  onNavigate,
  bottleUnitId,
  onCantinaCambiata,
}: SellWizardOptions) {
  const daCantina = Boolean(bottleUnitId);
  // Una bottiglia già in cantina è per definizione da vendere: "cantina
  // privata" e "cantina pubblica" sono scelte che si fanno catalogandola, e
  // rifarle qui vorrebbe dire poterla togliere dalla vendita da un passo che
  // in frontend/ non fa quel lavoro.
  const [modalita, setModalita] = useState<Modalita>(daCantina ? "vendita" : initialMode);
  // Con la bottiglia già scelta il passo "Modalità" non ha nulla da chiedere e
  // si parte dal secondo. Gli indici dei passi restano quelli di prima: cambia
  // il punto di partenza, non la numerazione interna.
  const primoPasso = daCantina ? 1 : 0;
  const [step, setStep] = useState(primoPasso);
  const [d, setD] = useState({
    produttore: "",
    nome: "",
    annata: "",
    regione: "",
    tipo: "Rosso",
    condizione: "Perfetto",
    conservazione: "",
    storia: "",
    prezzo: "",
    disponibili: "1",
  });
  const set = (k: keyof typeof d) => (v: string) => setD((s) => ({ ...s, [k]: v }));

  const [foto, setFoto] = useState<FotoCaricata[]>([]);
  const [fotoInCorso, setFotoInCorso] = useState(false);
  const [inviando, setInviando] = useState(false);
  // Id della bozza già creata su Supabase, se c'è.
  const [bozzaId, setBozzaId] = useState<string | null>(null);

  const listingService = useMemo(() => createListingService(getSupabaseClient()), []);
  const cellarService = useMemo(() => createCellarService(getSupabaseClient()), []);

  const isVendita = modalita === "vendita";
  const steps = isVendita ? VENDITA_STEPS : CATALOGAZIONE_STEPS;
  /** Quanti passi vede davvero l'utente, e a quale è arrivato. */
  const passiVisibili = steps.length - primoPasso;
  const numeroPasso = step - primoPasso + 1;
  const progress = (numeroPasso / passiVisibili) * 100;
  const next = useCallback(() => setStep((s) => Math.min(steps.length - 1, s + 1)), [steps.length]);
  const prev = useCallback(() => setStep((s) => Math.max(primoPasso, s - 1)), [primoPasso]);

  const caricaFoto = useCallback(async (file: File) => {
    const client = getSupabaseClient();
    if (!client) {
      toast.error("Connessione a Supabase non configurata.");
      return;
    }

    setFotoInCorso(true);
    try {
      const firma = await firmaUploadFoto(
        file.type,
        file.size,
        daCantina ? "annuncio" : "cantina",
      );
      if (!firma.ok) {
        toast.error(firma.error);
        return;
      }

      const { error } = await client.storage
        .from(firma.data.bucket)
        .uploadToSignedUrl(firma.data.percorso, firma.data.token, file);

      if (error) {
        console.error("[vendi] upload fallito:", error);
        toast.error("Caricamento non riuscito. Riprova.");
        return;
      }

      setFoto((f) => [...f, { percorso: firma.data.percorso, anteprima: URL.createObjectURL(file) }]);
      toast.success("Fotografia caricata");
    } finally {
      setFotoInCorso(false);
    }
  }, [daCantina]);

  const rimuoviFoto = useCallback((indice: number) => {
    setFoto((f) => {
      const uscente = f[indice];
      // L'oggetto resta nel bucket: cancellarlo richiederebbe una scrittura
      // aggiuntiva a ogni ripensamento, e un file mai referenziato da nessun
      // annuncio non è raggiungibile se non da chi ne conosce già l'URL. La
      // pulizia dei file orfani è manutenzione, non parte di questa fase.
      if (uscente) URL.revokeObjectURL(uscente.anteprima);
      return f.filter((_, i) => i !== indice);
    });
  }, []);

  const datiVendita = useCallback((): DatiVenditaDaCantina | null => {
    if (!bottleUnitId) return null;
    return {
      bottleUnitId,
      condizione: d.condizione as Wine["condizione"],
      conservazione: d.conservazione.trim(),
      storia: d.storia.trim(),
      // Da euro digitati a centesimi interi. Math.round evita che 24.99 * 100
      // diventi 2498.9999999999995 e poi 2498 per troncamento.
      prezzoCents: Math.round(Number(d.prezzo) * 100),
      immagini: foto.map((f) => f.percorso),
    };
  }, [d, foto, bottleUnitId]);

  const datiBottiglia = useCallback((): DatiNuovaBottiglia => {
    return {
      produttore: d.produttore.trim(),
      nome: d.nome.trim(),
      annata: Number(d.annata),
      regione: d.regione.trim(),
      tipo: d.tipo as Wine["tipo"],
      visibilita: modalita === "pubblica" ? "cantina_pubblica" : "privata",
      immagini: foto.map((f) => f.percorso),
    };
  }, [d, foto, modalita]);

  /** Crea la bozza se non esiste ancora, e ne restituisce id e slug. */
  const assicuraBozza = useCallback(async () => {
    if (bozzaId) return { id: bozzaId, slug: null as string | null };

    const dati = datiVendita();
    if (!dati) {
      toast.error("Scegli una bottiglia dalla Cantina prima di metterla in vendita.");
      return null;
    }

    const esito = await listingService.crea(dati);
    if (!esito.ok) {
      toast.error(esito.error);
      return null;
    }
    setBozzaId(esito.data.id);
    // La cantina è appena cambiata: o è nata una bottiglia, o una che c'era ha
    // ora un annuncio.
    await onCantinaCambiata?.();
    return { id: esito.data.id, slug: esito.data.slug as string | null };
  }, [bozzaId, datiVendita, listingService, onCantinaCambiata]);

  const aggiungiInCantina = useCallback(async () => {
    const esito = await cellarService.aggiungiBottiglia(datiBottiglia());
    if (!esito.ok) {
      toast.error(esito.error);
      return false;
    }
    await onCantinaCambiata?.();
    toast.success(
      modalita === "pubblica"
        ? "Bottiglia aggiunta alla cantina pubblica"
        : "Bottiglia aggiunta alla tua cantina privata",
    );
    onNavigate("/cantina");
    return true;
  }, [cellarService, datiBottiglia, modalita, onCantinaCambiata, onNavigate]);

  const pubblica = useCallback(async () => {
    if (!isVendita) {
      setInviando(true);
      try {
        await aggiungiInCantina();
      } finally {
        setInviando(false);
      }
      return;
    }

    setInviando(true);
    try {
      const bozza = await assicuraBozza();
      if (!bozza) return;

      const esito = await listingService.pubblica(bozza.id);
      if (!esito.ok) {
        toast.error(esito.error);
        return;
      }

      toast.success("Annuncio pubblicato");
      // La bottiglia passa a "in vendita": lo stato che la cantina mostra è
      // derivato dagli annunci, quindi va riletto.
      await onCantinaCambiata?.();
      // Ritorno in cantina, come in frontend/. In 6b si andava all'annuncio
      // appena creato perché /cantina non era ancora stata portata: quella
      // divergenza, dichiarata allora, si chiude qui.
      onNavigate("/cantina");
    } finally {
      setInviando(false);
    }
  }, [aggiungiInCantina, assicuraBozza, isVendita, onNavigate, listingService, onCantinaCambiata]);

  const salvaBozza = useCallback(async () => {
    if (!isVendita) {
      setInviando(true);
      try {
        await aggiungiInCantina();
      } finally {
        setInviando(false);
      }
      return;
    }

    setInviando(true);
    try {
      const bozza = await assicuraBozza();
      if (!bozza) return;
      toast.success("Bozza salvata");
      // Anche una bozza è visibile in cantina: la bottiglia esiste, e compare
      // fra le proprie senza il distintivo "In vendita" finché non si pubblica.
      // In 6b non c'era una pagina dove mandare l'utente e si restava qui.
      onNavigate("/cantina");
    } finally {
      setInviando(false);
    }
  }, [aggiungiInCantina, assicuraBozza, isVendita, onNavigate]);

  const suggerito = d.produttore.toLowerCase().includes("sassicaia")
    ? 260
    : d.produttore.toLowerCase().includes("barolo")
      ? 300
      : 120;

  return {
    modalita,
    setModalita,
    step,
    steps,
    primoPasso,
    passiVisibili,
    numeroPasso,
    daCantina,
    progress,
    next,
    prev,
    isVendita,
    d,
    set,
    suggerito,
    foto,
    fotoInCorso,
    caricaFoto,
    rimuoviFoto,
    inviando,
    bozzaId,
    pubblica,
    salvaBozza,
  };
}
