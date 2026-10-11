import { describe, expect, it } from "bun:test";
import {
  PARTNER_STATI,
  azioneRichiedeMotivo,
  azioniAmmesse,
  datiDaPartner,
  linkInvito,
  messaggioErrorePartner,
  normalizzaPartitaIva,
  parseInvito,
  parsePartner,
  parsePartnerAdmin,
  partitaIvaValida,
  tokenDaFrammento,
  validaDatiPartner,
} from "@/lib/partner/partner";

const TOKEN = "a".repeat(32) + "0123456789abcdef0123456789abcdef";

const rigaPartner = {
  id: "p1",
  stato: "in_verifica",
  ragione_sociale: "Enoteca Srl",
  nome_commerciale: "Enoteca",
  partita_iva: "12345678903",
  paese: "IT",
  sede_indirizzo: "Via Roma 1",
  sede_cap: "12051",
  sede_citta: "Alba",
  sede_provincia: "CN",
  email_commerciale: "info@enoteca.it",
  tipologia: "enoteca",
  inviato_verifica_at: "2026-10-11T10:00:00Z",
  attivo_dal: null,
  sospeso_at: null,
  revocato_at: null,
  ultimo_motivo: null,
  created_at: "2026-10-11T09:00:00Z",
  updated_at: "2026-10-11T10:00:00Z",
};

describe("partita IVA (stesso algoritmo della porta SQL)", () => {
  it("accetta cifre di controllo corrette", () => {
    expect(partitaIvaValida("12345678903")).toBe(true);
    expect(partitaIvaValida("01234567897")).toBe(true);
    expect(partitaIvaValida("00000000000")).toBe(true);
  });

  it("rifiuta cifra di controllo errata e formati non a 11 cifre", () => {
    expect(partitaIvaValida("12345678901")).toBe(false);
    expect(partitaIvaValida("1234567890")).toBe(false);
    expect(partitaIvaValida("IT12345678903")).toBe(false);
    expect(partitaIvaValida("1234567890a")).toBe(false);
  });

  it("normalizza prefisso IT e spazi", () => {
    expect(normalizzaPartitaIva(" it 1234567 8903 ")).toBe("12345678903");
  });
});

describe("transizioni mostrate all'amministrazione", () => {
  it("rispecchiano la tabella del guardiano SQL", () => {
    expect(azioniAmmesse("invitato")).toEqual(["revoca"]);
    expect(azioniAmmesse("in_verifica")).toEqual(["approva", "restituisci", "revoca"]);
    expect(azioniAmmesse("attivo")).toEqual(["sospendi", "revoca"]);
    expect(azioniAmmesse("sospeso")).toEqual(["riattiva", "revoca"]);
    expect(azioniAmmesse("revocato")).toEqual([]);
  });

  it("chiedono un motivo per restituzione, sospensione e revoca", () => {
    expect(azioneRichiedeMotivo("restituisci")).toBe(true);
    expect(azioneRichiedeMotivo("sospendi")).toBe(true);
    expect(azioneRichiedeMotivo("revoca")).toBe(true);
    expect(azioneRichiedeMotivo("approva")).toBe(false);
    expect(azioneRichiedeMotivo("riattiva")).toBe(false);
  });

  it("revocato è terminale", () => {
    expect(PARTNER_STATI.filter((s) => azioniAmmesse(s).length === 0)).toEqual(["revocato"]);
  });
});

describe("token d'invito nel frammento", () => {
  it("costruisce il link con il token nel frammento, mai in query", () => {
    const link = linkInvito("https://vineawineclub.com/", TOKEN);
    expect(link).toBe(`https://vineawineclub.com/partner/invito#t=${TOKEN}`);
    expect(new URL(link).search).toBe("");
  });

  it("legge solo token di 64 esadecimali, normalizzando le maiuscole", () => {
    expect(tokenDaFrammento(`#t=${TOKEN.toUpperCase()}`)).toBe(TOKEN);
    expect(tokenDaFrammento("#t=abc")).toBeNull();
    expect(tokenDaFrammento("")).toBeNull();
    expect(tokenDaFrammento(`#x=${TOKEN}`)).toBeNull();
  });
});

describe("validazione di cortesia dei dati", () => {
  it("segnala solo i campi compilati e non validi", () => {
    const vuoti = validaDatiPartner(datiDaPartner(null));
    expect(vuoti.errori).toEqual({});
    expect(vuoti.completo).toBe(false);

    const { errori } = validaDatiPartner({
      ...datiDaPartner(null),
      partitaIva: "12345678901",
      sedeCap: "123",
      sedeProvincia: "Cuneo",
      emailCommerciale: "non-email",
    });
    expect(Object.keys(errori).sort()).toEqual(["emailCommerciale", "partitaIva", "sedeCap", "sedeProvincia"]);
  });

  it("è completo solo con tutti i campi e la tipologia", () => {
    const partner = parsePartner(rigaPartner);
    const dati = datiDaPartner(partner);
    expect(validaDatiPartner(dati)).toEqual({ errori: {}, completo: true });
    expect(validaDatiPartner({ ...dati, tipologia: null }).completo).toBe(false);
  });
});

describe("parsing delle risposte RPC", () => {
  it("accetta un Partner ben formato e scarta stati o tipologie sconosciute", () => {
    expect(parsePartner(rigaPartner)?.stato).toBe("in_verifica");
    expect(parsePartner({ ...rigaPartner, stato: "approvata" })).toBeNull();
    expect(parsePartner({ ...rigaPartner, tipologia: "pizzeria" })?.tipologia).toBeNull();
    expect(parsePartner(null)).toBeNull();
  });

  it("la riga admin richiede titolare ed email d'invito", () => {
    expect(parsePartnerAdmin(rigaPartner)).toBeNull();
    const admin = parsePartnerAdmin({
      ...rigaPartner,
      titolare_id: "u1",
      titolare_email: "u1@x.test",
      titolare_username: "u1",
      invito_email: "u1@x.test",
    });
    expect(admin?.titolareEmail).toBe("u1@x.test");
  });

  it("l'invito non porta mai il token, nemmeno se la risposta lo contenesse", () => {
    const invito = parseInvito({
      id: "i1",
      email: "u1@x.test",
      stato: "valido",
      scade_at: "2026-10-25T00:00:00Z",
      created_at: "2026-10-11T00:00:00Z",
      token: TOKEN,
    });
    expect(invito).not.toBeNull();
    expect(JSON.stringify(invito)).not.toContain(TOKEN);
    expect(parseInvito({ id: "i1", email: "x", stato: "boh", scade_at: "a", created_at: "b" })).toBeNull();
  });
});

describe("messaggi d'errore", () => {
  it("traduce gli hint stabili delle porte", () => {
    expect(messaggioErrorePartner({ code: "42501", hint: "invito_email_diversa" }, "x")).toContain(
      "altro indirizzo email",
    );
    expect(messaggioErrorePartner({ code: "P0001", hint: "invito_scaduto" }, "x")).toContain("scaduto");
  });

  it("non mostra testi di PostgreSQL per errori non previsti", () => {
    expect(
      messaggioErrorePartner({ code: "23505", message: "duplicate key value violates unique constraint" }, "Riprova."),
    ).toBe("Riprova.");
    expect(messaggioErrorePartner({ code: "42501", message: "permission denied for table partners" }, "x")).toBe(
      "Operazione non consentita.",
    );
  });
});
