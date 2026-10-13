import { describe, expect, it } from "bun:test";
import {
  creaDatiCheckout,
  destinazioneSaldoOnly,
  OPZIONI_IMBALLAGGIO_BETA,
  passiCheckout,
  riepilogoCheckout,
  validaPassoCheckout,
} from "@/lib/beta/checkout";

describe("checkout beta deterministico", () => {
  it("crea uno stato locale senza dati finanziari", () => {
    expect(creaDatiCheckout("utente@example.test")).toEqual({
      email: "utente@example.test",
      telefono: "",
      deliveryMode: "spedizione",
      destinazione: "pudo",
      indirizzoId: null,
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

  it("il punto di ritiro è la destinazione predefinita e non chiede indirizzi", () => {
    expect(validaPassoCheckout("consegna", creaDatiCheckout())).toEqual({});
  });

  it("il domicilio richiede un indirizzo della rubrica", () => {
    const dati = { ...creaDatiCheckout(), destinazione: "home" as const };
    expect(validaPassoCheckout("consegna", dati)).toEqual({
      indirizzoId: "Scegli o aggiungi l'indirizzo di consegna.",
    });
    expect(validaPassoCheckout("consegna", { ...dati, indirizzoId: "ind-1" })).toEqual({});
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

  it("riepiloga il preventivo del database senza ricalcolarlo, imballaggio a parte", () => {
    const preventivo = {
      classe: "partner" as const,
      quantita: 1,
      prezzoUnitarioCents: 10000,
      subtotaleCents: 10000,
      commissioneCents: 1772,
      totaleCents: 11772,
      margineObiettivoBps: 1500,
      riferimentoPercentualeBps: 209,
      riferimentoFissoCents: 25,
    };
    expect(riepilogoCheckout(preventivo, 0)).toEqual({
      prezzoCents: 10000,
      commissioneCents: 1772,
      imballaggioCents: 0,
      logisticaCents: 0,
      feePagamentoCents: 0,
      totaleCents: 11772,
    });
  });

  it("senza preventivo non inventa un totale", () => {
    expect(riepilogoCheckout(null)).toBeNull();
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
