/**
 * Ciò che il dominio logistico WP6A **non** deve contenere, misurato sulla
 * sorgente.
 *
 * Questi non sono controlli di stile: un nome di corriere cablato, un prezzo
 * commerciale nel seed o una seconda copia dell'8% sono difetti che nessun
 * test di comportamento vede, perché il codice funzionerebbe benissimo. Si
 * vedono solo guardando il testo del file.
 */

import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const repository = join(import.meta.dir, "../../../..");
const leggi = (percorso: string) => readFileSync(join(repository, percorso), "utf8");

const MIGRAZIONE = "supabase/migrations/20260930090000_logistics_economic_foundation.sql";
const QUOTE_SERVICE = "frontend-next/src/services/logistics/logistics-quote-service.ts";
const CONFIG_SERVICE = "frontend-next/src/services/logistics/logistics-config-service.ts";

// Un divieto si cerca nel codice, non nella prosa che lo spiega: questi file
// *parlano* di payout e di corrieri proprio per dire che non li toccano.
// L'atomo temperato evita che il match scavalchi il proprio `*/`.
const senzaCommentiTs = (sorgente: string) =>
  sorgente.replace(/\/\*(?:(?!\*\/)[\s\S])*\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");
const senzaCommentiSql = (sorgente: string) => sorgente.replace(/^\s*--.*$/gm, "");

const migrazione = leggi(MIGRAZIONE);
const quoteService = senzaCommentiTs(leggi(QUOTE_SERVICE));
const configService = senzaCommentiTs(leggi(CONFIG_SERVICE));
const runtime = [
  { nome: MIGRAZIONE, sorgente: senzaCommentiSql(migrazione) },
  { nome: QUOTE_SERVICE, sorgente: quoteService },
  { nome: CONFIG_SERVICE, sorgente: configService },
];

describe("WP6A — nessun fornitore commerciale nel runtime", () => {
  // I confini di parola servono: «gel» vive dentro «congelata» e «mbe» dentro
  // «number». Cercare la sottostringa nuda produrrebbe allarmi che non
  // riguardano nessun fornitore.
  const vietati = [
    /\bVigoroso\b/i,
    /\bUmbria\s+Hub\b/i,
    /\bBRT\b/i,
    /\bSDA\b/i,
    /\bPoste\s+Italiane\b/i,
    /\bGLS\b/i,
    /\bGEL\b/i,
    /\bMBE\b/i,
    /\bUPS\b/i,
    /\bSendcloud\b/i,
    /\bShippyPro\b/i,
  ];

  for (const { nome, sorgente } of runtime) {
    it(`${nome} non nomina alcun corriere o fornitore reale`, () => {
      for (const vietato of vietati) {
        expect(vietato.test(sorgente)).toBe(false);
      }
    });
  }

  it("i codici fornitore restano configurazione, non costanti del motore", () => {
    // `provider_code` è una colonna e un parametro: mai un elenco cablato di
    // valori ammessi. Un `check (provider_code in (...))` sarebbe esattamente
    // il difetto che WP6A vuole evitare.
    expect(/provider_code\s+in\s*\(/i.test(migrazione)).toBe(false);
    expect(/service_code\s+in\s*\(/i.test(migrazione)).toBe(false);
  });
});

describe("WP6A — nessuna integrazione con vettori o storage", () => {
  for (const { nome, sorgente } of runtime) {
    it(`${nome} non chiama servizi esterni`, () => {
      expect(sorgente).not.toContain("getPublicUrl");
      expect(sorgente).not.toContain("fetch(");
      expect(sorgente).not.toContain("https://");
      expect(sorgente).not.toContain("http_post");
      expect(sorgente).not.toContain("pg_net");
    });
  }
});

describe("WP6A — il legacy resta dov'è", () => {
  it("la migrazione non altera né reinterpreta `packaging_options`", () => {
    for (const vietato of [
      /alter\s+table\s+(public\.)?packaging_options/i,
      /drop\s+table\s+.*packaging_options/i,
      /insert\s+into\s+(public\.)?packaging_options/i,
      /update\s+(public\.)?packaging_options/i,
      /delete\s+from\s+(public\.)?packaging_options/i,
      /create\s+or\s+replace\s+view\s+(public\.)?public_packaging_options/i,
    ]) {
      expect(vietato.test(migrazione)).toBe(false);
    }
  });

  it("la migrazione non tocca checkout, pagamenti, payout o saldo", () => {
    for (const vietato of [
      /create\s+or\s+replace\s+function\s+public\.order_checkout_reserve/i,
      /alter\s+table\s+(public\.)?orders/i,
      /alter\s+table\s+(public\.)?payments/i,
      /alter\s+table\s+(public\.)?payouts/i,
      /alter\s+table\s+(public\.)?balance_/i,
      /insert\s+into\s+(public\.)?payments/i,
      /insert\s+into\s+(public\.)?payouts/i,
      /update\s+(public\.)?orders\b/i,
    ]) {
      expect(vietato.test(migrazione)).toBe(false);
    }
  });

  it("i servizi logistici non chiamano porte di checkout o pagamento", () => {
    for (const sorgente of [quoteService, configService]) {
      expect(sorgente).not.toContain("order_checkout_reserve");
      expect(sorgente).not.toContain("payout");
      expect(sorgente).not.toContain("stripe");
      expect(sorgente).not.toContain("balance_");
    }
  });
});

describe("WP6A — una sola autorità sulla commissione", () => {
  it("il motore rilegge la commissione dal marketplace invece di ricalcolarla", () => {
    expect(migrazione).toContain("private.marketplace_config_corrente()");
    expect(migrazione).toContain("private.marketplace_totale_cents(");
  });

  it("nessuna seconda copia dell'8% nel dominio logistico", () => {
    for (const vietato of [
      /logistics_commission_rate/i,
      /vinea_commission_percent/i,
      /marketplace_fee_8/i,
      /commission_bps\s+integer/i,
    ]) {
      expect(vietato.test(migrazione)).toBe(false);
    }
    // 800 bps non deve comparire come costante del dominio logistico: il
    // margine si legge da `marketplace_config`, non si riscrive qui.
    expect(/default\s+800\b/.test(migrazione)).toBe(false);
  });
});

describe("WP6A — nessun prezzo commerciale nel seed", () => {
  it("la migrazione non inserisce SKU, tariffe, costi, pack o stock", () => {
    for (const vietato of [
      /insert\s+into\s+private\.logistics_packaging_skus/i,
      /insert\s+into\s+private\.logistics_shipping_rates/i,
      /insert\s+into\s+private\.logistics_rate_surcharges\s*\(\s*rate_id[\s\S]{0,200}?values/i,
      /insert\s+into\s+private\.logistics_fulfillment_costs/i,
      /insert\s+into\s+private\.logistics_pack_definitions/i,
      /insert\s+into\s+private\.logistics_packaging_stock/i,
    ]) {
      // Le `insert` dentro le porte admin sono un'altra cosa: quelle scrivono
      // ciò che un amministratore manda, non un listino deciso qui. Si
      // distinguono perché non hanno letterali economici accanto.
      const occorrenze = migrazione.match(new RegExp(vietato.source, "gi")) ?? [];
      for (const occorrenza of occorrenze) {
        const posizione = migrazione.indexOf(occorrenza);
        const intorno = migrazione.slice(posizione, posizione + 900);
        expect(/private\.logistics_json_/.test(intorno)).toBe(true);
      }
    }
  });

  it("la configurazione di preventivo seminata è a zero", () => {
    const seed = migrazione.match(
      /insert\s+into\s+private\.logistics_quote_config[\s\S]{0,400}?;/i,
    );
    expect(seed).not.toBeNull();
    const testo = seed?.[0] ?? "";
    // Un buffer seminato diverso da zero sarebbe una decisione commerciale
    // presa dalla migrazione invece che dalla configurazione.
    expect(/select\s+0\s*,\s*0\s*,/.test(testo)).toBe(true);
  });
});

describe("WP6A — le porte restano chiuse", () => {
  it("ogni funzione pubblica del dominio è SECURITY DEFINER con search_path vuoto", () => {
    const porte = migrazione.match(/create\s+or\s+replace\s+function\s+public\.(\w+)/gi) ?? [];
    expect(porte.length).toBeGreaterThanOrEqual(10);
    for (const porta of porte) {
      const posizione = migrazione.indexOf(porta);
      const intestazione = migrazione.slice(posizione, posizione + 400);
      expect(intestazione).toContain("security definer");
      expect(intestazione).toContain("set search_path = ''");
    }
  });

  it("nessuna tabella autoritativa è raggiungibile da anon o authenticated", () => {
    expect(/grant\s+[^;]*\s+on\s+private\.logistics/i.test(migrazione)).toBe(false);
    expect(migrazione).toContain("revoke all on private.%I from anon");
    expect(migrazione).toContain("revoke all on private.%I from authenticated");
  });

  it("le porte admin verificano il ruolo nel database", () => {
    const admin = migrazione.match(/create\s+or\s+replace\s+function\s+public\.admin_logistics_\w+/gi) ?? [];
    expect(admin).toHaveLength(7);
    for (const porta of admin) {
      const posizione = migrazione.indexOf(porta);
      const corpo = migrazione.slice(posizione, posizione + 900);
      expect(corpo).toContain("private.logistics_admin_richiedi()");
    }
  });

  it("i servizi non derivano alcun permesso per conto proprio", () => {
    for (const sorgente of [quoteService, configService]) {
      expect(sorgente).not.toContain("isAdmin");
      expect(sorgente).not.toContain("user_roles");
      expect(sorgente).not.toContain("localStorage");
    }
  });
});
