import { describe, expect, it } from "bun:test";
import {
  chiaveIdempotenzaValida,
  messaggioOrdineAccessori,
  parseDisponibilita,
  parseElencoOrdini,
  parseOrdineAccessorio,
} from "./ordine";

import { ID_ANNUNCIO_PROVA as ANN, ID_ORDINE_PROVA as ID, ordineValido, ordineVenditore } from "./ordine.fixture";

describe("parseOrdineAccessorio", () => {
  it("legge un ordine coerente, con le voci separate", () => {
    const o = parseOrdineAccessorio(ordineValido());
    expect(o).not.toBeNull();
    expect(o?.stato).toBe("in_attesa_pagamento");
    expect(o?.commissioneCents).toBe(480);
    expect(o?.coperturaPagamentoCents).toBe(25);
    expect(o?.logistica?.totaleCents).toBe(1180);
    expect(o?.totaleAcquirenteCents).toBe(5685);
    expect(o?.controparte).toBe("ua");
    expect(o?.ricevoCents).toBeNull();
  });

  it("rifiuta somme che non tornano al centesimo", () => {
    expect(parseOrdineAccessorio(ordineValido({ totaleAcquirenteCents: 5000 }))).toBeNull();
    expect(
      parseOrdineAccessorio(ordineValido({ prezzo: { unitarioCents: 2000, quantita: 2, subtotaleCents: 3999 } })),
    ).toBeNull();
    expect(
      parseOrdineAccessorio(ordineValido({ logistica: { ...ordineValido().logistica, totaleCents: 1000 } })),
    ).toBeNull();
    // Quantità del prezzo diversa da quella dell'ordine.
    expect(
      parseOrdineAccessorio(ordineValido({ prezzo: { unitarioCents: 2000, quantita: 3, subtotaleCents: 6000 } })),
    ).toBeNull();
  });

  it("rifiuta stati e motivi sconosciuti o incoerenti", () => {
    expect(parseOrdineAccessorio(ordineValido({ stato: "rimborsato" }))).toBeNull();
    expect(parseOrdineAccessorio(ordineValido({ stato: "annullato", motivoChiusura: null }))).toBeNull();
    expect(parseOrdineAccessorio(ordineValido({ stato: "annullato", motivoChiusura: "fantasia" }))).toBeNull();
    expect(parseOrdineAccessorio(ordineValido({ stato: "in_attesa_pagamento", motivoChiusura: "acquirente" }))).toBeNull();
    expect(parseOrdineAccessorio(ordineValido({ stato: "annullato", motivoChiusura: "acquirente" }))?.stato).toBe(
      "annullato",
    );
  });

  it("uno scaduto non ancora chiuso dal database (solo per orario) è valido", () => {
    expect(parseOrdineAccessorio(ordineValido({ stato: "scaduto", motivoChiusura: null }))?.stato).toBe("scaduto");
    expect(parseOrdineAccessorio(ordineValido({ stato: "scaduto", motivoChiusura: "scadenza" }))?.motivoChiusura).toBe(
      "scadenza",
    );
  });

  it("pagato solo con data e pagamento simulato coerenti", () => {
    expect(parseOrdineAccessorio(ordineValido({ stato: "pagato", pagatoAt: null, pagamentoSimulato: true }))).toBeNull();
    expect(
      parseOrdineAccessorio(ordineValido({ stato: "pagato", pagatoAt: "2026-11-02T10:05:00Z", pagamentoSimulato: false })),
    ).toBeNull();
    expect(
      parseOrdineAccessorio(ordineValido({ stato: "in_attesa_pagamento", pagatoAt: "2026-11-02T10:05:00Z" })),
    ).toBeNull();
    const o = parseOrdineAccessorio(
      ordineValido({ stato: "pagato", pagatoAt: "2026-11-02T10:05:00Z", pagamentoSimulato: true }),
    );
    expect(o?.pagamentoSimulato).toBe(true);
  });

  it("rifiuta scadenze impossibili, identificativi malformati e destinazioni diverse dal punto di ritiro", () => {
    expect(parseOrdineAccessorio(ordineValido({ scadeAt: "2026-11-02T09:00:00Z" }))).toBeNull();
    expect(parseOrdineAccessorio(ordineValido({ id: "non-un-uuid" }))).toBeNull();
    expect(
      parseOrdineAccessorio(ordineValido({ logistica: { ...ordineValido().logistica, destinazione: "domicilio" } })),
    ).toBeNull();
    expect(parseOrdineAccessorio(ordineValido({ quantita: 0 }))).toBeNull();
    expect(parseOrdineAccessorio(ordineValido({ quantita: 121 }))).toBeNull();
    expect(parseOrdineAccessorio(null)).toBeNull();
    expect(parseOrdineAccessorio("ordine")).toBeNull();
  });

  it("il lato del venditore porta solo ciò che incassa; l'acquirente è noto solo a vendita avvenuta", () => {
    const prenotato = parseOrdineAccessorio(ordineVenditore());
    expect(prenotato?.ricevoCents).toBe(4000);
    expect(prenotato?.commissioneCents).toBeNull();
    expect(prenotato?.logistica).toBeNull();
    expect(prenotato?.totaleAcquirenteCents).toBeNull();
    expect(prenotato?.controparte).toBeNull();
    // Una prenotazione resta anonima: un acquirente nominato è una risposta inattesa.
    expect(parseOrdineAccessorio(ordineVenditore({ acquirente: { username: 'ub' } }))).toBeNull();
    const pagato = { stato: 'pagato', pagatoAt: '2026-11-02T10:05:00Z', pagamentoSimulato: true };
    expect(parseOrdineAccessorio(ordineVenditore({ ...pagato, acquirente: { username: 'ub' } }))?.controparte).toBe('ub');
    expect(parseOrdineAccessorio(ordineVenditore(pagato))).toBeNull();
    // Importo incassato incoerente, o voci dell'acquirente presenti: rifiutato.
    expect(parseOrdineAccessorio(ordineVenditore({ ricevi: { cents: 3999 } }))).toBeNull();
    expect(parseOrdineAccessorio(ordineVenditore({ ricevi: undefined }))).toBeNull();
    expect(parseOrdineAccessorio(ordineVenditore({ commissione: { cents: 480 } }))).toBeNull();
    expect(parseOrdineAccessorio(ordineVenditore({ totaleAcquirenteCents: 5685 }))).toBeNull();
    expect(parseOrdineAccessorio(ordineVenditore({ venditore: { username: 'ua' } }))).toBeNull();
    // E l'acquirente non riceve i campi del venditore.
    expect(parseOrdineAccessorio(ordineValido({ ricevi: { cents: 4000 } }))).toBeNull();
    expect(parseOrdineAccessorio(ordineValido({ acquirente: { username: 'ub' } }))).toBeNull();
  });
});

describe("parseElencoOrdini e parseDisponibilita", () => {
  it("l'elenco è tutto o niente", () => {
    expect(parseElencoOrdini([ordineValido(), ordineValido({ id: ANN })])?.length).toBe(2);
    expect(parseElencoOrdini([ordineValido(), { id: ID }])).toBeNull();
    expect(parseElencoOrdini({})).toBeNull();
    expect(parseElencoOrdini([])).toEqual([]);
  });

  it("una disponibilità prenotabile ha almeno un pezzo", () => {
    expect(parseDisponibilita({ disponibili: 3, prenotabile: true, motivo: null })).toEqual({
      disponibili: 3,
      prenotabile: true,
      motivo: null,
    });
    expect(parseDisponibilita({ disponibili: 0, prenotabile: true, motivo: null })).toBeNull();
    expect(parseDisponibilita({ disponibili: -1, prenotabile: false, motivo: "esaurito" })).toBeNull();
    expect(parseDisponibilita({ disponibili: 0, prenotabile: false, motivo: "checkout_non_attivo" })?.prenotabile).toBe(
      false,
    );
    expect(parseDisponibilita(null)).toBeNull();
  });
});

describe("chiavi e messaggi", () => {
  it("la chiave di idempotenza ha la forma attesa dal database", () => {
    expect(chiaveIdempotenzaValida("acc-12345678")).toBe(true);
    expect(chiaveIdempotenzaValida("corta")).toBe(false);
    expect(chiaveIdempotenzaValida("con spazi non ammessi")).toBe(false);
    expect(chiaveIdempotenzaValida("a".repeat(129))).toBe(false);
  });

  it("i rifiuti noti hanno parole, gli ignoti nessuna", () => {
    expect(messaggioOrdineAccessori("quantita_non_disponibile")).toContain("pezzi");
    expect(messaggioOrdineAccessori("prenotazione_aperta")).toContain("prenotazione");
    expect(messaggioOrdineAccessori("hint_inventato")).toBeNull();
  });
});
