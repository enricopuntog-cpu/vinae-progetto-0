import { afterEach, describe, expect, it } from "bun:test";
import {
  ascoltaRichiesteSommelier,
  concediConsenso,
  consensoAttivo,
  contestoVinoDaAnnuncio,
  richiediSommelier,
  richiestaContestoServer,
  type ContestoUi,
} from "./sommelier-contesto-ui";

const UTENTE_A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const UTENTE_B = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const ANNUNCIO = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";

describe("consenso alla Cantina: legato a utente e sessione", () => {
  it("è inizialmente spento", () => {
    expect(consensoAttivo(null, UTENTE_A, "s-1234")).toBe(false);
  });

  it("si concede solo a un utente autenticato e con una sessione di conversazione", () => {
    expect(concediConsenso(null, "s-1234")).toBeNull();
    expect(concediConsenso(UTENTE_A, null)).toBeNull();
    expect(concediConsenso(UTENTE_A, "s-1234")).toEqual({ utenteId: UTENTE_A, sessionId: "s-1234" });
  });

  it("vale per quell'utente e quella sessione: altro utente (logout/cambio account) o altra sessione lo spengono", () => {
    const consenso = concediConsenso(UTENTE_A, "s-1234");
    expect(consensoAttivo(consenso, UTENTE_A, "s-1234")).toBe(true);
    expect(consensoAttivo(consenso, UTENTE_B, "s-1234")).toBe(false);
    expect(consensoAttivo(consenso, null, "s-1234")).toBe(false);
    expect(consensoAttivo(consenso, UTENTE_A, "s-altra")).toBe(false);
    expect(consensoAttivo(consenso, UTENTE_A, null)).toBe(false);
  });
});

describe("richiesta di contesto verso il server", () => {
  const vino: ContestoUi = { tipo: "vino", annuncioId: ANNUNCIO, etichetta: "Monfortino 2015" };
  const cantina: ContestoUi = { tipo: "cantina", vuota: false };

  it("nessun contesto: nessun campo, il Sommelier resta generale", () => {
    expect(richiestaContestoServer(null, false)).toBeUndefined();
    expect(richiestaContestoServer(null, true)).toBeUndefined();
  });

  it("il vino manda solo l'identificativo dell'annuncio, mai l'etichetta o attributi", () => {
    expect(richiestaContestoServer(vino, false)).toEqual({ tipo: "vino", annuncioId: ANNUNCIO });
    expect(JSON.stringify(richiestaContestoServer(vino, false))).not.toContain("Monfortino");
  });

  it("la Cantina senza consenso non genera nessuna richiesta di lettura", () => {
    expect(richiestaContestoServer(cantina, false)).toBeUndefined();
  });

  it("la Cantina con consenso manda il solo consenso, senza proprietario né inventario", () => {
    expect(richiestaContestoServer(cantina, true)).toEqual({ tipo: "cantina", consenso: true });
  });

  it("una Cantina vuota non chiede alcuna lettura nemmeno con consenso", () => {
    expect(richiestaContestoServer({ tipo: "cantina", vuota: true }, true)).toBeUndefined();
  });
});

describe("contesto dalla scheda dell'annuncio", () => {
  it("serve un identificativo di annuncio reale (uuid): dati dimostrativi non producono nessun pulsante", () => {
    expect(contestoVinoDaAnnuncio(ANNUNCIO, "Monfortino 2015")).toEqual({
      tipo: "vino",
      annuncioId: ANNUNCIO,
      etichetta: "Monfortino 2015",
    });
    expect(contestoVinoDaAnnuncio(undefined, "x")).toBeNull();
    expect(contestoVinoDaAnnuncio("barolo-monfortino-2015", "x")).toBeNull();
    expect(contestoVinoDaAnnuncio("", "x")).toBeNull();
  });

  it("l'etichetta è limitata e ripulita: è solo testo per l'interfaccia", () => {
    const c = contestoVinoDaAnnuncio(ANNUNCIO, `  ${"N".repeat(300)}\n`);
    expect(c?.tipo === "vino" && c.etichetta.length).toBeLessThanOrEqual(80);
  });
});

describe("apertura del Sommelier da una pagina", () => {
  const annulla: (() => void)[] = [];
  afterEach(() => {
    while (annulla.length) annulla.pop()!();
  });

  it("notifica i soli ascoltatori attivi, una volta ciascuno, con il contesto richiesto", () => {
    const visti: ContestoUi[] = [];
    annulla.push(ascoltaRichiesteSommelier((c) => visti.push(c)));
    richiediSommelier({ tipo: "cantina", vuota: false });
    richiediSommelier({ tipo: "vino", annuncioId: ANNUNCIO, etichetta: "x" });
    expect(visti.map((c) => c.tipo)).toEqual(["cantina", "vino"]);
  });

  it("dopo l'annullamento non arriva più niente", () => {
    const visti: ContestoUi[] = [];
    const stop = ascoltaRichiesteSommelier((c) => visti.push(c));
    stop();
    richiediSommelier({ tipo: "cantina", vuota: false });
    expect(visti).toHaveLength(0);
  });
});
