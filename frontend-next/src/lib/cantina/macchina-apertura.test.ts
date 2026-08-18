import { describe, expect, it } from "bun:test";
import {
  STATO_INIZIALE,
  riduttoreApertura,
  versoDegustazione,
  type EventoApertura,
  type StatoApertura,
} from "@/lib/cantina/macchina-apertura";
import { percorsoApertura } from "@/lib/cantina/apertura";

/** Applica una sequenza di eventi, come farebbe l'utente uno dopo l'altro. */
const svolgi = (eventi: EventoApertura[], da: StatoApertura = STATO_INIZIALE) =>
  eventi.reduce(riduttoreApertura, da);

const PERCORSO_DIRETTO = percorsoApertura(null);
const PERCORSO_CON_RIMOZIONE = percorsoApertura({ id: "l-1", stato: "attivo" });
const PERCORSO_BLOCCATO = percorsoApertura({ id: "l-1", stato: "riservato" });

describe("nessuna apertura senza conferma esplicita", () => {
  it("non apre premendo soltanto il comando, nel percorso diretto", () => {
    const stato = svolgi([{ tipo: "premi", percorso: PERCORSO_DIRETTO }]);
    expect(stato.fase).toBe("apertura");
    expect(versoDegustazione(stato)).toBe(false);
  });

  it("non apre premendo soltanto il comando, nel percorso con rimozione", () => {
    const stato = svolgi([{ tipo: "premi", percorso: PERCORSO_CON_RIMOZIONE }]);
    expect(stato.fase).toBe("rimozione");
    expect(versoDegustazione(stato)).toBe(false);
  });

  it("non apre nemmeno dopo che la rimozione e' riuscita", () => {
    // Il punto piu' insidioso: la rimozione e' andata a buon fine e la
    // bottiglia sarebbe tecnicamente apribile. Senza la seconda conferma non
    // si apre lo stesso.
    const stato = svolgi([
      { tipo: "premi", percorso: PERCORSO_CON_RIMOZIONE },
      { tipo: "rimozione-riuscita" },
    ]);
    expect(stato.fase).toBe("apertura");
    expect(stato.rimozioneEseguita).toBe(true);
    expect(versoDegustazione(stato)).toBe(false);
  });

  it("apre solo dopo la conferma esplicita, nel percorso diretto", () => {
    const stato = svolgi([
      { tipo: "premi", percorso: PERCORSO_DIRETTO },
      { tipo: "conferma-apertura" },
    ]);
    expect(versoDegustazione(stato)).toBe(true);
  });

  it("apre solo dopo entrambe le conferme, nel percorso con rimozione", () => {
    const stato = svolgi([
      { tipo: "premi", percorso: PERCORSO_CON_RIMOZIONE },
      { tipo: "rimozione-riuscita" },
      { tipo: "conferma-apertura" },
    ]);
    expect(versoDegustazione(stato)).toBe(true);
  });

  it("ignora una conferma d'apertura che arrivi fuori dal suo dialogo", () => {
    // Difesa contro l'evento fuori sequenza: se `conferma-apertura` passasse
    // da "rimozione" o da "bloccato", la bottiglia si aprirebbe saltando la
    // domanda. Il riduttore non lo consente.
    for (const percorso of [PERCORSO_CON_RIMOZIONE, PERCORSO_BLOCCATO]) {
      const stato = svolgi([
        { tipo: "premi", percorso },
        { tipo: "conferma-apertura" },
      ]);
      expect(versoDegustazione(stato)).toBe(false);
    }
    expect(versoDegustazione(svolgi([{ tipo: "conferma-apertura" }]))).toBe(false);
  });
});

describe("annullare a meta', in ciascuno dei due dialoghi", () => {
  it("annullando il primo dialogo non rimuove e non apre", () => {
    const stato = svolgi([
      { tipo: "premi", percorso: PERCORSO_CON_RIMOZIONE },
      { tipo: "annulla" },
    ]);
    expect(stato.fase).toBe("inattivo");
    expect(stato.rimozioneEseguita).toBe(false);
    expect(versoDegustazione(stato)).toBe(false);
  });

  it("annullando il secondo dialogo non apre, ma la rimozione resta fatta", () => {
    // E' il caso che il primo dialogo deve annunciare: la rimozione e'
    // avvenuta e non si disfa, la bottiglia pero' resta chiusa. Se questo caso
    // dicesse `rimozioneEseguita: false` significherebbe che l'interfaccia sta
    // raccontando all'utente qualcosa di diverso da cio' che e' successo.
    const stato = svolgi([
      { tipo: "premi", percorso: PERCORSO_CON_RIMOZIONE },
      { tipo: "rimozione-riuscita" },
      { tipo: "annulla" },
    ]);
    expect(stato.fase).toBe("inattivo");
    expect(stato.rimozioneEseguita).toBe(true);
    expect(versoDegustazione(stato)).toBe(false);
  });

  it("annullando il secondo dialogo nel percorso diretto non apre", () => {
    const stato = svolgi([
      { tipo: "premi", percorso: PERCORSO_DIRETTO },
      { tipo: "annulla" },
    ]);
    expect(stato.fase).toBe("inattivo");
    expect(versoDegustazione(stato)).toBe(false);
  });

  it("ripremendo dopo un annullamento non richiede la rimozione gia' fatta", () => {
    const stato = svolgi([
      { tipo: "premi", percorso: PERCORSO_CON_RIMOZIONE },
      { tipo: "rimozione-riuscita" },
      { tipo: "annulla" },
      { tipo: "premi", percorso: PERCORSO_CON_RIMOZIONE },
    ]);
    // Va dritto alla seconda conferma: l'annuncio e' gia' fuori dalla vendita
    // e richiederne la rimozione sarebbe una domanda gia' risposta.
    expect(stato.fase).toBe("apertura");
    expect(versoDegustazione(stato)).toBe(false);
  });

  it("ripremendo dopo un annullamento del primo dialogo richiede ancora la rimozione", () => {
    const stato = svolgi([
      { tipo: "premi", percorso: PERCORSO_CON_RIMOZIONE },
      { tipo: "annulla" },
      { tipo: "premi", percorso: PERCORSO_CON_RIMOZIONE },
    ]);
    expect(stato.fase).toBe("rimozione");
    expect(stato.rimozioneEseguita).toBe(false);
  });
});

describe("percorso bloccato", () => {
  it("apre solo il dialogo informativo e non arriva mai all'apertura", () => {
    const stato = svolgi([{ tipo: "premi", percorso: PERCORSO_BLOCCATO }]);
    expect(stato.fase).toBe("bloccato");
    expect(versoDegustazione(stato)).toBe(false);
  });

  it("chiudendolo si torna al riposo senza effetti", () => {
    const stato = svolgi([
      { tipo: "premi", percorso: PERCORSO_BLOCCATO },
      { tipo: "annulla" },
    ]);
    expect(stato).toEqual(STATO_INIZIALE);
  });
});

describe("rimozione fallita", () => {
  it("non porta alla seconda conferma", () => {
    // listing_sospendi ha rifiutato: la bottiglia non e' apribile, quindi
    // chiedere «confermi l'apertura?» sarebbe una domanda a vuoto.
    const stato = svolgi([
      { tipo: "premi", percorso: PERCORSO_CON_RIMOZIONE },
      { tipo: "rimozione-fallita" },
    ]);
    expect(stato.fase).toBe("rimozione");
    expect(stato.rimozioneEseguita).toBe(false);
    expect(versoDegustazione(stato)).toBe(false);
  });

  it("una rimozione riuscita fuori sequenza non apre la seconda conferma", () => {
    const stato = svolgi([{ tipo: "rimozione-riuscita" }]);
    expect(stato).toEqual(STATO_INIZIALE);
  });
});
