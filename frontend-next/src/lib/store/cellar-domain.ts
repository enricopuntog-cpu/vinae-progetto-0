"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { toast } from "sonner";
import {
  type CellarBottle,
  type StorageEnvironment,
  type StorageModule,
  type WineVintageMeta,
} from "@/data/cellar";
import type { Wine } from "@/data/wines";
import type { AnaliticaPortafoglio } from "@/lib/cantina/portfolio";
import { getSupabaseClient } from "@/lib/supabase/client";
import { createCellarService, leggiPosizione } from "@/services/cellar-service";
import type { DatiNuovoAmbiente, Result } from "@/services/types";

export type DrinkOverride = {
  drinkWindowStart?: number;
  drinkWindowEnd?: number;
  peakStart?: number;
  peakEnd?: number;
  preferenza?: "giovane" | "equilibrato" | "evoluto";
  nota?: string;
};

/**
 * Quanta parte delle unità di un vino è esposta nel profilo pubblico.
 *
 * PERCHÉ TRE VALORI E NON UN BOOLEANO. La visibilità è una colonna di
 * `bottle_units`: appartiene alla singola bottiglia, e il database la modella
 * così. L'interfaccia della Cantina però ragiona per vino — una scheda per
 * `wineVintageId`, e ogni comando accanto ad essa (`togglePrezzoNascosto`,
 * `setDrinkWindowOverride`) scrive tutte le unità di quel vino. Si è scelto di
 * tenere quell'aggregazione, non di introdurre una seconda superficie per
 * bottiglia; ma scegliere l'aggregazione non autorizza a fingere che il dato
 * sia per vino.
 *
 * Un booleano «almeno una esposta» lo fingerebbe, e mentirebbe due volte: la
 * scheda direbbe «Visibile nel profilo» mentre due bottiglie su tre sono
 * private, e il comando successivo le renderebbe private tutte e tre senza che
 * nulla lo annunciasse. Con tre valori lo stato misto ha un nome, si vede, e
 * `prossimaVisibilita` dice che cosa succede toccandolo.
 */
export type EsposizioneVino = "nessuna" | "alcune" | "tutte";

/** Lo stato di esposizione di ogni vino, contando le unità una per una. */
export const esposizioneDeiVini = (
  bottiglie: readonly Pick<CellarBottle, "wineVintageId" | "visibilitaCantina">[],
): Record<string, EsposizioneVino> => {
  const conteggio = new Map<string, { esposte: number; totale: number }>();
  for (const b of bottiglie) {
    const riga = conteggio.get(b.wineVintageId) ?? { esposte: 0, totale: 0 };
    riga.totale += 1;
    // `undefined` vale «non lo so» (dati dimostrativi senza colonna), e non lo
    // so non è esposta: la Cantina resta privata per difetto.
    if (b.visibilitaCantina === "cantina_pubblica") riga.esposte += 1;
    conteggio.set(b.wineVintageId, riga);
  }

  const out: Record<string, EsposizioneVino> = {};
  for (const [wineId, { esposte, totale }] of conteggio) {
    out[wineId] = esposte === 0 ? "nessuna" : esposte === totale ? "tutte" : "alcune";
  }
  return out;
};

/**
 * Dove porta il comando, dato lo stato corrente del vino.
 *
 * Si ritira solo da ciò che è esposto per intero. Da uno stato misto il primo
 * tocco espone tutto — la direzione che il pulsante annuncia — e il secondo
 * ritira tutto: due gesti, nessuno dei due a sorpresa, e lo stato misto si
 * risolve invece di alternarsi.
 */
export const prossimaVisibilita = (
  stato: EsposizioneVino | undefined,
): "privata" | "cantina_pubblica" => (stato === "tutte" ? "privata" : "cantina_pubblica");

const VUOTO = {
  bottiglie: [] as CellarBottle[],
  vini: [] as Wine[],
  metaPerVino: {} as Record<string, WineVintageMeta>,
  ambienti: [] as StorageEnvironment[],
  moduli: [] as StorageModule[],
};

/**
 * Dominio Cantina su dati reali (Fase 6c-2).
 *
 * PERCHÉ CARICA DAL BROWSER E NON DAL SERVER. La cantina è privata e non ha
 * nulla da mostrare a chi non ha una sessione, quindi non c'è niente da
 * prerenderizzare; in `frontend/` la pagina è comunque interamente client-side.
 * Soprattutto, i suoi dati non servono solo a `/cantina`: `MyBottleActions`
 * sulla scheda annuncio e la ricerca per abbinamento leggono le stesse
 * bottiglie da qui. Tenere il caricamento nello store lascia una sola fonte di
 * verità; passarle come prop dalle pagine ne creerebbe una per pagina.
 *
 * Il precedente è `real-auth-domain.ts`, che dalla Fase 5a carica la sessione
 * con lo stesso schema.
 *
 * La riduzione delle animazioni resta una preferenza della vista corrente. Le
 * preferenze di catalogo e lo sfondo personalizzato, che simulavano un
 * salvataggio senza persistenza, non sono esposti nella beta pubblica.
 */
export function useCellarDomain() {
  const [reduceMotion, setReduceMotion] = useState(false);

  const [dati, setDati] = useState(VUOTO);
  const [cantinaLoading, setCantinaLoading] = useState(() => getSupabaseClient() !== null);

  /**
   * L'analitica (D3-B) è uno stato separato, non un campo di `dati`, perché può
   * mancare mentre la cantina c'è: è un'altra lettura, con un altro privilegio,
   * e il suo errore non deve poter nascondere le bottiglie.
   */
  const [analitica, setAnalitica] = useState<AnaliticaPortafoglio | null>(null);
  const [analiticaErrore, setAnaliticaErrore] = useState<string | null>(null);
  const [analiticaLoading, setAnaliticaLoading] = useState(() => getSupabaseClient() !== null);

  const servizio = useMemo(() => createCellarService(getSupabaseClient()), []);

  const caricaCantina = useCallback(
    async (conSessione: boolean) => {
      if (!conSessione) {
        // Nessuna sessione, nessuna cantina: un ospite non ne ha una. Si azzera
        // invece di lasciare in vista quella di chi ha appena chiuso la sessione.
        setDati(VUOTO);
        setAnalitica(null);
        setAnaliticaErrore(null);
        setCantinaLoading(false);
        setAnaliticaLoading(false);
        return;
      }

      // Le due letture partono insieme — una sola andata e ritorno ciascuna, non
      // una per bottiglia — ma l'elenco non aspetta la contabilità: `/cantina`
      // si mostra appena le bottiglie sono qui, e l'analitica arriva dopo o non
      // arriva affatto.
      setAnaliticaLoading(true);
      const promessaAnalitica = servizio.analitica();

      setDati(await servizio.carica());
      setCantinaLoading(false);

      const esito = await promessaAnalitica;
      setAnalitica(esito.ok ? esito.data : null);
      setAnaliticaErrore(esito.ok ? null : esito.error);
      setAnaliticaLoading(false);
    },
    [servizio],
  );

  /** Rilettura dopo una scrittura. Fuori dagli effect, quindi può leggere da sé
   *  la sessione corrente. */
  const ricarica = useCallback(async () => {
    const supabase = getSupabaseClient();
    if (!supabase) return;
    const { data } = await supabase.auth.getSession();
    await caricaCantina(data.session !== null);
  }, [caricaCantina]);

  useEffect(() => {
    const supabase = getSupabaseClient();
    if (!supabase) return;

    let attivo = true;

    // La prima lettura sta dentro il `.then` e non nel corpo dell'effect:
    // aggiornare lo stato in modo sincrono qui innescherebbe render a cascata.
    // È la stessa forma di real-auth-domain.ts.
    void supabase.auth.getSession().then(({ data }) => {
      if (attivo) void caricaCantina(data.session !== null);
    });

    const { data: subscription } = supabase.auth.onAuthStateChange((_evento, session) => {
      if (attivo) void caricaCantina(session !== null);
    });

    return () => {
      attivo = false;
      subscription.subscription.unsubscribe();
    };
  }, [caricaCantina]);

  const { bottiglie: bottiglieCantina, vini: viniCantina, metaPerVino, ambienti, moduli } = dati;

  /**
   * `inVendita` e `prezzoNascosto` erano due `Set` indipendenti dai dati, con
   * un valore iniziale scritto a mano. Ora sono derivati: "in vendita" è un
   * fatto che vive in `listings` (deciso in 6a), "prezzo riservato" una colonna
   * dell'unità. L'indice resta il vino, perché è per vino che l'interfaccia
   * mostra le schede.
   */
  const inVendita = useMemo(
    () =>
      new Set(
        bottiglieCantina.filter((b) => b.saleStatus === "in_vendita").map((b) => b.wineVintageId),
      ),
    [bottiglieCantina],
  );

  const prezzoNascosto = useMemo(
    () =>
      new Set(
        bottiglieCantina
          .filter((b) => b.priceVisibility === "riservato")
          .map((b) => b.wineVintageId),
      ),
    [bottiglieCantina],
  );

  /**
   * Quanta parte di ogni vino il proprietario mostra nel proprio profilo.
   *
   * Il dato è distinto da `saleStatus` — una bottiglia può essere in vendita e
   * restare privata in Cantina, o essere esposta senza essere in vendita — e
   * per questo viene dalla colonna `visibilita`, non da una sua derivazione.
   * Non è un `Set` come `inVendita` e `prezzoNascosto`: il motivo è scritto
   * sopra `esposizioneDeiVini`.
   */
  const esposizioneCantina = useMemo(
    () => esposizioneDeiVini(bottiglieCantina),
    [bottiglieCantina],
  );

  /**
   * Nella 6c-1 l'override sta sull'unità, perché è una scelta personale.
   * L'interfaccia però lo mostra per vino: qui si ricompone quell'indice
   * prendendo il primo override trovato fra le proprie unità di quel vino.
   */
  const drinkWindowOverrides = useMemo(() => {
    const out: Record<string, DrinkOverride> = {};
    for (const b of bottiglieCantina) {
      if (b.override && !out[b.wineVintageId]) out[b.wineVintageId] = b.override;
    }
    return out;
  }, [bottiglieCantina]);

  /** Le unità di un vino che sono mie: bersaglio delle scritture "per vino". */
  const unitaDelVino = useCallback(
    (wineId: string) =>
      bottiglieCantina.filter((b) => b.wineVintageId === wineId).map((b) => b.bottleId),
    [bottiglieCantina],
  );

  /** Esito comune: messaggio d'errore del database, oppure conferma e ricarica. */
  const applica = useCallback(
    async (esito: Result<void>, conferma: string): Promise<Result<void>> => {
      if (!esito.ok) {
        toast.error(esito.error);
        return esito;
      }
      await ricarica();
      toast.success(conferma);
      return esito;
    },
    [ricarica],
  );

  const togglePrezzoNascosto = useCallback(
    async (wineId: string) => {
      const nascosto = prezzoNascosto.has(wineId);
      const esito = await servizio.impostaVisibilitaPrezzo(
        unitaDelVino(wineId),
        nascosto ? "visibile" : "riservato",
      );
      return applica(esito, nascosto ? "Prezzo visibile agli altri" : "Prezzo nascosto agli altri");
    },
    [applica, prezzoNascosto, servizio, unitaDelVino],
  );

  /**
   * L'unico comando che rende pubblica una bottiglia, e l'unico che la
   * richiude. Scrive la colonna `visibilita` attraverso il `GRANT UPDATE
   * (visibilita)` e la policy `bottle_units_update_own` che esistevano già: il
   * proprietario poteva tecnicamente cambiarla da prima della 20260925140000,
   * ma nell'interfaccia non c'era nessun posto da cui farlo.
   */
  const toggleCantinaPubblica = useCallback(
    async (wineId: string) => {
      const visibilita = prossimaVisibilita(esposizioneCantina[wineId]);
      const esito = await servizio.impostaVisibilitaCantina(unitaDelVino(wineId), visibilita);
      // Il testo non conta le bottiglie perché il comando non ne tocca una: la
      // scheda è il vino, e la conferma parla della stessa cosa del pulsante.
      return applica(
        esito,
        visibilita === "privata"
          ? "Questo vino non è più visibile nel tuo profilo"
          : "Questo vino è visibile nel tuo profilo",
      );
    },
    [applica, esposizioneCantina, servizio, unitaDelVino],
  );

  const setDrinkWindowOverride = useCallback(
    async (wineId: string, override: DrinkOverride) => {
      const esito = await servizio.impostaOverrideFinestra(unitaDelVino(wineId), override);
      // Stesso testo che PersonalizeDialog mostrava da sé prima della 6c-2:
      // la conferma si sposta qui perché ora può anche non arrivare.
      return applica(esito, "Finestra personalizzata salvata");
    },
    [applica, servizio, unitaDelVino],
  );

  const openBottle = useCallback(
    async (bottleId: string, nota?: string) => {
      const esito = await servizio.apri(bottleId, nota);
      return applica(esito, "Bottiglia aperta. Buona degustazione!");
    },
    [applica, servizio],
  );

  const scheduleOpen = useCallback(
    async (bottleId: string, date: string) => {
      const esito = await servizio.pianificaApertura(bottleId, date);
      return applica(esito, `Apertura programmata per il ${date}`);
    },
    [applica, servizio],
  );

  /**
   * La firma resta quella del mock — una bottiglia e un id di posizione —
   * perché è il linguaggio di `Cellar3D` e della finestra "Sposta". La
   * traduzione in (modulo, riga, colonna), che è ciò che il database vuole,
   * avviene qui: è il confine fra il vocabolario dell'interfaccia e quello
   * dello schema.
   */
  const moveBottle = useCallback(
    async (bottleId: string, newSlotId: string) => {
      const posizione = leggiPosizione(newSlotId);
      if (!posizione) {
        const errore = "Posizione non riconosciuta.";
        toast.error(errore);
        return { ok: false as const, error: errore };
      }
      const esito = await servizio.colloca(
        bottleId,
        posizione.moduleId,
        posizione.riga,
        posizione.colonna,
      );
      return applica(esito, "Bottiglia spostata");
    },
    [applica, servizio],
  );

  const creaAmbiente = useCallback(
    async (input: DatiNuovoAmbiente) => {
      const esito = await servizio.creaAmbiente(input);
      return applica(esito, `Ambiente "${input.nome}" creato`);
    },
    [applica, servizio],
  );

  return {
    inVendita,
    prezzoNascosto,
    togglePrezzoNascosto,
    esposizioneCantina,
    toggleCantinaPubblica,
    bottiglieCantina,
    viniCantina,
    metaPerVino,
    cantinaLoading,
    analitica,
    analiticaErrore,
    analiticaLoading,
    ricaricaCantina: ricarica,
    ambienti,
    moduli,
    drinkWindowOverrides,
    setDrinkWindowOverride,
    openBottle,
    scheduleOpen,
    moveBottle,
    creaAmbiente,
    reduceMotion,
    setReduceMotion,
  };
}
