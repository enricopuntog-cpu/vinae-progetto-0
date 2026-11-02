import { describe, expect, it } from "bun:test";
import { parseOrdineAccessorio, testoStatoOrdine, type OrdineAccessorio } from "@/lib/accessori-ordini/ordine";
import { ordineValido, ordineVenditore } from "@/lib/accessori-ordini/ordine.fixture";
import {
  chiaveAperturaPagamento,
  chiavePublishableValida,
  esitoDaStripe,
  faseDaOrdine,
  indirizzoRitorno,
  valutaPagabilita,
} from "@/lib/accessori-ordini/pagamento";

const ordine = (extra: Record<string, unknown> = {}): OrdineAccessorio => {
  const o = parseOrdineAccessorio(ordineValido(extra));
  if (!o) throw new Error("ordine di prova non valido");
  return o;
};
const PK = "pk_test_abcdefgh12345678";
const PRIMA = Date.parse("2026-11-02T10:05:00Z");
const PAGATO = { stato: "pagato", pagatoAt: "2026-11-02T10:05:00Z" };
const ID = "12f50000-0000-4000-8000-0000000000a1";

describe("valutaPagabilita", () => {
  const ok = { azioniAbilitate: true, chiavePublishable: PK, adesso: PRIMA };

  it("acquirente, in attesa, non scaduto, gate e chiave presenti: pagabile", () => {
    expect(valutaPagabilita({ ordine: ordine(), ...ok })).toEqual({ pagabile: true });
  });

  it("gate spento: nessun pulsante", () => {
    expect(valutaPagabilita({ ordine: ordine(), ...ok, azioniAbilitate: false })).toEqual({
      pagabile: false,
      motivo: "gate_spento",
    });
  });

  it("chiave publishable mancante, vuota o segreta: non pagabile", () => {
    for (const k of [null, undefined, "", "sk_test_abcdefgh12345678", "pk_abc"]) {
      expect(valutaPagabilita({ ordine: ordine(), ...ok, chiavePublishable: k })).toEqual({
        pagabile: false,
        motivo: "chiave_mancante",
      });
    }
    expect(chiavePublishableValida(PK)).toBe(true);
  });

  it("prenotazione scaduta per orario: nessuna nuova apertura", () => {
    expect(valutaPagabilita({ ordine: ordine(), ...ok, adesso: Date.parse("2026-11-02T10:15:01Z") })).toEqual({
      pagabile: false,
      motivo: "prenotazione_scaduta",
    });
  });

  it("ordine già pagato, annullato o scaduto: non pagabile", () => {
    expect(valutaPagabilita({ ordine: ordine(PAGATO), ...ok }).pagabile).toBe(false);
    expect(valutaPagabilita({ ordine: ordine({ stato: "scaduto" }), ...ok }).pagabile).toBe(false);
    expect(
      valutaPagabilita({ ordine: ordine({ stato: "annullato", motivoChiusura: "acquirente" }), ...ok }).pagabile,
    ).toBe(false);
  });

  it("il venditore non può pagare", () => {
    const v = parseOrdineAccessorio(ordineVenditore());
    expect(v).not.toBeNull();
    expect(valutaPagabilita({ ordine: v as OrdineAccessorio, ...ok })).toEqual({
      pagabile: false,
      motivo: "non_acquirente",
    });
  });
});

describe("esitoDaStripe", () => {
  it("succeeded e processing sono in verifica, mai pagato", () => {
    expect(esitoDaStripe({ paymentIntent: { status: "succeeded" } })).toEqual({ tipo: "in_verifica" });
    expect(esitoDaStripe({ paymentIntent: { status: "processing" } })).toEqual({ tipo: "in_verifica" });
  });

  it("requires_action chiede l autenticazione", () => {
    expect(esitoDaStripe({ paymentIntent: { status: "requires_action" } })).toEqual({ tipo: "richiede_azione" });
  });

  it("errore carta: messaggio di Stripe; errore del fornitore: generico, senza dettagli", () => {
    expect(esitoDaStripe({ error: { type: "card_error", message: "Carta rifiutata." } })).toEqual({
      tipo: "errore",
      messaggio: "Carta rifiutata.",
    });
    const g = esitoDaStripe({ error: { type: "api_error", message: "req_123 interno" } });
    expect(g.tipo === "errore" && g.messaggio.includes("req_123")).toBe(false);
  });

  it("stato inatteso o assente: errore", () => {
    expect(esitoDaStripe({}).tipo).toBe("errore");
    expect(esitoDaStripe({ paymentIntent: { status: "requires_payment_method" } }).tipo).toBe("errore");
  });
});

describe("rilettura autoritativa", () => {
  it("solo un ordine pagato del database vale come pagato", () => {
    expect(faseDaOrdine(ordine())).toBe("in_attesa");
    expect(faseDaOrdine(ordine(PAGATO))).toBe("pagato");
    expect(faseDaOrdine(ordine({ stato: "scaduto" }))).toBe("chiuso");
  });

  it("il testo distingue pagamento del fornitore e simulato", () => {
    expect(testoStatoOrdine(ordine(PAGATO))).toBe("Pagamento confermato");
    expect(testoStatoOrdine(ordine({ ...PAGATO, pagamentoSimulato: true }))).toBe("Pagato (simulato)");
  });
});

describe("idempotenza e ritorno", () => {
  it("la chiave è stabile per ordine (doppio click, refresh, retry) e valida per la Edge Function", () => {
    expect(chiaveAperturaPagamento(ID)).toBe(chiaveAperturaPagamento(ID));
    expect(chiaveAperturaPagamento(ID)).toMatch(/^[A-Za-z0-9._:-]{8,128}$/);
  });

  it("il ritorno riporta sempre all ordine, solo su origini https o localhost", () => {
    expect(indirizzoRitorno("https://vinea.example", ID)).toBe(
      `https://vinea.example/ordini-accessori/${ID}?checkout=ritorno`,
    );
    expect(indirizzoRitorno("http://localhost:3000", ID)).toContain("/ordini-accessori/");
    expect(indirizzoRitorno("http://127.0.0.1:3100", ID)).toContain("/ordini-accessori/");
    expect(indirizzoRitorno("http://evil.example", ID)).toBeNull();
    expect(indirizzoRitorno("https://vinea.example/percorso", ID)).toBeNull();
    expect(indirizzoRitorno("non un url", ID)).toBeNull();
  });
});
