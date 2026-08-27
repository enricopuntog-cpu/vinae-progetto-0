import { describe, expect, it } from "bun:test";
import {
  creaDatiCheckout,
  destinazioneSaldoOnly,
  OPZIONI_IMBALLAGGIO_BETA,
  passiCheckout,
  stimaCheckout,
  validaPassoCheckout,
} from "@/lib/beta/checkout";

describe("checkout beta deterministico", () => {
  it("crea uno stato locale senza dati finanziari", () => {
    expect(creaDatiCheckout("utente@example.test")).toEqual({
      email: "utente@example.test",
      telefono: "",
      destinatario: "",
      via: "",
      cap: "",
      citta: "",
      provincia: "",
      deliveryMode: "spedizione",
      imballaggioCodice: "nessuno",
      metodoPagamento: "carta",
    });
  });

  it("include l'imballaggio quando la relativa UI è visibile", () => {
    expect(passiCheckout(true)).toEqual(["contatti", "consegna", "imballaggio", "pagamento"]);
  });

  it("raggiunge comunque il pagamento quando l'imballaggio è nascosto", () => {
    expect(passiCheckout(false)).toEqual(["contatti", "consegna", "pagamento"]);
  });

  it("rifiuta contatti incompleti", () => {
    expect(validaPassoCheckout("contatti", creaDatiCheckout("non-email"))).toEqual({
      email: "Inserisci un indirizzo email valido.",
      telefono: "Inserisci un numero di telefono valido.",
    });
  });

  it("accetta contatti validi", () => {
    const dati = { ...creaDatiCheckout("utente@example.test"), telefono: "+39 333-1234567" };
    expect(validaPassoCheckout("contatti", dati)).toEqual({});
  });

  it("valida tutti i campi della spedizione", () => {
    const errori = validaPassoCheckout("consegna", creaDatiCheckout());
    expect(Object.keys(errori).sort()).toEqual(["cap", "citta", "destinatario", "provincia", "via"]);
  });

  it("accetta un indirizzo italiano completo", () => {
    const dati = {
      ...creaDatiCheckout(),
      destinatario: "Ada Vigna",
      via: "Via Roma 1",
      cap: "10100",
      citta: "Torino",
      provincia: "TO",
    };
    expect(validaPassoCheckout("consegna", dati)).toEqual({});
  });

  it("non richiede un indirizzo per il ritiro concordato", () => {
    const dati = { ...creaDatiCheckout(), deliveryMode: "consegna_mano" as const };
    expect(validaPassoCheckout("consegna", dati)).toEqual({});
  });

  it("espone soltanto opzioni locali fake a costo zero", () => {
    expect(OPZIONI_IMBALLAGGIO_BETA).toHaveLength(3);
    expect(OPZIONI_IMBALLAGGIO_BETA.every((opzione) => opzione.provider === "fake")).toBeTrue();
    expect(OPZIONI_IMBALLAGGIO_BETA.every((opzione) => opzione.prezzoCents === 0)).toBeTrue();
  });

  it("calcola un riepilogo stabile senza mutare il prezzo dell'imballaggio", () => {
    const stima = stimaCheckout(100, "kit_domicilio");
    expect(stima).toEqual({
      prezzoCents: 10000,
      commissioneCents: 686,
      imballaggioCents: 0,
      totaleCents: 10686,
    });
  });
});

describe("atterraggio di un ordine pagato interamente con il saldo Vinea", () => {
  it("porta sulla lista degli acquisti, che è una pagina che esiste", () => {
    expect(destinazioneSaldoOnly("ord-1")).toBe("/acquisti?checkout=saldo&orderId=ord-1");
  });

  it("non rimanda più al dettaglio ordine usato prima di questa modifica", () => {
    expect(destinazioneSaldoOnly("ord-1").startsWith("/acquisti?")).toBe(true);
    expect(destinazioneSaldoOnly("ord-1")).not.toInclude("/ordine/");
  });

  it("codifica l'identificativo invece di lasciarlo aggiungere parametri", () => {
    expect(destinazioneSaldoOnly("a&b=c")).toBe("/acquisti?checkout=saldo&orderId=a%26b%3Dc");
  });
});
