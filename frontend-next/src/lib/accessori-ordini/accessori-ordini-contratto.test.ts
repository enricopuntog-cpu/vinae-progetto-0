import { describe, expect, it } from "bun:test";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

/**
 * VPM-015B5A — contratto del checkout Accessori, scritto come test.
 *
 * La prenotazione non è un pagamento: nessun legame con Stripe, con le Edge
 * Function dei pagamenti o con gli ordini del vino; nessun importo, venditore o
 * quantità autoritativa deciso dal browser; nessun carrello multi-venditore.
 * Il contratto guarda il CODICE (non i commenti) e la migrazione, così che una
 * scorciatoia faccia fallire la build.
 */

const progetto = join(import.meta.dir, "../../..");
const radiceRepo = join(progetto, "..");
const leggi = (p: string) => readFileSync(join(progetto, p), "utf8");
const leggiRepo = (p: string) => readFileSync(join(radiceRepo, p), "utf8");
const senzaCommenti = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");
const senzaCommentiSql = (s: string) => s.replace(/--.*$/gm, "");
const ricorsivi = (d: string): string[] =>
  readdirSync(d, { withFileTypes: true }).flatMap((v) => {
    const p = join(d, v.name);
    return v.isDirectory() ? ricorsivi(p) : [p];
  });

const SUPERFICI = [
  "src/lib/accessori-ordini",
  "src/services/accessori-ordini-service.ts",
  "src/components/vinea/ordini-accessori",
  "src/app/ordini-accessori",
];
/** VPM-015B5D: le sole superfici che portano il Payment Element; il resto del dominio resta senza legami con il pagamento. */
const SUPERFICI_PAGAMENTO_B5D = /[\\/](pagamento\.ts|PagamentoAccessorio\.tsx)$/;
const IMPORT_B5D = 'from "./PagamentoAccessorio"';
const codice = () =>
  SUPERFICI.flatMap((voce) => {
    const abs = join(progetto, voce);
    const file = voce.endsWith(".ts") ? [abs] : ricorsivi(abs);
    return file
      .filter((f) => /\.(ts|tsx)$/.test(f) && !/\.(test|fixture)\.tsx?$/.test(f) && !SUPERFICI_PAGAMENTO_B5D.test(f))
      .map((f) => ({ file: f, codice: senzaCommenti(readFileSync(f, "utf8")).replace(IMPORT_B5D, "") }));
  });

const MIGRAZIONE = "supabase/migrations/20261102090000_vpm_015b5a_checkout_accessori.sql";
const migrazione = () => senzaCommentiSql(leggiRepo(MIGRAZIONE));

describe("B5A: nessun pagamento, nessun legame con il vino", () => {
  it("non importa pagamenti, Stripe, ordini o servizi del vino", () => {
    const vietati =
      /(phase7|proposal|payment|pagament|stripe|payouts|balance|orders?-service|order-service|listing-service|preventivo-service|cellar-service|logistics-service|vp-e-logistica)/i;
    for (const { file, codice: c } of codice()) {
      for (const i of c.match(/from\s+["'][^"']+["']/g) ?? []) {
        expect({ file, importo: i, vietato: vietati.test(i) }).toEqual({ file, importo: i, vietato: false });
      }
    }
  });

  it("nessun comando di pagamento, nessun vettore, nessun carrello", () => {
    for (const { file, codice: c } of codice()) {
      expect({ file, v: /(Paga ora|Paga\b\s*[<"'{]|Compra ora|carrello|addToCart|\bbuy\b)/i.test(c) }).toEqual({
        file,
        v: false,
      });
      expect({ file, v: /(\b(brt|sda|ups|dhl|poste|gls)\b|etichett|tracking|payments-checkout)/i.test(c) }).toEqual({
        file,
        v: false,
      });
    }
  });

  it("nessun importo, tariffa o commissione scritti nel codice: i numeri sono del database", () => {
    for (const { file, codice: c } of codice()) {
      expect({ file, v: /(prezzo_cents|commissione_cents|\b1000\s*bps|margine\s*[:=]\s*\d)/i.test(c) }).toEqual({
        file,
        v: false,
      });
    }
  });

  it("chiama solo le cinque porte del checkout, senza tabelle e senza argomenti economici", () => {
    const servizio = senzaCommenti(leggi("src/services/accessori-ordini-service.ts"));
    expect(servizio).not.toMatch(/\.from\(/);
    const rpc = [...servizio.matchAll(/"(accessori_(?:checkout|ordine|ordini|disponibilita)[a-z_]*)"/g)].map((m) => m[1]);
    expect([...new Set(rpc)].sort()).toEqual([
      "accessori_checkout_crea",
      "accessori_disponibilita",
      "accessori_ordine_annulla",
      "accessori_ordine_leggi",
      "accessori_ordini_elenca",
    ]);
    expect(servizio).not.toMatch(
      /p_(prezzo|importo|tariffa|servizio|provider|commissione|margine|totale|costo|quantita|venditore|seller|annuncio_id|buyer|acquirente)/,
    );
    // L'unica funzione che applica una vendita è privata: il client non la raggiunge.
    expect(servizio).not.toMatch(/segna_pagato|pagamento_simula/i);
  });

  it("nessun controllo del browser decide chi vende o quanto si paga", () => {
    for (const { file, codice: c } of codice()) {
      expect({ file, v: /(seller_id|buyer_id|venditore_id|acquirente_id)\s*[:=]/.test(c) }).toEqual({ file, v: false });
    }
  });

  it("la flag server è spenta di default e la scheda la rispetta", () => {
    const features = leggi("src/config/features.ts");
    expect(features).toMatch(/accessoriOrdiniAbilitatoServer[\s\S]*?ACCESSORI_ORDINI_ENABLED/);
    const scheda = leggi("src/app/accessori/annunci/[id]/page.tsx");
    expect(scheda).toMatch(/accessoriOrdiniAbilitatoServer\(\)\s*\?/);
    for (const p of ["src/app/ordini-accessori/page.tsx", "src/app/ordini-accessori/[id]/page.tsx"]) {
      const c = leggi(p);
      expect(c).toMatch(/accessoriOrdiniAbilitatoServer\(\)/);
      expect(c).toMatch(/notFound\(\)/);
      expect(c).toMatch(/noindex|index:\s*false/);
    }
    for (const f of [".env.example", "../docs/ENVIRONMENT.md"]) {
      expect(leggi(f)).toContain("ACCESSORI_ORDINI_ENABLED");
    }
    expect(leggi(".env.example")).toMatch(/^ACCESSORI_ORDINI_ENABLED=false$/m);
  });
});

describe("B5A: forma della migrazione", () => {
  it("esiste ed è additiva", () => {
    expect(existsSync(join(radiceRepo, MIGRAZIONE))).toBe(true);
    const m = migrazione();
    expect(m).not.toMatch(/drop\s+table/i);
    expect(m).not.toMatch(/alter\s+table\s+public\.(orders|payments|listings|proposals|marketplace_config)/i);
    expect(m).not.toMatch(/(insert\s+into|update|delete\s+from)\s+public\.(orders|payments|listings|proposals|marketplace_config)/i);
  });

  it("interruttore spento di default; accensione solo col ruolo di rilascio", () => {
    const m = migrazione();
    expect(m).toMatch(/checkout_attivo boolean not null default false/);
    expect(m).toMatch(/rilascio_non_autorizzato/);
    expect(m).toMatch(/accessori_rilascio_richiesto\(\)/);
  });

  it("nessuna esecuzione ad anon sulle porte dell'ordine e nessuna a service_role", () => {
    const m = migrazione();
    for (const f of ["accessori_checkout_crea(uuid, text)", "accessori_ordine_annulla(uuid)", "accessori_ordine_leggi(uuid)"]) {
      expect(m).toContain(`grant execute on function public.${f} to authenticated;`);
    }
    expect(m).toContain("grant execute on function public.accessori_disponibilita(uuid) to anon, authenticated;");
    expect(m).not.toMatch(/grant\s+execute[^;]*accessori_ordine_segna_pagato/i);
    expect(m).toMatch(/revoke all on function %s from public, anon, authenticated, service_role/);
  });

  it("ordini senza chiavi esterne verso il vino, importi congelati e immutabili", () => {
    const m = migrazione();
    expect(m).not.toMatch(/references\s+public\.(orders|listings|payments|proposals|bottle_units)/i);
    expect(m).toMatch(/accessori_ordini_totale/);
    expect(m).toMatch(/ordine_immutabile/);
    expect(m).toMatch(/create unique index accessori_ordini_una_prenotazione_aperta/);
    expect(m).toMatch(/create unique index accessori_ordini_chiave_unica/);
    expect(m).toMatch(/create unique index accessori_ordini_preventivo_unico/);
  });

  it("l'unica scrittura delle quantità passa dal pagamento simulato, dopo il lock dell'accessorio", () => {
    const m = migrazione();
    const corpo = m.slice(m.indexOf("create function private.accessori_ordine_segna_pagato"));
    const fine = corpo.indexOf("revoke execute on function private.accessori_ordine_segna_pagato");
    const f = corpo.slice(0, fine);
    expect(f.indexOf("from private.cantina_accessori")).toBeLessThan(f.indexOf("from private.annunci_accessori"));
    expect(f).toMatch(/for update/);
    // Le quantità scendono dopo che l'ordine è uscito da «in attesa».
    expect(f.indexOf("stato = 'pagato'")).toBeLessThan(f.indexOf("set quantita = quantita - o.quantita"));
  });

  it("il checkout non riceve importi: due soli argomenti", () => {
    const m = migrazione();
    expect(m).toMatch(/function public\.accessori_checkout_crea\(p_preventivo_id uuid, p_chiave text\)/);
  });
});

describe("B5D: il Payment Element non decide nulla", () => {
  const b5d = () =>
    ["src/lib/accessori-ordini/pagamento.ts", "src/components/vinea/ordini-accessori/PagamentoAccessorio.tsx"].map((f) =>
      senzaCommenti(leggi(f)),
    );

  it("usa il solo servizio B5B, senza chiavi segrete né chiamate dirette alla Edge Function", () => {
    for (const c of b5d()) {
      expect(/(sk_(live|test)|STRIPE_SECRET|payments-checkout|service_role|SERVICE_ROLE)/i.test(c)).toBe(false);
    }
    expect(b5d()[1]).toContain("apriPagamentoAccessori");
  });

  it("non scrive mai lo stato pagato e non legge il redirect come prova", () => {
    for (const c of b5d()) {
      expect(/(stato\s*[:=]\s*["']pagato["']|redirect_status|checkout\s*===\s*["']success["'])/.test(c)).toBe(false);
    }
  });

  it("non invia importi, venditori o quantità al pagamento", () => {
    const c = b5d()[1] ?? "";
    expect(/(amount|importo|prezzo|sellerId|venditoreId|quantita)\s*:/i.test(c.replace(/ordine\.id/g, ""))).toBe(false);
  });
});
