/**
 * Il modulo puro della logistica dell'annuncio, e l'ordine di scrittura.
 *
 * Due cose si provano qui. La prima è che i valori del frontend siano
 * esattamente quelli che `public.listing_logistica_dichiara` accetta: l'unione
 * TypeScript è una copia locale di un vincolo del database, e una copia che
 * diverge non protegge, illude. La seconda è la sequenza pubblica-dopo-dichiara,
 * isolata apposta in funzioni iniettabili perché il pacchetto non ha un renderer
 * React e un ordine di scrittura provato soltanto leggendo l'hook sarebbe
 * provato male.
 */

import { describe, expect, it } from "bun:test";
import {
  ammetteFotoConfezione,
  confezioneOriginaleTipoDaDb,
  eConfezioneOriginaleTipo,
  eHandoffVenditore,
  etichettaConfezioneOriginale,
  etichettaHandoff,
  haLogisticaDaSalvare,
  handoffVenditoreDaDb,
  logisticaCompleta,
  messaggioLogisticaMancante,
  normalizzaLogistica,
  pubblicaConLogistica,
  salvaLogisticaBozza,
  CONFEZIONI_ORIGINALI,
  ETICHETTA_CONFEZIONE_ORIGINALE,
  ETICHETTA_HANDOFF,
  HANDOFF_CONSIGLIATO,
  HANDOFF_VENDITORE,
  MANCA_CONFEZIONE,
  MANCA_HANDOFF,
  MAX_FOTO_CONFEZIONE,
  type DichiarazioneLogistica,
  type EsitoLogistica,
  type StatoLogisticaWizard,
} from "@/lib/vendi/logistica-annuncio";

const ANNUNCIO = "7b1f0e2a-3333-4333-8333-cccccccccccc";
const UID = "11111111-1111-4111-8111-111111111111";
const FOTO = (n: number) =>
  Array.from({ length: n }, (_, i) => `${UID}/0000000${i}-0000-4000-8000-000000000000.jpg`);

const stato = (over: Partial<StatoLogisticaWizard> = {}): StatoLogisticaWizard => ({
  confezioneOriginaleTipo: null,
  fotoConfezione: [],
  handoffVenditore: null,
  ...over,
});

const ok: EsitoLogistica = { ok: true, data: undefined };

// ---------------------------------------------------------------------------
// A. Tipi ed etichette
// ---------------------------------------------------------------------------

describe("i valori ammessi", () => {
  it("espone esattamente i quattro tipi di confezione originale", () => {
    expect([...CONFEZIONI_ORIGINALI]).toEqual([
      "nessuna_confezione_originale",
      "cofanetto_originale",
      "cassa_legno_originale",
      "confezione_multipla_originale",
    ]);
    expect(eConfezioneOriginaleTipo("cofanetto_originale")).toBeTrue();
    // Le varianti plausibili che la funzione SQL respingerebbe con 22023.
    for (const finto of ["cofanetto", "COFANETTO_ORIGINALE", "cassa_legno", "", null, 3]) {
      expect(eConfezioneOriginaleTipo(finto)).toBeFalse();
    }
  });

  it("espone esattamente le due modalità di consegna", () => {
    expect([...HANDOFF_VENDITORE]).toEqual(["dropoff_pudo", "ritiro_domicilio"]);
    expect(eHandoffVenditore("ritiro_domicilio")).toBeTrue();
    for (const finto of ["pudo", "dropoff", "ritiro", "", null]) {
      expect(eHandoffVenditore(finto)).toBeFalse();
    }
  });

  it("etichetta ciascun valore, senza buchi e senza etichette in più", () => {
    expect(Object.keys(ETICHETTA_CONFEZIONE_ORIGINALE).sort()).toEqual(
      [...CONFEZIONI_ORIGINALI].sort(),
    );
    expect(Object.keys(ETICHETTA_HANDOFF).sort()).toEqual([...HANDOFF_VENDITORE].sort());
    expect(etichettaConfezioneOriginale("cassa_legno_originale")).toBe(
      "Cassa in legno originale",
    );
    expect(etichettaConfezioneOriginale("nessuna_confezione_originale")).toBe(
      "Nessuna confezione originale",
    );
    expect(etichettaHandoff("dropoff_pudo")).toBe("Drop-off presso punto di consegna");
    expect(etichettaHandoff("ritiro_domicilio")).toBe("Ritiro a domicilio");
    for (const etichetta of Object.values(ETICHETTA_CONFEZIONE_ORIGINALE)) {
      expect(etichetta).toBeString();
      expect(etichetta.length).toBeGreaterThan(0);
    }
  });

  it("non trasforma l'annuncio legacy in «nessuna confezione originale»", () => {
    // NULL è il terzo stato: nessuno ha dichiarato niente. Confonderlo con la
    // prima etichetta significherebbe attestare al posto del venditore che
    // quella bottiglia non ha cofanetto.
    expect(confezioneOriginaleTipoDaDb(null)).toBeNull();
    expect(confezioneOriginaleTipoDaDb(undefined)).toBeNull();
    expect(confezioneOriginaleTipoDaDb("")).toBeNull();
    expect(confezioneOriginaleTipoDaDb("cofanetto_originale")).toBe("cofanetto_originale");
    expect(handoffVenditoreDaDb(null)).toBeNull();
    expect(handoffVenditoreDaDb("dropoff_pudo")).toBe("dropoff_pudo");
  });
});

// ---------------------------------------------------------------------------
// C. Regole dello stato del wizard che vivono nel modulo puro
// ---------------------------------------------------------------------------

describe("le regole del passo Consegna", () => {
  it("consiglia il drop-off senza sceglierlo al posto del venditore", () => {
    expect(HANDOFF_CONSIGLIATO).toBe("dropoff_pudo");
    // Lo stato iniziale del wizard resta senza risposta: è la stessa cosa che
    // la colonna dice nascendo NULL.
    expect(stato().handoffVenditore).toBeNull();
    expect(logisticaCompleta(stato())).toBeFalse();
  });

  it("non preseleziona alcun tipo di confezione", () => {
    expect(stato().confezioneOriginaleTipo).toBeNull();
    expect(messaggioLogisticaMancante(stato())).toBe(MANCA_CONFEZIONE);
  });

  it("nomina la confezione mancante prima dell'anteprima", () => {
    const senzaTipo = stato({ handoffVenditore: "dropoff_pudo" });
    expect(logisticaCompleta(senzaTipo)).toBeFalse();
    expect(messaggioLogisticaMancante(senzaTipo)).toBe(MANCA_CONFEZIONE);
  });

  it("nomina la consegna mancante prima dell'anteprima", () => {
    const senzaHandoff = stato({ confezioneOriginaleTipo: "cofanetto_originale" });
    expect(logisticaCompleta(senzaHandoff)).toBeFalse();
    expect(messaggioLogisticaMancante(senzaHandoff)).toBe(MANCA_HANDOFF);
  });

  it("accetta «nessuna confezione originale» senza chiedere fotografie", () => {
    const scelto = stato({
      confezioneOriginaleTipo: "nessuna_confezione_originale",
      handoffVenditore: "ritiro_domicilio",
    });
    expect(logisticaCompleta(scelto)).toBeTrue();
    expect(messaggioLogisticaMancante(scelto)).toBeNull();
    expect(ammetteFotoConfezione("nessuna_confezione_originale")).toBeFalse();
    expect(ammetteFotoConfezione(null)).toBeFalse();
    expect(ammetteFotoConfezione("cofanetto_originale")).toBeTrue();
  });

  it("non dichiara più di quattro fotografie della confezione", () => {
    expect(MAX_FOTO_CONFEZIONE).toBe(4);
    const troppe = stato({
      confezioneOriginaleTipo: "cassa_legno_originale",
      fotoConfezione: FOTO(6),
      handoffVenditore: "dropoff_pudo",
    });
    expect(normalizzaLogistica(troppe).confezioneOriginaleFoto).toHaveLength(4);
  });

  it("lascia cadere le fotografie quando il tipo non le ammette", () => {
    // La funzione SQL rifiuta con 22023 un array non vuoto senza confezione:
    // qui lo stato non arriva nemmeno a produrre quella chiamata.
    const cambiato = stato({
      confezioneOriginaleTipo: "nessuna_confezione_originale",
      fotoConfezione: FOTO(2),
      handoffVenditore: "dropoff_pudo",
    });
    expect(normalizzaLogistica(cambiato).confezioneOriginaleFoto).toEqual([]);
    expect(haLogisticaDaSalvare(stato({ fotoConfezione: FOTO(2) }))).toBeFalse();
  });
});

// ---------------------------------------------------------------------------
// D. Ordine di scrittura
// ---------------------------------------------------------------------------

type Traccia = string[];

const doppi = (
  esiti: { dichiara?: EsitoLogistica; pubblica?: EsitoLogistica } = {},
): {
  traccia: Traccia;
  dichiarazioni: DichiarazioneLogistica[];
  dichiaraLogistica: (id: string, d: DichiarazioneLogistica) => Promise<EsitoLogistica>;
  pubblica: (id: string) => Promise<EsitoLogistica>;
} => {
  const traccia: Traccia = [];
  const dichiarazioni: DichiarazioneLogistica[] = [];
  return {
    traccia,
    dichiarazioni,
    dichiaraLogistica: async (_id, dichiarazione) => {
      traccia.push("dichiara");
      dichiarazioni.push(dichiarazione);
      return esiti.dichiara ?? ok;
    },
    pubblica: async () => {
      traccia.push("pubblica");
      return esiti.pubblica ?? ok;
    },
  };
};

describe("l'ordine di scrittura della pubblicazione", () => {
  it("dichiara la logistica prima di pubblicare", async () => {
    const { traccia, dichiarazioni, dichiaraLogistica, pubblica } = doppi();
    const esito = await pubblicaConLogistica({
      listingId: ANNUNCIO,
      dichiarazione: normalizzaLogistica(
        stato({
          confezioneOriginaleTipo: "cofanetto_originale",
          fotoConfezione: FOTO(1),
          handoffVenditore: "dropoff_pudo",
        }),
      ),
      dichiaraLogistica,
      pubblica,
    });

    expect(esito.ok).toBeTrue();
    expect(traccia).toEqual(["dichiara", "pubblica"]);
    expect(dichiarazioni[0]).toEqual({
      confezioneOriginaleTipo: "cofanetto_originale",
      confezioneOriginaleFoto: FOTO(1),
      handoffVenditore: "dropoff_pudo",
    });
  });

  it("non pubblica se la dichiarazione fallisce", async () => {
    const { traccia, dichiaraLogistica, pubblica } = doppi({
      dichiara: { ok: false, error: "Annuncio non trovato." },
    });
    const esito = await pubblicaConLogistica({
      listingId: ANNUNCIO,
      dichiarazione: normalizzaLogistica(
        stato({
          confezioneOriginaleTipo: "cofanetto_originale",
          handoffVenditore: "dropoff_pudo",
        }),
      ),
      dichiaraLogistica,
      pubblica,
    });

    expect(esito).toEqual({ ok: false, error: "Annuncio non trovato." });
    expect(traccia).toEqual(["dichiara"]);
  });

  it("non racconta una pubblicazione che non è avvenuta", async () => {
    const { traccia, dichiaraLogistica, pubblica } = doppi({
      pubblica: { ok: false, error: "Annuncio non pubblicabile." },
    });
    const esito = await pubblicaConLogistica({
      listingId: ANNUNCIO,
      dichiarazione: normalizzaLogistica(
        stato({
          confezioneOriginaleTipo: "cofanetto_originale",
          handoffVenditore: "dropoff_pudo",
        }),
      ),
      dichiaraLogistica,
      pubblica,
    });

    // I metadati restano sulla bozza: è uno stato legittimo, e il fallimento
    // non va mascherato da successo.
    expect(esito).toEqual({ ok: false, error: "Annuncio non pubblicabile." });
    expect(traccia).toEqual(["dichiara", "pubblica"]);
  });

  it("salva una bozza intatta senza scrivere nulla", async () => {
    const { traccia, dichiaraLogistica } = doppi();
    const esito = await salvaLogisticaBozza({
      listingId: ANNUNCIO,
      stato: stato(),
      dichiaraLogistica,
    });

    expect(esito.ok).toBeTrue();
    expect(traccia).toEqual([]);
  });

  it("persiste la bozza incompleta che una risposta ce l'ha", async () => {
    const { traccia, dichiarazioni, dichiaraLogistica } = doppi();
    const esito = await salvaLogisticaBozza({
      listingId: ANNUNCIO,
      stato: stato({ handoffVenditore: "ritiro_domicilio" }),
      dichiaraLogistica,
    });

    expect(esito.ok).toBeTrue();
    expect(traccia).toEqual(["dichiara"]);
    expect(dichiarazioni[0]).toEqual({
      confezioneOriginaleTipo: null,
      confezioneOriginaleFoto: [],
      handoffVenditore: "ritiro_domicilio",
    });
  });

  it("riporta l'errore della dichiarazione al salvataggio della bozza", async () => {
    const { dichiaraLogistica } = doppi({ dichiara: { ok: false, error: "Annuncio non trovato." } });
    const esito = await salvaLogisticaBozza({
      listingId: ANNUNCIO,
      stato: stato({ confezioneOriginaleTipo: "cofanetto_originale" }),
      dichiaraLogistica,
    });

    expect(esito).toEqual({ ok: false, error: "Annuncio non trovato." });
  });
});
