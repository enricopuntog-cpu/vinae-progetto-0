import { describe, expect, it } from "bun:test";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

/**
 * VPM-015A — contratto di fondazione degli Accessori, scritto come test.
 *
 * Questa sezione e un catalogo Beta: nessuna vendita, nessun pagamento, nessun
 * prezzo, nessuna commissione. Il contratto guarda il CODICE (non i commenti)
 * e la migrazione, cosi che aggiungere un percorso di transazione, o una porta
 * lasciata aperta, faccia fallire la build invece di passare in una PR.
 */

const progetto = join(import.meta.dir, "../../..");
const radiceRepo = join(progetto, "..");
const leggi = (percorso: string) => readFileSync(join(progetto, percorso), "utf8");
const leggiRepo = (percorso: string) => readFileSync(join(radiceRepo, percorso), "utf8");
const senzaCommenti = (sorgente: string) =>
  sorgente.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");
// I `comment on ...` sono documentazione, come i commenti: anche loro citano
// ciò che la tabella NON è (annunci, ordini...), e non devono far fallire la prova.
const senzaCommentiSql = (sorgente: string) =>
  sorgente.replace(/--.*$/gm, "").replace(/comment on [^;]*;/gi, "");
const fileRicorsivi = (directory: string): string[] =>
  readdirSync(directory, { withFileTypes: true }).flatMap((voce) => {
    const percorso = join(directory, voce.name);
    return voce.isDirectory() ? fileRicorsivi(percorso) : [percorso];
  });

const SUPERFICI_ACCESSORI = [
  "src/lib/accessori",
  "src/services/accessori-service.ts",
  "src/components/vinea/accessori",
  "src/app/accessori",
  "src/app/admin/accessori",
];

const codiceAccessori = (): Array<{ file: string; codice: string }> =>
  SUPERFICI_ACCESSORI.flatMap((voce) => {
    const assoluto = join(progetto, voce);
    const file = voce.endsWith(".ts") ? [assoluto] : fileRicorsivi(assoluto);
    return file
      .filter((f) => /\.(ts|tsx)$/.test(f) && !/\.test\.tsx?$/.test(f))
      .map((f) => ({ file: f, codice: senzaCommenti(readFileSync(f, "utf8")) }));
  });

const MIGRAZIONE = "supabase/migrations/20261020120000_vpm_015a_accessori_fondazione.sql";

describe("Accessori: nessun percorso di transazione", () => {
  it("il codice degli Accessori non importa checkout, ordini, proposte, pagamenti o annunci", () => {
    const vietati =
      /(checkout|phase7|phase7c|proposal|payment|pagament|orders?-service|order-service|listing-service|partner-scorte|payouts|balance|stripe|preventivo|logistic)/i;
    for (const { file, codice } of codiceAccessori()) {
      const importi = codice.match(/from\s+["'][^"']+["']/g) ?? [];
      for (const i of importi) {
        expect({ file, importo: i, vietato: vietati.test(i) }).toEqual({ file, importo: i, vietato: false });
      }
    }
  });

  it("nessuna superficie degli Accessori linka percorsi di acquisto", () => {
    const percorsiVietati = /["'`]\/(checkout|ordine|acquisti|vendite|vendi|annuncio)\b/;
    for (const { file, codice } of codiceAccessori()) {
      expect({ file, trovato: percorsiVietati.test(codice) }).toEqual({ file, trovato: false });
    }
  });

  it("nessun campo o etichetta di prezzo, valuta o carrello nel codice degli Accessori", () => {
    const economico =
      /(prezzo|price|valuta\b|currency|cents|carrello|\bcart\b|\bacquista\b|\bcompra\b|checkout|commission)/i;
    for (const { file, codice } of codiceAccessori()) {
      expect({ file, trovato: economico.exec(codice)?.[0] ?? null }).toEqual({ file, trovato: null });
    }
  });

  it("il servizio chiama solo funzioni accessori_* e il bucket accessori-media", () => {
    const servizio = senzaCommenti(leggi("src/services/accessori-service.ts"));
    const rpc = [...servizio.matchAll(/rpc\(\s*(?:"([^"]+)"|(\w+))/g)].map((m) => m[1] ?? m[2]);
    expect(rpc.length).toBeGreaterThan(0);
    for (const nome of rpc) {
      // L'helper `scheda` riceve il nome come parametro: i valori reali sono
      // controllati qui sotto, nelle chiamate che lo invocano.
      expect(nome === "rpc" || nome.startsWith("accessori_")).toBe(true);
    }
    const invocate = [...servizio.matchAll(/scheda\(\s*"[^"]+",\s*"([^"]+)"/g)].map((m) => m[1]);
    expect(invocate.length).toBeGreaterThan(0);
    for (const nome of invocate) expect(nome.startsWith("accessori_")).toBe(true);
    expect(servizio).not.toMatch(/\.from\(\s*["'](?!accessori-media)/);
    expect(servizio).not.toMatch(/service_role|SERVICE_ROLE/);
  });

  it("il servizio non espone una scrittura della visibilita pubblica", () => {
    const servizio = senzaCommenti(leggi("src/services/accessori-service.ts"));
    expect(servizio).not.toContain("accessori_admin_visibilita_imposta");
    expect(servizio).toContain("accessori_admin_stato");
  });
});

describe("Accessori: gate e feature flag spenti di default", () => {
  it("ogni pagina pubblica risolve la modalita prima di leggere e risponde 404 senza", () => {
    for (const pagina of [
      "src/app/accessori/page.tsx",
      "src/app/accessori/categoria/[slug]/page.tsx",
      "src/app/accessori/[slug]/page.tsx",
    ]) {
      const codice = senzaCommenti(leggi(pagina));
      const gate = codice.indexOf("risolviModalitaAccessori(");
      const lettura = codice.indexOf("creaAccessoriLetturaService(");
      expect(gate).toBeGreaterThan(-1);
      expect(lettura).toBeGreaterThan(gate);
      expect(codice).toMatch(/if \(!modalita\) notFound\(\)/);
      expect(codice).toContain("robots: { index: false, follow: false }");
    }
  });

  it("la pagina admin usa il ruolo reale da user_roles e non dipende dalle flag", () => {
    const codice = senzaCommenti(leggi("src/app/admin/accessori/page.tsx"));
    expect(codice).toContain('from("user_roles")');
    expect(codice).toContain("eAdminReale(ruoli)");
    expect(codice).toContain("if (!eAdminReale(ruoli)) notFound()");
    expect(codice).toContain("redirect(PERCORSO_ACCESSO)");
    expect(codice).not.toMatch(/ACCESSORI_ENABLED|useVinea|DEMO_UI/);
  });

  it("il gate pubblico richiede ACCESSORI_ENABLED e la variabile pubblica, entrambe esattamente true", () => {
    const gate = senzaCommenti(leggi("src/lib/accessori/gate.ts"));
    expect(gate).toMatch(/process\.env\.ACCESSORI_ENABLED[\s\S]*process\.env\.NEXT_PUBLIC_ACCESSORI_ENABLED/);
    expect(gate).toContain("valoreFlagEsattamenteTrue");
    expect(gate).toContain("eAdminReale(ruoli)");
    expect(senzaCommenti(leggi("src/config/features.ts"))).toMatch(
      /ACCESSORI_UI_ABILITATA = valoreFlagEsattamenteTrue\(\s*process\.env\.NEXT_PUBLIC_ACCESSORI_ENABLED,?\s*\)/,
    );
  });

  it("la voce di navigazione e filtrata dalla flag pubblica, solo sul desktop", () => {
    const layout = leggi("src/components/vinea/Layout.tsx");
    expect(layout).toContain('ACCESSORI_UI_ABILITATA || voce.to !== "/accessori"');
    expect(leggi("src/lib/shell/navigazione-mobile.ts")).not.toContain("/accessori");
  });

  it(".env.example e docs/ENVIRONMENT.md documentano le due flag, spente", () => {
    const esempio = leggi(".env.example");
    expect(esempio).toMatch(/^NEXT_PUBLIC_ACCESSORI_ENABLED=false$/m);
    expect(esempio).toMatch(/^ACCESSORI_ENABLED=false$/m);
    const ambiente = leggiRepo("docs/ENVIRONMENT.md");
    expect(ambiente).toContain("NEXT_PUBLIC_ACCESSORI_ENABLED");
    expect(ambiente).toContain("ACCESSORI_ENABLED");
  });

  it("netlify.toml non accende le flag", () => {
    const netlify = leggiRepo("netlify.toml");
    expect(netlify).not.toMatch(/ACCESSORI_ENABLED\s*=\s*["']?true/);
  });
});

describe("Accessori: contratto della migrazione", () => {
  const sql = () => senzaCommentiSql(leggiRepo(MIGRAZIONE));

  it("esiste ed e additiva: nessuna modifica a tabelle o oggetti di altri domini", () => {
    expect(existsSync(join(radiceRepo, MIGRAZIONE))).toBe(true);
    const testo = sql();
    expect(testo).not.toMatch(/alter\s+table\s+(?!private\.accessori)/i);
    expect(testo).not.toMatch(/drop\s+(table|function|policy|view|trigger)/i);
    expect(testo).not.toMatch(/create\s+or\s+replace/i);
    expect(testo).not.toMatch(/disable\s+row\s+level\s+security/i);
  });

  it("non cita annunci, ordini, pagamenti, vini, bottiglie o configurazione commerciale", () => {
    expect(sql()).not.toMatch(
      /\b(public\.)?(listings|orders|payments|payouts|proposals|bottle_units|wines|marketplace_config|balance_\w+)\b/i,
    );
  });

  it("nessuna tabella ne colonna economica", () => {
    expect(sql()).not.toMatch(
      /\b(prezzo\w*|price\w*|valuta|currency|\w*_cents|importo|amount|commissione|iva|vat|peso|weight|dimension\w*|fornitor\w*|supplier\w*)\b/i,
    );
  });

  it("le tabelle stanno in private, con RLS attiva e senza grant ai ruoli client", () => {
    const testo = sql();
    const tabelle = [...testo.matchAll(/create table (private\.\w+)/gi)].map((m) => m[1]);
    expect(tabelle.sort()).toEqual([
      "private.accessori",
      "private.accessori_categorie",
      "private.accessori_impostazioni",
      "private.accessori_registro",
    ]);
    for (const t of tabelle) {
      expect(testo).toContain(`alter table ${t} enable row level security`);
      expect(testo).toContain(`revoke all on table ${t} from public, anon, authenticated`);
    }
    expect(testo).not.toMatch(/grant\s+(select|insert|update|delete|all)[^;]*\bon\s+(table\s+)?(public\.)?\w*accessori/i);
    expect(testo).not.toMatch(/create\s+(or replace\s+)?view/i);
  });

  it("l'interruttore pubblico nasce spento e nel database", () => {
    const testo = sql();
    expect(testo).toMatch(/visibilita_pubblica boolean not null default false/);
    expect(testo).toMatch(/insert into private\.accessori_impostazioni \(singleton, visibilita_pubblica\) values \(true, false\)/);
  });

  it("solo le tre letture pubbliche sono concesse ad anon; le porte admin solo ad authenticated", () => {
    const testo = sql();
    const anon = [...testo.matchAll(/grant execute on function (public\.\w+)\([^)]*\) to anon, authenticated/g)].map((m) => m[1]);
    expect(anon.sort()).toEqual([
      "public.accessori_categorie_elenca",
      "public.accessori_dettaglio",
      "public.accessori_elenca",
    ]);
    const admin = [...testo.matchAll(/grant execute on function (public\.accessori_admin_\w+)\([^)]*\) to authenticated;/g)].map((m) => m[1]);
    expect(admin.length).toBe(9);
    // Ogni funzione public parte revocata da tutti i ruoli client e service_role.
    const create = [...testo.matchAll(/create function (public\.\w+)\(/g)].map((m) => m[1]);
    for (const f of create) {
      expect(testo).toMatch(new RegExp(`revoke all on function ${f.replace(".", "\\.")}\\([^)]*\\) from public, anon, authenticated, service_role`));
    }
  });

  it("ogni funzione security definer fissa il search_path vuoto", () => {
    const testo = sql();
    const blocchi = testo.split(/create function /).slice(1);
    for (const blocco of blocchi) {
      const intestazione = blocco.slice(0, blocco.indexOf("$$"));
      if (/security definer/i.test(intestazione)) {
        expect(intestazione).toMatch(/set search_path = ''/);
      }
    }
  });

  it("le porte admin delegano al controllo del ruolo reale", () => {
    const testo = sql();
    expect(testo).toContain("select private.partner_admin_richiesto()");
    const admin = testo.split(/create function public\.accessori_admin_/).slice(1);
    expect(admin.length).toBe(9);
    for (const blocco of admin) expect(blocco).toContain("private.accessori_admin_richiesto()");
  });

  it("la griglia 12zh e registrata nel gate CI", () => {
    expect(existsSync(join(radiceRepo, "supabase/tests/12zh_vpm_015a_accessori.sql"))).toBe(true);
    expect(leggiRepo("supabase/tests/12g_ci_run.sh")).toContain("12zh_vpm_015a_accessori.sql");
  });
});
