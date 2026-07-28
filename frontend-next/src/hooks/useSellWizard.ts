"use client";

import { useCallback, useMemo, useState } from "react";
import { toast } from "sonner";
import { firmaUploadFoto } from "@/app/vendi/actions";
import { getSupabaseClient } from "@/lib/supabase/client";
import { BUCKET_ANNUNCI, createListingService } from "@/services/listing-service";
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
 * 2. Le fotografie si caricano sul serio, su Supabase Storage, invece di
 *    mostrare un toast "(demo)".
 * 3. `pubblica` e `salvaBozza` sono asincroni e possono fallire: il messaggio
 *    che arriva dal database è già leggibile e viene mostrato così com'è.
 * 4. `sellerStatus` non è più un parametro. In frontend/ blocca la
 *    pubblicazione finché la verifica venditore non è completa; qui il ruolo
 *    `seller_enabled` non è applicato (decisione di Fase 6a) e
 *    /verifica-venditore non è ancora portata, quindi il blocco non avrebbe
 *    né una verifica da controllare né una pagina dove mandare l'utente.
 *
 * `salvaBozza` seguito da `pubblica` non crea due annunci: l'id della bozza
 * resta in memoria e la pubblicazione riusa quello. Vale anche quando la
 * pubblicazione fallisce e l'utente riprova.
 */
export function useSellWizard({ initialMode, onNavigate }: SellWizardOptions) {
  const [modalita, setModalita] = useState<Modalita>(initialMode);
  const [step, setStep] = useState(0);
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

  const service = useMemo(() => createListingService(getSupabaseClient()), []);

  const isVendita = modalita === "vendita";
  const steps = isVendita ? VENDITA_STEPS : CATALOGAZIONE_STEPS;
  const progress = ((step + 1) / steps.length) * 100;
  const next = useCallback(() => setStep((s) => Math.min(steps.length - 1, s + 1)), [steps.length]);
  const prev = useCallback(() => setStep((s) => Math.max(0, s - 1)), []);

  const caricaFoto = useCallback(async (file: File) => {
    const client = getSupabaseClient();
    if (!client) {
      toast.error("Connessione a Supabase non configurata.");
      return;
    }

    setFotoInCorso(true);
    try {
      const firma = await firmaUploadFoto(file.type, file.size);
      if (!firma.ok) {
        toast.error(firma.error);
        return;
      }

      const { error } = await client.storage
        .from(BUCKET_ANNUNCI)
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
  }, []);

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

  /** Dati del wizard nella forma che il servizio (e il database) si aspettano. */
  const datiAnnuncio = useCallback(
    () => ({
      produttore: d.produttore.trim(),
      nome: d.nome.trim(),
      annata: Number(d.annata),
      regione: d.regione.trim(),
      tipo: d.tipo as Wine["tipo"],
      condizione: d.condizione as Wine["condizione"],
      conservazione: d.conservazione.trim(),
      storia: d.storia.trim(),
      // Da euro digitati a centesimi interi. Math.round evita che 24.99 * 100
      // diventi 2498.9999999999995 e poi 2498 per troncamento.
      prezzoCents: Math.round(Number(d.prezzo) * 100),
      immagini: foto.map((f) => f.percorso),
    }),
    [d, foto],
  );

  /** Crea la bozza se non esiste ancora, e ne restituisce id e slug. */
  const assicuraBozza = useCallback(async () => {
    if (bozzaId) return { id: bozzaId, slug: null as string | null };

    const esito = await service.crea(datiAnnuncio());
    if (!esito.ok) {
      toast.error(esito.error);
      return null;
    }
    setBozzaId(esito.data.id);
    return { id: esito.data.id, slug: esito.data.slug as string | null };
  }, [bozzaId, datiAnnuncio, service]);

  const pubblica = useCallback(async () => {
    if (!isVendita) {
      // Catalogazione: in frontend/ è un toast di demo che non scrive nulla, e
      // resta tale. Le bottiglie in cantina senza annuncio sono la Fase 6c.
      toast.success(
        modalita === "pubblica"
          ? "Bottiglia aggiunta alla cantina pubblica (demo)"
          : "Bottiglia aggiunta alla tua cantina privata (demo)",
      );
      onNavigate("/home");
      return;
    }

    setInviando(true);
    try {
      const bozza = await assicuraBozza();
      if (!bozza) return;

      const esito = await service.pubblica(bozza.id);
      if (!esito.ok) {
        toast.error(esito.error);
        return;
      }

      toast.success("Annuncio pubblicato");
      // In frontend/ si torna in cantina, che qui non esiste ancora: si va
      // all'annuncio appena creato, che è la prova che la pubblicazione è
      // andata a buon fine.
      onNavigate(bozza.slug ? `/annuncio/${bozza.slug}` : "/esplora");
    } finally {
      setInviando(false);
    }
  }, [assicuraBozza, isVendita, modalita, onNavigate, service]);

  const salvaBozza = useCallback(async () => {
    if (!isVendita) {
      toast.success("Bozza salvata nella cantina (demo)");
      onNavigate("/home");
      return;
    }

    setInviando(true);
    try {
      const bozza = await assicuraBozza();
      if (!bozza) return;
      // Si resta nel wizard: una bozza non compare da nessuna parte finché non
      // viene pubblicata, quindi non c'è nessuna pagina dove mandare l'utente.
      toast.success("Bozza salvata");
    } finally {
      setInviando(false);
    }
  }, [assicuraBozza, isVendita, onNavigate]);

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
