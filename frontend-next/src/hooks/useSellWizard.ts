"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { toast } from "sonner";
import { firmaUploadFoto, riusaFotoDellaBottiglia } from "@/app/vendi/actions";
import { getSupabaseClient } from "@/lib/supabase/client";
import { createCellarService } from "@/services/cellar-service";
import { createListingService } from "@/services/listing-service";
import { creaWineRegionsService } from "@/services/wine-regions-service";
import { createSupabaseAiService } from "@/services/phase10/supabase-ai-service";
import { campiDaSuggerimento } from "@/lib/phase10/catalogazione";
import {
  smartSellPriceDaLettura,
  type SmartSellPrice,
} from "@/lib/price-intelligence/smart-sell-price";
import { euroDaCents, richiedeConfermaPrezzoPrecedente } from "@/lib/vendi/prezzo";
import { acquisizioneDaCampi } from "@/lib/vendi/acquisizione";
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
   * L'identità reale del vino dell'unità che si sta vendendo, per Smart Sell
   * Price: la chiave con cui due annunci sono lo stesso vino e il formato
   * esatto della bottiglia.
   *
   * Arriva dalla pagina e non si ricava qui: il vino dell'unità vive nello
   * store della Cantina, che la pagina ha già letto. Chiederlo di nuovo da
   * dentro il wizard sarebbe una seconda lettura per righe già in memoria.
   *
   * `null` finché la Cantina non è arrivata, o quando non si sta vendendo.
   */
  identitaVino?: { wineKey: string; formato: string } | null;
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
  identitaVino,
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
    // I due fatti di acquisizione restano testo finché non si cataloga: la
    // conversione è nel modulo dedicato, perché lo sbaglio possibile qui è
    // invisibile — trasformare «non lo so» in un costo noto di zero.
    prezzoAcquisto: "",
    dataAcquisto: "",
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
  // «L'utente ha scelto un prezzo», che non è «nel campo c'è un prezzo».
  // Il precompilato dell'annuncio precedente non lo accende (lo scrive
  // l'effetto qui sotto con `setD`, non `impostaPrezzo`); digitare o applicare
  // il suggerimento sì. Vedi `richiedeConfermaPrezzoPrecedente`.
  const [prezzoSceltoDaUtente, setPrezzoSceltoDaUtente] = useState(false);
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

  const supabase = useMemo(() => getSupabaseClient(), []);
  const listingService = useMemo(() => createListingService(supabase), [supabase]);
  const cellarService = useMemo(() => createCellarService(supabase), [supabase]);
  const wineRegionsService = useMemo(() => creaWineRegionsService(supabase), [supabase]);

  // Il registro distingue quattro stati: un successo vuoto non è un errore, ma
  // nessuno dei due può abilitare la scelta. La promise nel ref garantisce una
  // sola lettura per visita anche quando React riesegue l'effetto in sviluppo:
  // ogni setup si collega alla stessa richiesta invece di crearne una seconda.
  const [regioni, setRegioni] = useState<
    | { stato: "non_richiesto" }
    | { stato: "caricamento" }
    | { stato: "disponibili"; nomi: string[] }
    | { stato: "vuoto" }
    | { stato: "errore"; messaggio: string }
  >(daCantina ? { stato: "non_richiesto" } : { stato: "caricamento" });
  const richiestaRegioni = useRef<ReturnType<typeof wineRegionsService.elenco> | null>(null);

  useEffect(() => {
    if (daCantina) return;

    richiestaRegioni.current ??= wineRegionsService.elenco();
    let attivo = true;

    void richiestaRegioni.current
      .then((esito) => {
        if (!attivo) return;
        if (!esito.ok) {
          setRegioni({ stato: "errore", messaggio: esito.error });
        } else if (esito.data.length === 0) {
          setRegioni({ stato: "vuoto" });
        } else {
          setRegioni({ stato: "disponibili", nomi: esito.data });
        }
      })
      .catch((errore: unknown) => {
        console.error("[vendi] lettura regioni fallita:", errore);
        if (attivo) {
          setRegioni({
            stato: "errore",
            messaggio: "Non è stato possibile leggere l'elenco delle regioni.",
          });
        }
      });

    return () => {
      attivo = false;
    };
  }, [daCantina, wineRegionsService]);

  const regioniCanoniche = useMemo(
    () => (regioni.stato === "disponibili" ? regioni.nomi : []),
    [regioni],
  );
  const regioneValida = daCantina || regioniCanoniche.includes(d.regione);

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
    setD((s) => ({
      ...s,
      ...campiDaSuggerimento(aiSuggerimento, s, regioniCanoniche),
    }));
    toast.success("Suggerimenti AI applicati");
  }, [aiSuggerimento, regioniCanoniche]);

  const isVendita = modalita === "vendita";

  // -- Smart Sell Price -------------------------------------------------------
  //
  // Il suggerimento del passo Prezzo. Il calcolo non è qui: è la composizione
  // 1B in `@/lib/price-intelligence/smart-sell-price`, che riusa soglia,
  // mediana, filtro vino/formato, deduplica e copertura senza riscriverli.
  // Qui c'è solo la lettura che gliela fornisce.
  //
  // La sorgente è `ListingService.elencoConEsito()`, cioè `public_listings`:
  // annunci pubblici e attivi, con il filtro `stato = 'attivo'` dentro la vista.
  // L'esito esplicito impedisce di raccontare «zero comparabili» quando invece
  // è fallita la lettura. Lo storico prezzi NON viene letto — il suggerimento
  // nasce dai comparabili ASKING correnti, come la 1B ha deciso, e le vendite non
  // hanno da qui una strada per entrare.
  const wineKeyVino = identitaVino?.wineKey ?? null;
  const formatoVino = identitaVino?.formato ?? null;
  const chiaveSmartPrice =
    isVendita && wineKeyVino && formatoVino
      ? JSON.stringify([wineKeyVino, formatoVino])
      : null;
  const [smartPriceLetto, setSmartPriceLetto] = useState<{
    chiave: string;
    suggerimento: SmartSellPrice;
  } | null>(null);

  useEffect(() => {
    // Una bottiglia non ancora risolta sul catalogo non ha una chiave con cui
    // confrontare gli annunci. Senza client non c'è invece una lettura riuscita.
    // In entrambi i casi lo stato derivato sotto è `non_disponibile` e il campo
    // manuale resta utilizzabile, senza setState sincroni dentro l'effetto.
    if (!chiaveSmartPrice || !wineKeyVino || !formatoVino || !supabase) return;

    let attivo = true;

    void (async () => {
      try {
        const esito = await listingService.elencoConEsito();
        if (!attivo) return;

        // Nessun numero di ripiego e nessun blocco su errore: il passo Prezzo
        // resta utilizzabile a mano. Il mapper distingue l'errore dall'elenco
        // davvero vuoto senza copiare nell'interfaccia il dettaglio PostgREST.
        setSmartPriceLetto({
          chiave: chiaveSmartPrice,
          suggerimento: smartSellPriceDaLettura({
            esito,
            wineKey: wineKeyVino,
            formato: formatoVino,
          }),
        });
      } catch (errore) {
        // Copre errori inattesi del trasporto senza trasformarli in «zero
        // comparabili» e senza impedire l'inserimento manuale.
        console.error("[vendi] comparabili non disponibili:", errore);
        if (attivo) {
          setSmartPriceLetto({
            chiave: chiaveSmartPrice,
            suggerimento: { stato: "non_disponibile" },
          });
        }
      }
    })();

    return () => {
      attivo = false;
    };
  }, [chiaveSmartPrice, wineKeyVino, formatoVino, listingService, supabase]);

  // La chiave impedisce che il risultato della bottiglia precedente resti
  // visibile mentre cambia vino o formato. `null` rappresenta solo la lettura in
  // corso; le condizioni in cui non si può leggere sono terminali e manuali.
  const smartPrice = useMemo<SmartSellPrice | null>(
    () =>
      !isVendita
        ? null
        : !chiaveSmartPrice || !supabase
          ? { stato: "non_disponibile" }
          : smartPriceLetto?.chiave === chiaveSmartPrice
            ? smartPriceLetto.suggerimento
            : null,
    [isVendita, chiaveSmartPrice, smartPriceLetto, supabase],
  );
  const smartPriceInCorso = Boolean(
    chiaveSmartPrice && supabase && smartPriceLetto?.chiave !== chiaveSmartPrice,
  );

  /**
   * Il prezzo lo scrive l'utente, sempre: digitandolo o applicando il
   * suggerimento. Entrambe le vie passano di qui, ed entrambe valgono come
   * scelta esplicita — è ciò che spegne la conferma del prezzo precedente.
   */
  const impostaPrezzo = useCallback((valore: string) => {
    setPrezzoSceltoDaUtente(true);
    setD((s) => ({ ...s, prezzo: valore }));
  }, []);

  /** L'unico punto in cui il suggerimento entra nel campo prezzo. */
  const usaPrezzoSuggerito = useCallback(() => {
    if (!smartPrice || smartPrice.stato !== "suggerito") return;
    impostaPrezzo(euroDaCents(smartPrice.medianaCents));
    toast.success("Prezzo suggerito applicato");
  }, [smartPrice, impostaPrezzo]);

  const prezzoPrecedenteDaConfermare =
    prezzoPrecedente !== null && !prezzoSceltoDaUtente;
  const confermaPrezzoRichiesta = richiedeConfermaPrezzoPrecedente({
    prezzoPrecedenteCents: prezzoPrecedente,
    sceltaEsplicita: prezzoSceltoDaUtente,
    confermato: prezzoConfermato,
  });

  const steps = isVendita ? VENDITA_STEPS : CATALOGAZIONE_STEPS;
  /** Quanti passi vede davvero l'utente, e a quale è arrivato. */
  const passiVisibili = steps.length - primoPasso;
  const numeroPasso = step - primoPasso + 1;
  const progress = (numeroPasso / passiVisibili) * 100;
  /**
   * Il passo si riconosce dal nome, non da un indice: i due elenchi hanno
   * lunghezze diverse e un passo aggiunto prima di questo sposterebbe in
   * silenzio il guard su una schermata che non ha una Regione.
   */
  const suIdentificazione = steps[step] === "Identificazione";
  // Il guard sta fuori dall'updater di `setStep`: un updater deve essere puro,
  // e React lo riesegue in sviluppo — un `toast` al suo interno comparirebbe
  // due volte.
  const next = useCallback(() => {
    if (suIdentificazione && !regioneValida) {
      toast.error("Scegli una Regione dall'elenco prima di continuare.");
      return;
    }
    setStep((corrente) => Math.min(steps.length - 1, corrente + 1));
  }, [regioneValida, suIdentificazione, steps.length]);
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
      // Assenza e zero restano distinti fino alla RPC: il prezzo dell'annuncio
      // non c'entra, e un campo vuoto non è un costo noto di zero.
      ...acquisizioneDaCampi({
        prezzoEuro: d.prezzoAcquisto,
        data: d.dataAcquisto,
      }),
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
    //
    // «Guardarlo» però include averlo cambiato: chi ha digitato un altro
    // numero o ha applicato il suggerimento ha già scelto, e chiedergli di
    // confermare il vecchio prezzo sarebbe chiedergli di confermare un numero
    // che non è più nel campo.
    if (confermaPrezzoRichiesta) {
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
    confermaPrezzoRichiesta,
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
    regioni,
    regioneValida,
    suIdentificazione,
    impostaPrezzo,
    smartPrice,
    smartPriceInCorso,
    usaPrezzoSuggerito,
    foto,
    fotoInCorso,
    caricaFoto,
    rimuoviFoto,
    riusoInCorso,
    prezzoPrecedente,
    prezzoPrecedenteDaConfermare,
    prezzoConfermato,
    setPrezzoConfermato,
    confermaPrezzoRichiesta,
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
