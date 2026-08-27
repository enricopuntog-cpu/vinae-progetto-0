import { describe, expect, it } from "bun:test";
import {
  DIMENSIONE_MASSIMA_DOCUMENTO,
  MIME_DOCUMENTO_QUALIFICA,
  percorsoDocumento,
  validaDocumento,
  validaQualifica,
} from "@/lib/qualifiche/validazione";

const OWNER = "d1a00000-0000-4000-8000-000000000001";
const QUALIFICA = "d1b00000-0000-4000-8000-000000000002";
const FILE = "d1c00000-0000-4000-8000-000000000003";

const campi = (over: Partial<Parameters<typeof validaQualifica>[0]> = {}) => ({
  titolo: "Sommelier professionista",
  enteEmittente: "Associazione Italiana Sommelier",
  paese: "",
  credentialReference: "",
  issuedOn: "",
  expiresOn: "",
  ...over,
});

const fileFinto = (tipo: string, dimensione: number): File =>
  ({ type: tipo, size: dimensione, name: "prova" }) as unknown as File;

describe("validaQualifica", () => {
  it("normalizza i facoltativi vuoti in null e taglia gli spazi", () => {
    const esito = validaQualifica(campi({ titolo: "  Enologo  ", enteEmittente: " Ordine " }));
    expect(esito).toEqual({
      valido: true,
      valore: {
        titolo: "Enologo",
        enteEmittente: "Ordine",
        paese: null,
        credentialReference: null,
        issuedOn: null,
        expiresOn: null,
      },
    });
  });

  it("pretende titolo ed ente: una qualifica anonima non è una qualifica", () => {
    expect(validaQualifica(campi({ titolo: " " })).valido).toBe(false);
    expect(validaQualifica(campi({ enteEmittente: "" })).valido).toBe(false);
  });

  it("il paese sono due lettere, normalizzate in maiuscolo", () => {
    const esito = validaQualifica(campi({ paese: "it" }));
    expect(esito.valido && esito.valore.paese).toBe("IT");
    expect(validaQualifica(campi({ paese: "Italia" })).valido).toBe(false);
    expect(validaQualifica(campi({ paese: "I1" })).valido).toBe(false);
  });

  it("rifiuta una data inesistente, non solo una malformata", () => {
    expect(validaQualifica(campi({ issuedOn: "2024-02-31" })).valido).toBe(false);
    expect(validaQualifica(campi({ issuedOn: "01/06/2019" })).valido).toBe(false);
    expect(validaQualifica(campi({ issuedOn: "2024-02-29" })).valido).toBe(true);
  });

  it("una scadenza non può precedere il rilascio", () => {
    expect(
      validaQualifica(campi({ issuedOn: "2020-01-01", expiresOn: "2019-12-31" })).valido,
    ).toBe(false);
    expect(validaQualifica(campi({ issuedOn: "2020-01-01", expiresOn: "2020-01-01" })).valido).toBe(
      true,
    );
    // Solo la scadenza, senza rilascio: legittimo, e non c'è nulla da confrontare.
    expect(validaQualifica(campi({ expiresOn: "2030-01-01" })).valido).toBe(true);
  });
});

describe("validaDocumento", () => {
  it("ammette i soli tre tipi del bucket privato", () => {
    for (const mime of MIME_DOCUMENTO_QUALIFICA) {
      expect(validaDocumento(fileFinto(mime, 1024)).valido).toBe(true);
    }
    for (const mime of ["image/webp", "application/zip", "text/html", ""]) {
      expect(validaDocumento(fileFinto(mime, 1024)).valido).toBe(false);
    }
  });

  it("ferma il file vuoto e quello oltre i dieci megabyte", () => {
    expect(validaDocumento(fileFinto("application/pdf", 0)).valido).toBe(false);
    expect(
      validaDocumento(fileFinto("application/pdf", DIMENSIONE_MASSIMA_DOCUMENTO)).valido,
    ).toBe(true);
    expect(
      validaDocumento(fileFinto("application/pdf", DIMENSIONE_MASSIMA_DOCUMENTO + 1)).valido,
    ).toBe(false);
  });

  it("l'estensione segue il tipo, e non il nome del file", () => {
    const casi: [string, string][] = [
      ["application/pdf", "pdf"],
      ["image/jpeg", "jpg"],
      ["image/png", "png"],
    ];
    for (const [mime, estensione] of casi) {
      const esito = validaDocumento(fileFinto(mime, 10));
      expect(esito.valido && esito.estensione).toBe(estensione);
    }
  });
});

describe("percorsoDocumento", () => {
  it("compone `<titolare>/<qualifica>/<file>.<ext>`", () => {
    expect(percorsoDocumento(OWNER, QUALIFICA, FILE, "pdf")).toBe(
      `${OWNER}/${QUALIFICA}/${FILE}.pdf`,
    );
  });

  it("rifiuta identificativi che non sono uuid: un percorso è una cartella", () => {
    expect(percorsoDocumento("../altro", QUALIFICA, FILE, "pdf")).toBeNull();
    expect(percorsoDocumento(OWNER, "..", FILE, "pdf")).toBeNull();
    expect(percorsoDocumento(OWNER, QUALIFICA, "file", "pdf")).toBeNull();
  });

  it("rifiuta un'estensione fuori dalle tre ammesse", () => {
    expect(percorsoDocumento(OWNER, QUALIFICA, FILE, "exe")).toBeNull();
    expect(percorsoDocumento(OWNER, QUALIFICA, FILE, "pdf.exe")).toBeNull();
  });
});
