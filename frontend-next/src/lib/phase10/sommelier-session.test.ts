import { describe, expect, it } from "bun:test";
import {
  SESSION_ID_VALIDO,
  nuovoSessionId,
  sessionIdPersistente,
  type Deposito,
} from "@/lib/phase10/sommelier-session";

/** Deposito finto: registra le scritture e può essere reso ostile. */
const deposito = (
  iniziale: string | null,
  opzioni: { leggeSolleva?: boolean; scriveSolleva?: boolean } = {},
): Deposito & { scritture: string[] } => {
  const scritture: string[] = [];
  return {
    scritture,
    getItem: () => {
      if (opzioni.leggeSolleva) throw new Error("deposito non disponibile");
      return iniziale;
    },
    setItem: (_chiave, valore) => {
      if (opzioni.scriveSolleva) throw new Error("deposito in sola lettura");
      scritture.push(valore);
    },
  };
};

describe("identificativo di sessione del Sommelier", () => {
  it("ogni identificativo coniato passa il vincolo scritto nella migrazione e nella function", () => {
    // Il formato è `s-<base36>-<base36>` e la parte casuale può risultare
    // vuota: si estrae molte volte proprio perché il caso raro è quello che
    // conta, e un identificativo fuori formato darebbe un 23514 dal database
    // invece di un messaggio comprensibile.
    for (let i = 0; i < 2000; i += 1) {
      expect(nuovoSessionId()).toMatch(SESSION_ID_VALIDO);
    }
  });

  it("riusa l'identificativo già depositato senza riscriverlo", () => {
    const d = deposito("s-abcdef-xyz123");
    expect(sessionIdPersistente(d)).toBe("s-abcdef-xyz123");
    expect(d.scritture).toEqual([]);
  });

  it("sostituisce un residuo fuori formato invece di riusarlo", () => {
    // Un identificativo con caratteri non ammessi passerebbe il controllo del
    // browser e verrebbe rifiutato dal database: va scartato qui.
    const d = deposito("sessione con spazi e àccenti");
    const id = sessionIdPersistente(d);
    expect(id).not.toBe("sessione con spazi e àccenti");
    expect(id).toMatch(SESSION_ID_VALIDO);
    expect(d.scritture).toEqual([id]);
  });

  it("scarta un identificativo troppo corto", () => {
    const d = deposito("ab");
    expect(sessionIdPersistente(d)).toMatch(SESSION_ID_VALIDO);
    expect(d.scritture).toHaveLength(1);
  });

  it("un deposito che solleva in lettura non impedisce di aprire il pannello", () => {
    const d = deposito("s-abcdef-xyz123", { leggeSolleva: true });
    expect(sessionIdPersistente(d)).toMatch(SESSION_ID_VALIDO);
  });

  it("un deposito che solleva in scrittura dà comunque una conversazione", () => {
    // Navigazione privata: l'identificativo vive quanto la scheda, e questo è
    // meglio di un pannello che non si apre.
    const d = deposito(null, { scriveSolleva: true });
    expect(sessionIdPersistente(d)).toMatch(SESSION_ID_VALIDO);
  });

  it("senza deposito (render sul server) conia comunque un identificativo valido", () => {
    expect(sessionIdPersistente(null)).toMatch(SESSION_ID_VALIDO);
  });

  it("due conversazioni consecutive non condividono identificativo", () => {
    expect(sessionIdPersistente(null)).not.toBe(sessionIdPersistente(null));
  });
});
