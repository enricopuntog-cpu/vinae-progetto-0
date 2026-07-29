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
import { getSupabaseClient } from "@/lib/supabase/client";
import { createCellarService, leggiPosizione } from "@/services/cellar-service";
import type { DatiNuovoAmbiente, Result } from "@/services/types";

export type SfondoCantina = "moderna" | "rustica" | "pietra" | "premium" | "casse";

export type DrinkOverride = {
  drinkWindowStart?: number;
  drinkWindowEnd?: number;
  peakStart?: number;
  peakEnd?: number;
  preferenza?: "giovane" | "equilibrato" | "evoluto";
  nota?: string;
};

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
 * COSA RESTA IN MEMORIA. Regione e tipologia preferite, sfondo della cantina e
 * riduzione delle animazioni non hanno una tabella: non ce l'hanno nemmeno in
 * `frontend/`, dove sono `useState` che si perdono al ricaricamento. Migrarle
 * significherebbe aggiungere schema per una funzionalità che oggi non
 * persiste, cioè cambiare comportamento. Restano come sono.
 */
export function useCellarDomain() {
  const [regionePref, setRegionePref] = useState("Toscana");
  const [tipologiaPref, setTipologiaPref] = useState("Rossi strutturati");
  const [sfondoCantina, setSfondoCantina] = useState<SfondoCantina>("moderna");
  const [reduceMotion, setReduceMotion] = useState(false);

  const [dati, setDati] = useState(VUOTO);
  const [cantinaLoading, setCantinaLoading] = useState(() => getSupabaseClient() !== null);

  const servizio = useMemo(() => createCellarService(getSupabaseClient()), []);

  const caricaCantina = useCallback(
    async (conSessione: boolean) => {
      if (!conSessione) {
        // Nessuna sessione, nessuna cantina: un ospite non ne ha una. Si azzera
        // invece di lasciare in vista quella di chi ha appena chiuso la sessione.
        setDati(VUOTO);
        setCantinaLoading(false);
        return;
      }
      setDati(await servizio.carica());
      setCantinaLoading(false);
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

  const setPreferenze = useCallback((regione: string, tipologia: string) => {
    setRegionePref(regione);
    setTipologiaPref(tipologia);
    toast.success("Preferenze cantina aggiornate");
  }, []);

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
    regionePref,
    tipologiaPref,
    setPreferenze,
    sfondoCantina,
    setSfondoCantina,
    inVendita,
    prezzoNascosto,
    togglePrezzoNascosto,
    bottiglieCantina,
    viniCantina,
    metaPerVino,
    cantinaLoading,
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
