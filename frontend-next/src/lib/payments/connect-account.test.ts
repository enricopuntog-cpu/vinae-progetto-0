import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  derivaSellerEnabled,
  eventoApplicabile,
  faseOnboarding,
  type StatoAccountVenditore,
} from "@/lib/payments/connect-account";

const MIGRAZIONE = readFileSync(
  join(
    import.meta.dir,
    "../../../../supabase/migrations/20260803150000_phase_7b_stripe_connect_marketplace.sql",
  ),
  "utf8",
);

const abilitato: StatoAccountVenditore = {
  chargesEnabled: true,
  payoutsEnabled: true,
  detailsSubmitted: true,
  requisitiPendenti: [],
  disabledReason: null,
};

describe("derivazione del ruolo venditore", () => {
  it("è vero solo con incassi e versamenti abilitati insieme", () => {
    expect(derivaSellerEnabled(abilitato)).toBe(true);
    expect(derivaSellerEnabled({ ...abilitato, chargesEnabled: false })).toBe(false);
    expect(derivaSellerEnabled({ ...abilitato, payoutsEnabled: false })).toBe(false);
    expect(derivaSellerEnabled(null)).toBe(false);
  });

  it("non guarda details_submitted né i requisiti pendenti", () => {
    // Il fornitore può dichiarare abilitato un account con requisiti ancora
    // aperti ma non scaduti: la sua parola su charges/payouts è ciò che conta,
    // e aggiungere condizioni nostre farebbe divergere il ruolo dal trigger.
    expect(
      derivaSellerEnabled({
        ...abilitato,
        detailsSubmitted: false,
        requisitiPendenti: ["individual.id_number"],
      }),
    ).toBe(true);
  });
});

describe("fase di onboarding mostrata all'interfaccia", () => {
  it("distingue il caso parziale, che è reale e non un dettaglio", () => {
    // Incassi abilitati e versamenti no: il venditore può vendere ma non essere
    // pagato. Chiamarlo "abilitato" nasconderebbe il problema proprio a chi
    // dovrebbe risolverlo.
    expect(faseOnboarding({ ...abilitato, payoutsEnabled: false })).toBe("parziale");
    expect(faseOnboarding({ ...abilitato, chargesEnabled: false })).toBe("parziale");
  });

  it("copre le altre fasi", () => {
    expect(faseOnboarding(null)).toBe("assente");
    expect(faseOnboarding(abilitato)).toBe("abilitato");
    expect(
      faseOnboarding({
        chargesEnabled: false,
        payoutsEnabled: false,
        detailsSubmitted: false,
        requisitiPendenti: ["individual.first_name"],
        disabledReason: "requirements.past_due",
      }),
    ).toBe("da_completare");
    expect(
      faseOnboarding({
        chargesEnabled: false,
        payoutsEnabled: false,
        detailsSubmitted: true,
        requisitiPendenti: [],
        disabledReason: null,
      }),
    ).toBe("in_verifica");
  });
});

describe("protezione dagli eventi tardivi", () => {
  it("accetta il primo evento e quelli successivi", () => {
    expect(eventoApplicabile(null, "2026-08-03T10:00:00.000Z")).toBe(true);
    expect(eventoApplicabile("2026-08-03T10:00:00.000Z", "2026-08-03T10:00:01.000Z")).toBe(true);
  });

  it("rifiuta un evento più vecchio dell'ultimo applicato", () => {
    // È lo scenario che riaprirebbe un account appena chiuso: due eventi emessi
    // a distanza di secondi e consegnati in ordine inverso.
    expect(eventoApplicabile("2026-08-03T10:00:00.000Z", "2026-08-03T09:59:59.000Z")).toBe(false);
  });

  it("accetta due eventi con lo stesso istante", () => {
    // La deduplicazione su (provider, event_id) ha già escluso che siano lo
    // stesso evento: rifiutare il secondo perderebbe un aggiornamento vero.
    expect(eventoApplicabile("2026-08-03T10:00:00.000Z", "2026-08-03T10:00:00.000Z")).toBe(true);
  });

  it("rifiuta una data non interpretabile", () => {
    expect(eventoApplicabile(null, "non-una-data")).toBe(false);
  });
});

describe("accordo fra la copia TypeScript e lo schema SQL", () => {
  it("il trigger deriva seller_enabled dalla stessa congiunzione", () => {
    const sync = MIGRAZIONE.slice(
      MIGRAZIONE.indexOf("function private.seller_enabled_sync"),
      MIGRAZIONE.indexOf("create trigger seller_payout_accounts_seller_enabled"),
    );
    expect(sync).toContain("if new.charges_enabled and new.payouts_enabled then");
    expect(sync).toContain("insert into public.user_roles (user_id, role)");
    expect(sync).toContain("'seller_enabled'");
    expect(sync).toContain("delete from public.user_roles");
  });

  it("il ruolo si sincronizza da un trigger e non solo dentro una RPC", () => {
    // Dentro una RPC il vincolo varrebbe per chi la chiama; su un trigger vale
    // anche per service_role, che le RPC può scavalcarle.
    expect(MIGRAZIONE).toContain(
      "after insert or update of charges_enabled, payouts_enabled",
    );
  });

  it("la RPC di applicazione rifiuta gli eventi tardivi con lo stesso confronto", () => {
    const applica = MIGRAZIONE.slice(
      MIGRAZIONE.indexOf("function public.seller_payout_account_apply_event"),
    );
    expect(applica).toContain("v_created_at < v_account.provider_event_at");
    expect(applica).toContain("return 'stale'");
    expect(applica).toContain("on conflict (provider, event_id) do nothing");
    expect(applica).toContain("return 'duplicate'");
  });

  it("l'identificativo dell'account non è leggibile da un ruolo client", () => {
    const grant = MIGRAZIONE.match(
      /grant select \(([^)]*)\) on public\.seller_payout_accounts to authenticated/,
    );
    expect(grant).not.toBeNull();
    expect(grant![1]).not.toContain("provider_account_id");
    expect(grant![1]).toContain("charges_enabled");
  });
});
