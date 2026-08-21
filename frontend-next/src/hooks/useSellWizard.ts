"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { toast } from "sonner";
import { firmaUploadFoto, riusaFotoDellaBottiglia } from "@/app/vendi/actions";
import { getSupabaseClient } from "@/lib/supabase/client";
import { createCellarService } from "@/services/cellar-service";
import { createListingService } from "@/services/listing-service";
import { createSupabaseAiService } from "@/services/phase10/supabase-ai-service";
import { campiDaSuggerimento } from "@/lib/phase10/catalogazione";
import { AI_UI, AZIONI_IA_ABILITATE } from "@/config/features";
import type {
  CatalogazioneSuggerimento,
  DatiNuovaBottiglia,
  DatiVenditaDaCantina,
} from "@/services/types";
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

/**
 * Wizard /vendi, portato da frontend/src/hooks/useSellWizard.ts.
 *
 * Quattro differenze rispetto all'originale, tutte conseguenza del fatto che
 * qui la pubblicazione scrive davvero:
 *
 * 1. `chiediSuggerimento` / `applicaSuggerimento` sono i vecchi `askListingAI`
 *    e `applyAiSuggestion`, rientrati con la Fase 10c: al posto della chiamata
 *    a /api/ai/listing-suggestion sul backend FastAPI c'è `AiService`
 *    sopra la Edge Function `ai-catalogo`. Il pannello manda solo `hint`; il
 *    campo `ocr_text` che la function accetta resta senza chiamante anche qui,
 *    esattamente come nel legacy (`backend/ai_routes.py:228` lo dichiara,
 *    `frontend/src/hooks/useSellWizard.ts:66` non lo manda), perché la cattura
 *    da fotografia è la 7.3a e ha una sessione di spec propria.
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

  // -- Riuso di quello che la bottiglia ha già -------------------------------
  //
  // Una bottiglia catalogata ha già le sue fotografie, nel bucket privato
  // `cantina`. Prima di questa modifica lo step Foto partiva vuoto e il
  // venditore ricaricava tutto da capo — e chi non lo faceva pubblicava un
  // annuncio senza immagini, che è la ragione per cui la scheda pubblica
  // mostrava il segnaposto mentre in Cantina la stessa bottiglia si vedeva:
  // `rigaAVino()` ripiega sulle foto di cantina quando l'annuncio non ne ha,
  // la vista pubblica no.
  const [riusoInCorso, setRiusoInCorso] = useState(daCantina);
  const [prezzoPrecedente, setPrezzoPrecedente] = useState<number | null>(null);
  const [prezzoConfermato, setPrezzoConfermato] = useState(false);
  // Marcatore di "già chiesto" in un ref e non in state: in state il setState
  // provoca un render, il render rifà l'effetto perché il marcatore è fra le
  // sue dipendenze, e la pulizia annulla la richiesta appena partita. È la
  // stessa lezione della 10c sul pannello Sommelier.
  const riusoChiesto = useRef(false);

  useEffect(() => {
    if (!bottleUnitId || riusoChiesto.current) return;
    riusoChiesto.current = true;

    let attivo = true;
    void riusaFotoDellaBottiglia(bottleUnitId)
      .then((esito) => {
        if (!attivo) return;
        if (!esito.ok) {
          // Non è un errore che ferma la vendita: si può sempre caricare a
          // mano. Lo si dice e si va avanti.
          toast.error(esito.error);
          return;
        }
        // Si aggiunge in testa senza sostituire: se nel frattempo il venditore
        // ha già caricato qualcosa, quello che ha fatto lui non si perde.
        if (esito.data.foto.length > 0) {
          setFoto((attuali) => [...esito.data.foto, ...attuali]);
        }
        if (esito.data.prezzoCentsPrecedente !== null) {
          setPrezzoPrecedente(esito.data.prezzoCentsPrecedente);
          setD((s) => (s.prezzo ? s : { ...s, prezzo: String(esito.data.prezzoCentsPrecedente! / 100) }));
        }
      })
      .finally(() => {
        if (attivo) setRiusoInCorso(false);
      });

    return () => {
      attivo = false;
    };
  }, [bottleUnitId]);

  const listingService = useMemo(() => createListingService(getSupabaseClient()), []);
  const cellarService = useMemo(() => createCellarService(getSupabaseClient()), []);
  const aiService = useMemo(
    () =>
      AI_UI.catalogazione && AZIONI_IA_ABILITATE
        ? createSupabaseAiService(getSupabaseClient())
        : null,
    [],
  );

  // Assistente AI del passo Identificazione (10c).
  const [aiHint, setAiHint] = useState("");
  const [aiSuggerimento, setAiSuggerimento] = useState<CatalogazioneSuggerimento | null>(null);
  const [aiInCorso, setAiInCorso] = useState(false);
  const [aiErrore, setAiErrore] = useState<string | null>(null);
  const [aiBloccata, setAiBloccata] = useState(false);

  const aggiornaAiHint = useCallback((valore: string) => {
    setAiHint(valore);
    setAiBloccata(false);
    setAiErrore(null);
  }, []);

  const chiediSuggerimento = useCallback(async () => {
    const hint = aiHint.trim();
    if (!hint || aiInCorso) return;
    if (!AZIONI_IA_ABILITATE || !aiService) {
      setAiBloccata(true);
      setAiErrore(null);
      return;
    }
    setAiInCorso(true);
    setAiBloccata(false);
    setAiErrore(null);
    try {
      const esito = await aiService.catalogazione({ hint });
      if (esito.ok) {
        setAiSuggerimento(esito.data);
      } else {
        // Il messaggio arriva già mediato: la Edge Function non lascia mai
        // uscire quello del fornitore (7.5), e l'adapter traduce gli stati che
        // il gateway restituisce senza corpo.
        setAiErrore(esito.error);
        setAiSuggerimento(null);
      }
    } finally {
      setAiInCorso(false);
    }
  }, [aiHint, aiInCorso, aiService]);

  const applicaSuggerimento = useCallback(() => {
    if (!aiSuggerimento) return;
    setD((s) => ({ ...s, ...campiDaSuggerimento(aiSuggerimento, s) }));
    toast.success("Suggerimenti AI applicati");
  }, [aiSuggerimento]);

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
      //
      // Solo le anteprime `blob:` vanno revocate. Quelle riusate dalla cantina
      // sono URL pubblici del bucket `annunci`: revocarle non fa danno ma non
      // significa niente, e il controllo dice a chi legge che le due specie di
      // anteprima esistono davvero.
      if (uscente?.anteprima.startsWith("blob:")) URL.revokeObjectURL(uscente.anteprima);
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

    // Un prezzo ereditato da un annuncio precedente non si pubblica finché il
    // venditore non lo guarda. Il campo è già compilato — il lavoro che si
    // risparmia resta risparmiato — ma la conferma è un gesto suo, perché fra
    // il vecchio annuncio e questo può essere passato molto tempo.
    if (prezzoPrecedente !== null && !prezzoConfermato) {
      toast.error("Conferma il prezzo prima di pubblicare.");
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
  }, [
    aggiungiInCantina,
    assicuraBozza,
    isVendita,
    onNavigate,
    listingService,
    onCantinaCambiata,
    prezzoPrecedente,
    prezzoConfermato,
  ]);

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
    riusoInCorso,
    prezzoPrecedente,
    prezzoConfermato,
    setPrezzoConfermato,
    inviando,
    bozzaId,
    pubblica,
    salvaBozza,
    aiHint,
    setAiHint: aggiornaAiHint,
    aiSuggerimento,
    aiInCorso,
    aiErrore,
    aiBloccata,
    chiediSuggerimento,
    applicaSuggerimento,
  };
}
