import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  decidiRilascio,
  deveAutoRilasciare,
  scadenzaAutoRilascio,
  type IstantaneaAutoRilascio,
  type IstantaneaRilascio,
  type StatoPayout,
} from "@/lib/payments/release-policy";

const MIGRAZIONE = readFileSync(
  join(
    import.meta.dir,
    "../../../../supabase/migrations/20260803150000_phase_7b_stripe_connect_marketplace.sql",
  ),
  "utf8",
);

/**
 * La migrazione senza i commenti di riga. Serve dove si cerca una struttura e
 * non del testo: la prosa dei commenti contiene parentesi e punti e virgola, e
 * una regex che li incontra si ferma lì — lasciando passare come "corretta" una
 * divergenza vera. È esattamente il modo in cui questo test è già fallito una
 * volta senza che ci fosse alcun difetto nello schema.
 */
const STRUTTURA = MIGRAZIONE.replace(/--[^\n]*/g, "");

const rilasciabile: IstantaneaRilascio = {
  payoutStato: "in_attesa",
  contestatoAt: null,
  pagamentoStato: "paid",
  rimborsatoCents: 0,
  venditoreAbilitato: true,
};

const autoRilasciabile: IstantaneaAutoRilascio = {
  ordineStato: "consegnato",
  payoutStato: "trattenuto",
  contestatoAt: null,
  autoRilascioScadenza: "2026-08-01T00:00:00.000Z",
  pagamentoStato: "paid",
};

const ADESSO = new Date("2026-08-03T12:00:00.000Z");

describe("decisione di rilascio", () => {
  it("autorizza il trasferimento quando tutto è in ordine", () => {
    expect(decidiRilascio(rilasciabile)).toEqual({ esito: "da_trasferire" });
  });

  it("non rilascia finché i fondi sono solo trattenuti", () => {
    expect(decidiRilascio({ ...rilasciabile, payoutStato: "trattenuto" })).toEqual({
      esito: "non_dovuto",
      motivo: "trattenuto",
    });
  });

  it("riprova un trasferimento fallito", () => {
    // I fondi sono ancora sul balance della piattaforma: un fallimento non è
    // uno stato terminale, e la chiave di idempotenza protegge il ritentativo.
    expect(decidiRilascio({ ...rilasciabile, payoutStato: "fallito" })).toEqual({
      esito: "da_trasferire",
    });
  });
});

// Comportamento richiesto: la contestazione blocca il trasferimento.
describe("blocco su ordine contestato", () => {
  it("blocca il trasferimento appena esiste una contestazione", () => {
    expect(
      decidiRilascio({ ...rilasciabile, contestatoAt: "2026-08-02T10:00:00.000Z" }),
    ).toEqual({ esito: "bloccato", motivo: "ordine_contestato" });
  });

  it("blocca anche quando il payout è marcato bloccato senza data", () => {
    // È il caso del rimborso: `payment_apply_provider_event` porta il payout a
    // 'bloccato' senza aprire una contestazione del compratore.
    expect(decidiRilascio({ ...rilasciabile, payoutStato: "bloccato" })).toEqual({
      esito: "bloccato",
      motivo: "ordine_contestato",
    });
  });

  it("la contestazione vince su un incasso perfetto ma non su un trasferimento già fatto", () => {
    const contestato = { ...rilasciabile, contestatoAt: "2026-08-02T10:00:00.000Z" };
    expect(decidiRilascio(contestato).esito).toBe("bloccato");
    // Contestare dopo che il denaro è uscito non lo fa rientrare: l'uscita
    // idempotente viene prima di ogni altra valutazione.
    expect(decidiRilascio({ ...contestato, payoutStato: "trasferito" })).toEqual({
      esito: "gia_trasferito",
    });
  });

  it("blocca l'auto-rilascio di un ordine contestato anche a finestra scaduta", () => {
    expect(
      deveAutoRilasciare(
        { ...autoRilasciabile, contestatoAt: "2026-08-02T10:00:00.000Z" },
        ADESSO,
      ),
    ).toBe(false);
  });
});

// Comportamento richiesto: il rilascio è idempotente.
describe("idempotenza del rilascio", () => {
  it("un payout già trasferito non viene rifatto", () => {
    expect(decidiRilascio({ ...rilasciabile, payoutStato: "trasferito" })).toEqual({
      esito: "gia_trasferito",
    });
  });

  it("un trasferimento in corso non ne apre un secondo in parallelo", () => {
    // 'in_corso' resta rilasciabile perché un esecutore può essere morto fra la
    // preparazione e la chiamata al fornitore. Ciò che impedisce il doppio
    // pagamento non è lo stato: è la chiave di idempotenza, che il fornitore
    // riconosce.
    expect(decidiRilascio({ ...rilasciabile, payoutStato: "in_corso" })).toEqual({
      esito: "da_trasferire",
    });
    expect(MIGRAZIONE).toContain("'vinea-payout-' || replace(v_order.id::text, '-', '')");
  });

  it("nessuno stato produce due volte da_trasferire dopo un trasferimento", () => {
    const stati: StatoPayout[] = [
      "trattenuto",
      "in_attesa",
      "in_corso",
      "trasferito",
      "bloccato",
      "fallito",
    ];
    const dopoTrasferimento = stati.map((payoutStato) =>
      decidiRilascio({ ...rilasciabile, payoutStato }),
    );
    expect(dopoTrasferimento.filter((d) => d.esito === "gia_trasferito")).toHaveLength(1);
  });

  it("l'incasso non valido blocca prima di arrivare al fornitore", () => {
    expect(decidiRilascio({ ...rilasciabile, pagamentoStato: "processing" })).toEqual({
      esito: "bloccato",
      motivo: "incasso_non_valido",
    });
    expect(decidiRilascio({ ...rilasciabile, rimborsatoCents: 1 })).toEqual({
      esito: "bloccato",
      motivo: "incasso_non_valido",
    });
  });

  it("un venditore non abilitato non riceve nulla", () => {
    expect(decidiRilascio({ ...rilasciabile, venditoreAbilitato: false })).toEqual({
      esito: "bloccato",
      motivo: "venditore_non_abilitato",
    });
  });
});

// Comportamento richiesto: l'auto-rilascio non si esegue due volte.
describe("l'auto-rilascio non reclama due volte", () => {
  it("reclama un ordine consegnato con la finestra scaduta", () => {
    expect(deveAutoRilasciare(autoRilasciabile, ADESSO)).toBe(true);
  });

  it("non reclama prima della scadenza", () => {
    expect(
      deveAutoRilasciare(
        { ...autoRilasciabile, autoRilascioScadenza: "2026-08-04T00:00:00.000Z" },
        ADESSO,
      ),
    ).toBe(false);
  });

  it("smette di vederlo appena la prima esecuzione lo ha reclamato", () => {
    // È la condizione che porta il peso: dopo il primo giro payout_stato è
    // 'in_attesa', e nessuna esecuzione successiva lo riprende — nemmeno una
    // partita prima che il Transfer sia stato creato.
    const dopoIlPrimoGiro: IstantaneaAutoRilascio = {
      ...autoRilasciabile,
      ordineStato: "completato",
      payoutStato: "in_attesa",
    };
    expect(deveAutoRilasciare(dopoIlPrimoGiro, ADESSO)).toBe(false);
    // Anche tenendo lo stato ordine invariato, il solo payout_stato basta.
    expect(
      deveAutoRilasciare({ ...autoRilasciabile, payoutStato: "in_attesa" }, ADESSO),
    ).toBe(false);
  });

  it("nessuno stato di payout diverso da trattenuto è reclamabile", () => {
    const stati: StatoPayout[] = [
      "trattenuto",
      "in_attesa",
      "in_corso",
      "trasferito",
      "bloccato",
      "fallito",
    ];
    const reclamabili = stati.filter((payoutStato) =>
      deveAutoRilasciare({ ...autoRilasciabile, payoutStato }, ADESSO),
    );
    expect(reclamabili).toEqual(["trattenuto"]);
  });

  it("senza una scadenza registrata non parte nulla", () => {
    expect(
      deveAutoRilasciare({ ...autoRilasciabile, autoRilascioScadenza: null }, ADESSO),
    ).toBe(false);
  });

  it("un incasso non confermato non fa scattare la finestra", () => {
    expect(
      deveAutoRilasciare({ ...autoRilasciabile, pagamentoStato: "processing" }, ADESSO),
    ).toBe(false);
  });
});

describe("scadenza della finestra di verifica", () => {
  it("somma i giorni configurati alla consegna", () => {
    expect(scadenzaAutoRilascio(new Date("2026-08-03T00:00:00.000Z"), 14).toISOString()).toBe(
      "2026-08-17T00:00:00.000Z",
    );
  });

  it("rifiuta finestre fuori dai limiti dello schema", () => {
    expect(() => scadenzaAutoRilascio(new Date(), 0)).toThrow(RangeError);
    expect(() => scadenzaAutoRilascio(new Date(), 181)).toThrow(RangeError);
  });
});

// Anche qui: non si esegue SQL, si rilegge la migrazione vera perché una
// divergenza fra le due tavole di decisione non passi inosservata.
describe("accordo fra la copia TypeScript e lo schema SQL", () => {
  it("l'enum public.payout_stato elenca esattamente gli stati di questo modulo", () => {
    const blocco = STRUTTURA.match(/create type public\.payout_stato as enum \(([^)]*)\)/);
    expect(blocco).not.toBeNull();
    const valoriSql = [...blocco![1].matchAll(/'([a-z_]+)'/g)].map((m) => m[1]);
    expect(valoriSql.sort()).toEqual(
      ["trattenuto", "in_attesa", "in_corso", "trasferito", "bloccato", "fallito"].sort(),
    );
  });

  it("payout_prepara esce per prima cosa se il trasferimento è già avvenuto", () => {
    const prepara = MIGRAZIONE.slice(
      MIGRAZIONE.indexOf("function public.payout_prepara"),
      MIGRAZIONE.indexOf("function public.payout_registra_esito"),
    );
    expect(prepara.indexOf("gia_trasferito")).toBeLessThan(prepara.indexOf("ordine_contestato"));
    expect(prepara).toContain("v_order.contestato_at is not null");
    expect(prepara).toContain("v_account.charges_enabled or not v_account.payouts_enabled");
  });

  it("gli stati preparabili sono gli stessi delle due copie", () => {
    expect(MIGRAZIONE).toContain(
      "if v_order.payout_stato not in ('in_attesa', 'in_corso', 'fallito') then",
    );
  });

  it("l'auto-rilascio reclama con skip locked e solo ciò che è trattenuto", () => {
    const auto = MIGRAZIONE.slice(
      MIGRAZIONE.indexOf("function public.ordine_auto_rilascio_esegui"),
    );
    expect(auto).toContain("for update of o skip locked");
    expect(auto).toContain("o.payout_stato = 'trattenuto'");
    expect(auto).toContain("o.contestato_at is null");
    expect(auto).toContain("o.stato in ('consegnato', 'verifica')");
    expect(auto).toContain("p.stato = 'paid'");
  });

  it("una riga di payout per ordine, con chiave di idempotenza unica", () => {
    expect(MIGRAZIONE).toContain("order_id uuid not null unique references public.orders (id)");
    expect(MIGRAZIONE).toContain("idempotency_key text not null unique");
  });
});
