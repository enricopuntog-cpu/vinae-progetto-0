import { describe, expect, it } from "bun:test";
import {
  etichettaStatoQualifica,
  qualificaConSpunta,
  qualificaEliminabile,
  qualificaInviabile,
  qualificaModificabile,
  qualificaRitirabile,
  spiegazioneStato,
} from "@/lib/qualifiche/etichette";
import type { QualificaProfessionale, QualificaProfessionaleStato } from "@/services/types";

const STATI: QualificaProfessionaleStato[] = [
  "bozza",
  "inviata",
  "approvata",
  "rifiutata",
  "ritirata",
];

const qualifica = (over: Partial<QualificaProfessionale> = {}): QualificaProfessionale => ({
  id: "d1b00000-0000-4000-8000-000000000002",
  titolo: "Enologo",
  enteEmittente: "Ordine",
  paese: null,
  credentialReference: null,
  issuedOn: null,
  expiresOn: null,
  stato: "bozza",
  submittedAt: null,
  reviewedAt: null,
  createdAt: "2026-08-01T09:00:00Z",
  documenti: [],
  valida: false,
  ...over,
});

const documento = {
  id: "d1c00000-0000-4000-8000-000000000003",
  storagePath: "a/b/c.pdf",
  mimeType: "application/pdf",
  sizeBytes: 10,
  createdAt: "2026-08-01T09:00:00Z",
};

describe("etichettaStatoQualifica", () => {
  it("nomina ogni stato senza promettere un'identità verificata", () => {
    const parole = STATI.map(etichettaStatoQualifica);
    expect(parole).toEqual(["Bozza", "In verifica", "Approvata", "Non approvata", "Ritirata"]);
    expect(parole.join(" ")).not.toMatch(/KYC|identit|certificazione/i);
  });
});

describe("permessi mostrati", () => {
  it("si modifica solo una bozza", () => {
    for (const stato of STATI) {
      expect(qualificaModificabile(qualifica({ stato }))).toBe(stato === "bozza");
    }
  });

  it("si invia una bozza con almeno una prova", () => {
    expect(qualificaInviabile(qualifica({ documenti: [] }))).toBe(false);
    expect(qualificaInviabile(qualifica({ documenti: [documento] }))).toBe(true);
    expect(qualificaInviabile(qualifica({ stato: "inviata", documenti: [documento] }))).toBe(false);
  });

  it("si ritira solo una richiesta già inviata: mai una bozza, mai un esito", () => {
    // La bozza non è una richiesta: non c'è niente da cui ritirarsi, e offrire
    // «Ritira» lì produceva una riga `ritirata` di una pratica mai inviata.
    for (const stato of STATI) {
      expect(qualificaRitirabile(qualifica({ stato }))).toBe(stato === "inviata");
    }
  });
});

describe("qualificaEliminabile", () => {
  it("si elimina solo una bozza: inviata, approvata, rifiutata e ritirata restano", () => {
    for (const stato of STATI) {
      expect(qualificaEliminabile(qualifica({ stato }))).toBe(stato === "bozza");
    }
  });

  it("eliminabile e ritirabile non si sovrappongono mai", () => {
    // Sono le due metà dello stesso gesto in momenti diversi: prima dell'invio
    // si cancella, dopo l'invio si rinuncia lasciando traccia.
    for (const stato of STATI) {
      const q = qualifica({ stato });
      expect(qualificaEliminabile(q) && qualificaRitirabile(q)).toBe(false);
    }
  });

  it("non guarda i documenti: una bozza vuota si elimina come una con allegati", () => {
    expect(qualificaEliminabile(qualifica({ stato: "bozza", documenti: [] }))).toBe(true);
  });
});

describe("qualificaConSpunta", () => {
  it("è la regola del database, non una data confrontata nel browser", () => {
    // Approvata ma scaduta: il database ha già detto `valida: false`, e qui non
    // si ricalcola nulla.
    expect(qualificaConSpunta(qualifica({ stato: "approvata", expiresOn: "2000-01-01" }))).toBe(
      false,
    );
    expect(
      qualificaConSpunta(qualifica({ stato: "approvata", expiresOn: "2000-01-01", valida: true })),
    ).toBe(true);
  });
});

describe("spiegazioneStato", () => {
  it("il rifiuto è neutro e non riporta il ragionamento di chi ha verificato", () => {
    const testo = spiegazioneStato(qualifica({ stato: "rifiutata" })) ?? "";
    expect(testo).toInclude("non è stata approvata");
    expect(testo).not.toMatch(/provider|confidence|reasoning|falso|sospett/i);
  });

  it("una bozza e un'approvazione valida non hanno niente da spiegare", () => {
    expect(spiegazioneStato(qualifica({ stato: "bozza" }))).toBeNull();
    expect(spiegazioneStato(qualifica({ stato: "approvata", valida: true }))).toBeNull();
  });

  it("un'approvazione scaduta dice che non compare più sul profilo pubblico", () => {
    expect(spiegazioneStato(qualifica({ stato: "approvata", valida: false }))).toInclude("scaduta");
  });
});
