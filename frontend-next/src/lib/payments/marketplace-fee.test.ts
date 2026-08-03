import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  calcolaCommissione,
  percentualeLeggibile,
  scomposizioneOrdine,
} from "@/lib/payments/marketplace-fee";

const MIGRAZIONE = readFileSync(
  join(
    import.meta.dir,
    "../../../../supabase/migrations/20260803150000_phase_7b_stripe_connect_marketplace.sql",
  ),
  "utf8",
);

describe("calcolo della commissione", () => {
  it("applica la percentuale SOPRA il prezzo del venditore", () => {
    // 100,00 € al 5%: il venditore incassa 100,00, il compratore paga 105,00.
    // Se la commissione fosse dentro il prezzo, il totale resterebbe 10000.
    const scomposizione = calcolaCommissione(10000, 500);
    expect(scomposizione.prezzoVenditoreCents).toBe(10000);
    expect(scomposizione.commissioneCents).toBe(500);
    expect(scomposizione.totaleCents).toBe(10500);
  });

  it("arrotonda al centesimo, mezzo per eccesso come round() in Postgres", () => {
    // 123,45 € al 5% fa 617,25 centesimi: la metà esatta va per eccesso.
    expect(calcolaCommissione(12345, 500).commissioneCents).toBe(617);
    // 1,50 € al 5% fa 7,5 centesimi.
    expect(calcolaCommissione(150, 500).commissioneCents).toBe(8);
    // Un prezzo che non produce frazioni non deve muoversi.
    expect(calcolaCommissione(2000, 500).commissioneCents).toBe(100);
  });

  it("ammette la commissione a zero e rifiuta gli estremi non validi", () => {
    expect(calcolaCommissione(10000, 0)).toEqual({
      prezzoVenditoreCents: 10000,
      commissioneCents: 0,
      totaleCents: 10000,
      commissioneBps: 0,
    });
    expect(() => calcolaCommissione(10000, 5001)).toThrow(RangeError);
    expect(() => calcolaCommissione(10000, -1)).toThrow(RangeError);
    expect(() => calcolaCommissione(0, 500)).toThrow(RangeError);
    expect(() => calcolaCommissione(10.5, 500)).toThrow(RangeError);
  });

  it("mostra la percentuale in forma leggibile", () => {
    expect(percentualeLeggibile(500)).toBe("5%");
    expect(percentualeLeggibile(1250)).toBe("12.50%");
  });
});

// Il comportamento richiesto esplicitamente: la percentuale è congelata alla
// creazione dell'ordine e una modifica successiva della configurazione non lo
// tocca. È il caso in cui un ricalcolo sarebbe indistinguibile da una lettura
// finché la configurazione non cambia — ed è per questo che si prova cambiandola.
describe("percentuale congelata contro configurazione cambiata dopo", () => {
  const ordineNatoAlCinquePerCento = {
    prezzo_cents: 10000,
    commissione_bps: 500,
    commissione_cents: 500,
    totale_cents: 10500,
  };

  it("legge dall'ordine e non dalla configurazione corrente", () => {
    const scomposizione = scomposizioneOrdine(ordineNatoAlCinquePerCento);
    expect(scomposizione.commissioneBps).toBe(500);
    expect(scomposizione.commissioneCents).toBe(500);
    expect(scomposizione.totaleCents).toBe(10500);

    // La configurazione passa al 12%: un ordine nuovo pagherebbe 1200, questo no.
    const nuovoPreventivo = calcolaCommissione(10000, 1200);
    expect(nuovoPreventivo.commissioneCents).toBe(1200);
    expect(scomposizioneOrdine(ordineNatoAlCinquePerCento).commissioneCents).toBe(500);
    expect(scomposizioneOrdine(ordineNatoAlCinquePerCento).totaleCents).toBe(10500);
  });

  it("non prende una percentuale come parametro: ricalcolare non è esprimibile", () => {
    expect(scomposizioneOrdine.length).toBe(1);
  });

  it("restituisce la riga anche se fosse incoerente, senza correggerla", () => {
    // Correggere qui mostrerebbe al compratore un numero diverso da quello
    // addebitato. Il posto per accorgersene è la griglia SQL, non il browser.
    const incoerente = {
      prezzo_cents: 10000,
      commissione_bps: 500,
      commissione_cents: 999,
      totale_cents: 10999,
    };
    expect(scomposizioneOrdine(incoerente).commissioneCents).toBe(999);
  });
});

// Come per payment-state.test.ts: questi casi non eseguono SQL — nessun Postgres
// è disponibile in postazione — ma leggono il file di migrazione vero, così una
// divergenza fra le due implementazioni non passa inosservata.
describe("accordo fra la copia TypeScript e lo schema SQL", () => {
  it("la configurazione iniziale è 5% e 14 giorni", () => {
    const seed = MIGRAZIONE.match(
      /insert into public\.marketplace_config \(commissione_bps, auto_rilascio_giorni, nota\)\s*\nvalues \((\d+), (\d+),/,
    );
    expect(seed).not.toBeNull();
    expect(Number(seed![1])).toBe(500);
    expect(Number(seed![2])).toBe(14);
  });

  it("la RPC arrotonda con round() sulla stessa formula", () => {
    expect(MIGRAZIONE).toContain(
      "round(v_price::numeric * v_config.commissione_bps / 10000)::integer",
    );
  });

  it("il totale è generato come prezzo più commissione, non riscritto a mano", () => {
    expect(MIGRAZIONE).toContain(
      "generated always as (prezzo_cents + commissione_cents) stored",
    );
  });

  it("il pagamento addebita il totale e il payout trasferisce il solo prezzo", () => {
    expect(MIGRAZIONE).toContain("values (v_order.id, v_order.totale_cents, v_order.currency)");
    // Nel corpo di payout_prepara l'importo inserito è prezzo_cents: se
    // diventasse totale_cents, la piattaforma trasferirebbe anche la commissione.
    const prepara = MIGRAZIONE.slice(MIGRAZIONE.indexOf("function public.payout_prepara"));
    expect(prepara).toContain("v_order.prezzo_cents, v_order.currency, 'in_corso'");
    expect(prepara).not.toContain("v_order.totale_cents");
  });

  it("il massimo consentito ai punti base è lo stesso in entrambe le copie", () => {
    expect(MIGRAZIONE).toContain("check (commissione_bps between 0 and 5000)");
  });
});
