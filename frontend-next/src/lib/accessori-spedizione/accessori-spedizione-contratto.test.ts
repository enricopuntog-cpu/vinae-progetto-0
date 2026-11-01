import { describe, expect, it } from "bun:test";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

/**
 * VPM-015B4 — contratto della logistica Accessori, scritto come test.
 *
 * Stima e preventivo congelato non sono un acquisto: nessun legame con ordini,
 * pagamenti o checkout, nessun corriere, nessuna tariffa nel codice, nessun
 * importo deciso dal browser. Il contratto guarda il CODICE (non i commenti) e
 * la migrazione, così che una scorciatoia faccia fallire la build.
 */

const progetto = join(import.meta.dir, "../../..");
const radiceRepo = join(progetto, "..");
const leggi = (p: string) => readFileSync(join(progetto, p), "utf8");
const leggiRepo = (p: string) => readFileSync(join(radiceRepo, p), "utf8");
const senzaCommenti = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");
const senzaCommentiSql = (s: string) => s.replace(/--.*$/gm, "").replace(/comment on[sS]*?';/gi, "");
const ricorsivi = (d: string): string[] =>
  readdirSync(d, { withFileTypes: true }).flatMap((v) => {
    const p = join(d, v.name);
    return v.isDirectory() ? ricorsivi(p) : [p];
  });

const SUPERFICI = [
  "src/lib/accessori-spedizione",
  "src/services/accessori-spedizione-service.ts",
  "src/components/vinea/accessori-spedizione",
];
const codice = () =>
  SUPERFICI.flatMap((voce) => {
    const abs = join(progetto, voce);
    const file = voce.endsWith(".ts") ? [abs] : ricorsivi(abs);
    return file
      .filter((f) => /\.(ts|tsx)$/.test(f) && !/\.test\.tsx?$/.test(f))
      .map((f) => ({ file: f, codice: senzaCommenti(readFileSync(f, "utf8")) }));
  });

const MIGRAZIONE = "supabase/migrations/20261101120000_vpm_015b4_logistica_accessori.sql";
const migrazione = () => senzaCommentiSql(leggiRepo(MIGRAZIONE));

describe("B4: nessun percorso di transazione né corriere nel codice", () => {
  it("non importa checkout, ordini, proposte, pagamenti, saldo, preventivi del vino o logistica del vino", () => {
    const vietati =
      /(checkout|phase7|proposal|payment|pagament|orders?-service|order-service|listing-service|payouts|balance|stripe|preventivo-service|cellar-service|logistics-service|vp-e-logistica)/i;
    for (const { file, codice: c } of codice()) {
      for (const i of c.match(/from\s+["'][^"']+["']/g) ?? []) {
        expect({ file, importo: i, vietato: vietati.test(i) }).toEqual({ file, importo: i, vietato: false });
      }
    }
  });

  it("nessun link a percorsi di acquisto, nessun comando d'acquisto, nessun vettore", () => {
    for (const { file, codice: c } of codice()) {
      expect({ file, v: /["'`]\/(checkout|ordine|acquisti|vendite|vendi|annuncio)\b/.test(c) }).toEqual({ file, v: false });
      expect({ file, v: /(Acquista|Compra|carrello|Paga ora|Conferma ordine)/i.test(c) }).toEqual({ file, v: false });
      expect({ file, v: /(\b(brt|sda|ups|dhl|poste|gls)\b|etichett|tracking|prenota(zione)?\s+ritiro)/i.test(c) }).toEqual({
        file,
        v: false,
      });
    }
  });

  it("nessuna tariffa, costo o classe di collo nel codice: i numeri sono del database", () => {
    for (const { file, codice: c } of codice()) {
      expect({ file, v: /(prezzo_cents|tariff[ae]\s*[:=]\s*\d|costo\w*\s*[:=]\s*\d{2,})/i.test(c) }).toEqual({ file, v: false });
    }
  });

  it("chiama solo le tre porte di logistica, senza tabelle e senza argomenti economici", () => {
    const servizio = senzaCommenti(leggi("src/services/accessori-spedizione-service.ts"));
    expect(servizio).not.toMatch(/\.from\(/);
    const rpc = [...servizio.matchAll(/"((?:annuncio_accessorio|accessori)_logistica_[a-z_]+)"/g)].map((m) => m[1]).sort();
    expect([...new Set(rpc)]).toEqual([
      "accessori_logistica_preventivo_congela",
      "accessori_logistica_preventivo_leggi",
      "annuncio_accessorio_logistica_preventivo",
    ]);
    expect(servizio).not.toMatch(/p_(prezzo|importo|tariffa|servizio|provider|commissione|margine|totale|costo)/);
  });

  it("la scheda mostra la stima solo dietro il gate server e dichiara che gli acquisti non ci sono", () => {
    const pagina = leggi("src/app/accessori/annunci/[id]/page.tsx");
    expect(pagina).toContain("accessoriLogisticaAbilitataServer()");
    const componente = leggi("src/components/vinea/accessori-spedizione/StimaSpedizioneAccessorio.tsx");
    expect(componente).toContain('data-testid="avviso-acquisti-logistica"');
    const features = leggi("src/config/features.ts");
    expect(features).toContain("valoreFlagEsattamenteTrue(process.env.ACCESSORI_LOGISTICA_ENABLED)");
    expect(leggi(".env.example")).toContain("ACCESSORI_LOGISTICA_ENABLED=false");
    expect(leggiRepo("docs/ENVIRONMENT.md")).toContain("ACCESSORI_LOGISTICA_ENABLED");
  });
});

describe("B4: forma della migrazione", () => {
  it("esiste, non tocca ordini, pagamenti, annunci del mercato, vino né le tariffe delle bottiglie", () => {
    expect(existsSync(join(radiceRepo, MIGRAZIONE))).toBe(true);
    const m = migrazione();
    expect(m).not.toMatch(/\b(insert|update|delete)\s+(into|from)?\s*public\.(orders|listings|payments|proposals|wines|bottle_units|marketplace_config)\b/i);
    expect(m).not.toMatch(/\b(insert\s+into|update|delete\s+from|alter\s+table)\s+private\.logistics_(commercial_rate_sources|shipping_rates|packaging_|pack_|shipment_plans|fulfillment|quote)/i);
    expect(m).not.toMatch(/references\s+(public\.(orders|listings|payments|proposals)|private\.(ordine_logistica|logistics_shipment_plans))/i);
  });

  it("nessuna tariffa, servizio o assicurazione seminati: tutto parte vuoto e spento", () => {
    const m = migrazione();
    expect(m).not.toMatch(/^insert\s+into\s+private\.(accessori_logistica_tariffe|accessori_logistica_assicurazioni|logistics_\w+)/im);
    expect(m).toMatch(/logistica_attiva boolean not null default false/);
    expect(m).toMatch(/insert into private\.accessori_logistica_impostazioni \(singleton\) values \(true\)/);
  });

  it("l'accensione richiede il rilascio anche per i writer privilegiati; una tariffa active richiede la fonte", () => {
    const m = migrazione();
    expect(m).toMatch(/new\.logistica_attiva and not old\.logistica_attiva/);
    expect(m).toMatch(/rilascio_non_autorizzato/);
    expect(m).toMatch(/private\.accessori_rilascio_richiesto\(\)/);
    expect(m).toMatch(/check \(stato <> 'active' or fonte is not null\)/);
  });

  it("il servizio è quello esistente: nessuna tabella di servizi o reti parallela", () => {
    const m = migrazione();
    expect(m).toMatch(/private\.logistics_service_definitions/);
    expect(m).toMatch(/private\.logistica_servizio_reti_ok/);
    expect(m).not.toMatch(/create table private\.\w*(servizi|reti|pudo|providers?)\w*/i);
  });

  it("riusa la formula economica unica e non la ricalcola", () => {
    const m = migrazione();
    expect(m).toMatch(/private\.preventivo_dominio\(/);
    expect(m).not.toMatch(/marketplace_totale_cents|pagamento_fee_accessori_cents/);
  });

  it("tabelle in private con RLS e nessun grant; funzioni senza service_role e con search_path vuoto", () => {
    const m = migrazione();
    const tabelle = [...m.matchAll(/create table (private\.[a-z_]+)/g)].map((x) => x[1]);
    expect(tabelle.length).toBe(5);
    for (const t of tabelle) {
      expect(m).toContain(`alter table ${t} enable row level security`);
      expect(m).toContain(`revoke all on table ${t} from public, anon, authenticated`);
    }
    for (const f of m.match(/create function [^;]*?as \$\$/g) ?? []) {
      expect(f).toMatch(/set search_path = ''/);
    }
    expect(m).toMatch(/revoke all on function %s from public, anon, authenticated, service_role/);
  });

  it("solo la stima è per anon; il resto solo per authenticated", () => {
    const m = migrazione();
    const grant = [...m.matchAll(/grant execute on function (public\.[a-z_]+)\([^)]*\)\s+to ([a-z, ]+);/g)].map((x) => [x[1], x[2]]);
    const conAnon = grant.filter(([, a]) => /anon/.test(a)).map(([f]) => f);
    expect(conAnon).toEqual(["public.annuncio_accessorio_logistica_preventivo"]);
    for (const [, a] of grant.filter(([f]) => f !== "public.annuncio_accessorio_logistica_preventivo")) {
      expect(a.trim()).toBe("authenticated");
    }
  });
});

describe("B4: prove nel gate CI", () => {
  it("la griglia 12zl è registrata nel gate e le migrazioni precedenti non sono state toccate", () => {
    expect(existsSync(join(radiceRepo, "supabase/tests/12zl_vpm_015b4_logistica_accessori.sql"))).toBe(true);
    expect(leggiRepo("supabase/tests/12g_ci_run.sh")).toContain("12zl_vpm_015b4_logistica_accessori.sql");
  });
});
