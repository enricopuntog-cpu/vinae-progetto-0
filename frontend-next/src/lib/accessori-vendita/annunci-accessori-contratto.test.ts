import { describe, expect, it } from "bun:test";
import { createHash } from "node:crypto";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

/**
 * VPM-015B2 e VPM-015B3 — contratto degli annunci Accessori, scritto come test.
 *
 * Un annuncio Accessori si può pubblicare (VPM-015B3) solo dietro l'interruttore
 * di pubblicazione, il consenso del titolare per categoria e i requisiti
 * verificati dal database; pubblicato NON è acquistabile. Nessun gesto
 * d'acquisto, nessun legame con ordini, pagamenti o checkout, nessun campo
 * economico deciso dal browser. Il contratto guarda il CODICE (non i commenti) e
 * le migrazioni, così che aggiungere una scorciatoia faccia fallire la build
 * invece di passare in una PR. Il contratto della migrazione B3 è in
 * `annunci-accessori-pubblicazione-contratto.test.ts`; qui la migrazione B2 è
 * storia congelata e si verifica soltanto che non sia stata toccata.
 */

const progetto = join(import.meta.dir, "../../..");
const radiceRepo = join(progetto, "..");
const leggi = (percorso: string) => readFileSync(join(progetto, percorso), "utf8");
const leggiRepo = (percorso: string) => readFileSync(join(radiceRepo, percorso), "utf8");
const senzaCommenti = (sorgente: string) =>
  sorgente.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");
const senzaCommentiSql = (sorgente: string) =>
  sorgente.replace(/--.*$/gm, "").replace(/comment on [^;]*;/gi, "");
const fileRicorsivi = (directory: string): string[] =>
  readdirSync(directory, { withFileTypes: true }).flatMap((voce) => {
    const percorso = join(directory, voce.name);
    return voce.isDirectory() ? fileRicorsivi(percorso) : [percorso];
  });

const SUPERFICI = [
  "src/lib/accessori-vendita",
  "src/services/annunci-accessori-service.ts",
  "src/components/vinea/accessori-vendita",
];

const codice = (): Array<{ file: string; codice: string }> =>
  SUPERFICI.flatMap((voce) => {
    const assoluto = join(progetto, voce);
    const file = voce.endsWith(".ts") ? [assoluto] : fileRicorsivi(assoluto);
    return file
      .filter((f) => /\.(ts|tsx)$/.test(f) && !/\.test\.tsx?$/.test(f))
      .map((f) => ({ file: f, codice: senzaCommenti(readFileSync(f, "utf8")) }));
  });

const MIGRAZIONE = "supabase/migrations/20261021150000_vpm_015b2_annunci_accessori.sql";
const migrazione = () => senzaCommentiSql(leggiRepo(MIGRAZIONE));

describe("Annunci Accessori: nessun percorso di transazione", () => {
  it("il codice non importa checkout, ordini, proposte, pagamenti, saldo o servizi del vino", () => {
    const vietati =
      /(checkout|phase7|proposal|payment|pagament|orders?-service|order-service|listing-service|partner-scorte|payouts|balance|stripe|preventivo-service|logistic|cellar-service)/i;
    for (const { file, codice: c } of codice()) {
      for (const i of c.match(/from\s+["'][^"']+["']/g) ?? []) {
        expect({ file, importo: i, vietato: vietati.test(i) }).toEqual({ file, importo: i, vietato: false });
      }
    }
  });

  it("nessuna superficie linka percorsi di acquisto o di vendita del vino", () => {
    const percorsiVietati = /["'`]\/(checkout|ordine|acquisti|vendite|vendi|annuncio)\b/;
    for (const { file, codice: c } of codice()) {
      expect({ file, trovato: percorsiVietati.test(c) }).toEqual({ file, trovato: false });
    }
  });

  it("nessun comando d'acquisto: né «Acquista», né carrello, né pagamento", () => {
    const comando = /(\bAcquista\b|\bCompra\b|Aggiungi al carrello|\bPaga ora\b|\bPaga\b\s*[<"'{]|Checkout|\bbuy\b|addToCart)/;
    for (const { file, codice: c } of codice()) {
      expect({ file, trovato: comando.exec(c)?.[0] ?? null }).toEqual({ file, trovato: null });
    }
  });

  it("non tocca le tabelle del vino né del mercato", () => {
    const tabelle = /(wines|bottle_units|cellar_slots|cellar_|listings|orders|payments|marketplace_config|payouts)/;
    for (const { file, codice: c } of codice()) {
      expect({ file, trovato: tabelle.exec(c)?.[0] ?? null }).toEqual({ file, trovato: null });
    }
  });

  it("nessuna variabile d'ambiente nuova: l'interruttore vive solo nel database", () => {
    for (const { file, codice: c } of codice()) {
      expect({ file, env: /process\.env/.test(c) }).toEqual({ file, env: false });
    }
    expect(leggi(".env.example")).not.toMatch(/ANNUNCI_ACCESSORI/i);
    expect(leggiRepo("docs/ENVIRONMENT.md")).not.toMatch(/ANNUNCI_ACCESSORI/i);
  });

  it("nessuno stato «attivo» né acquistabile fra gli stati dell'annuncio; nessuna revisione manuale", () => {
    const lib = leggi("src/lib/accessori-vendita/annunci-accessori.ts");
    const stati = /STATI_ANNUNCIO_ACCESSORIO = \[([^\]]*)\]/.exec(lib)?.[1] ?? "";
    expect(stati.replace(/\s/g, "")).toBe(
      '"bozza","pubblicato","modifiche_richieste","oscurato","ritirato",',
    );
    expect(stati).not.toMatch(/attivo|acquist|venduto|riservato|in_revisione/);
  });
});

describe("Annunci Accessori: servizio", () => {
  const servizio = senzaCommenti(leggi("src/services/annunci-accessori-service.ts"));

  it("chiama solo funzioni annunci_accessori_*: nessuna porta di acquisto, nessuna tabella", () => {
    const rpc = [...servizio.matchAll(/\.rpc\(\s*"([a-z_]+)"/g)].map((m) => m[1]);
    const dinamiche = [...servizio.matchAll(/(?:annuncio|senzaRisultato)\(\s*"([a-z_]+)"/g)].map((m) => m[1]);
    const tutte = [...new Set([...rpc, ...dinamiche])];
    for (const nome of tutte) expect(nome).toMatch(/^annunci_accessori_/);
    expect(tutte.sort()).toEqual([
      "annunci_accessori_admin_categoria_pubblicabile_imposta",
      "annunci_accessori_admin_categorie_pubblicazione",
      "annunci_accessori_admin_dettaglio",
      "annunci_accessori_admin_elenca",
      "annunci_accessori_admin_imposta",
      "annunci_accessori_admin_modera",
      "annunci_accessori_admin_pubblicazione_imposta",
      "annunci_accessori_admin_stato",
      "annunci_accessori_elenca",
      "annunci_accessori_preventivo",
      "annunci_accessori_pubblica",
      "annunci_accessori_pubblici_elenca",
      "annunci_accessori_pubblico_dettaglio",
      "annunci_accessori_salva",
      "annunci_accessori_stato",
      "annunci_accessori_transizione",
    ]);
    expect(servizio).not.toMatch(/\.from\(\s*["'`]/);
    // Storage solo per firmare le foto dello snapshot: mai upload, remove o lista del bucket.
    expect(servizio).not.toMatch(/\.(upload|remove|list|download|getPublicUrl)\(/);
    expect([...servizio.matchAll(/\.storage\b/g)]).toHaveLength(1);
    expect(servizio).toContain(".createSignedUrls(");
  });

  it("venditore, classe, margine, commissione e stato non sono mai parametri delle porte", () => {
    expect(servizio).not.toMatch(
      /p_(owner|seller|venditore|proprietario|classe|margine|commissione|totale|stato)\b|owner_id\s*:|seller_id\s*:/,
    );
  });
});

describe("Annunci Accessori: superfici", () => {
  it("la scheda della Cantina integra il comando senza toccare le bottiglie", () => {
    const cantina = leggi("src/components/vinea/cantina-accessori/CantinaAccessori.tsx");
    expect(cantina).toContain("<VenditaAccessoriProvider>");
    expect(cantina).toContain("<VenditaAccessorio accessorio={a} />");
    const pagina = leggi("src/app/cantina/page-client.tsx");
    expect(pagina).toContain("<CantinaAccessori />");
    expect(pagina).toContain("<BottiglieView");
    expect(pagina).not.toContain("annunci-accessori");
  });

  it("il comando non mostra nulla senza lo stato abilitato e archiviati esclusi", () => {
    const comando = leggi("src/components/vinea/accessori-vendita/VenditaAccessorio.tsx");
    expect(comando).toMatch(/!contesto\?\.stato\?\.abilitata \|\| accessorio\.archiviato\) return null/);
  });

  it("il dialogo dichiara che gli acquisti non sono disponibili e pubblica solo tramite il servizio", () => {
    const dialogo = senzaCommenti(leggi("src/components/vinea/accessori-vendita/AnnuncioAccessorioDialog.tsx"));
    expect(dialogo).toContain("Gli acquisti non sono ancora disponibili.");
    expect(dialogo).toContain('data-testid="avviso-acquisti-non-disponibili"');
    expect(dialogo).toContain("servizio.pubblica(");
    expect(dialogo).toContain("Pubblica annuncio");
    // nessuna revisione manuale nascosta
    expect(dialogo).not.toMatch(/in_revisione|Invia in revisione|Riporta in bozza/);
  });

  it("le pagine pubbliche passano dallo stesso gate degli Accessori e non linkano acquisti", () => {
    for (const pagina of ["src/app/accessori/annunci/page.tsx", "src/app/accessori/annunci/[id]/page.tsx"]) {
      const c = senzaCommenti(leggi(pagina));
      expect(c).toContain("risolviModalitaAccessori(client)");
      expect(c).toContain("notFound()");
      expect(c).not.toMatch(/process\.env/);
      expect(c).not.toMatch(/(checkout|phase7|proposal|payment|pagament|orders?-service|listing-service|balance|stripe)/i);
      expect(c).not.toMatch(/["'`]\/(checkout|ordine|acquisti|vendite|vendi|annuncio)\b/);
    }
  });

  it("la vetrina pubblica non ha comandi d'acquisto e l'unica azione è la segnalazione, che richiede l'accesso", () => {
    const vetrina = senzaCommenti(leggi("src/components/vinea/accessori-vendita/AnnunciPubblici.tsx"));
    expect(vetrina).toContain("Gli acquisti non sono ancora disponibili.");
    expect(vetrina).toContain('targetType="annuncio_accessorio"');
    expect(vetrina).toContain("Segnala annuncio");
    // senza sessione la segnalazione rimanda all'accesso: nessuna porta anonima
    expect(vetrina).toContain("autenticato ?");
    expect(vetrina).toContain("Accedi per segnalare");
    // le foto non si ritagliano: oggetti verticali interi
    expect(vetrina).toContain("object-contain");
    expect(vetrina).not.toContain("object-cover");
  });

  it("l'area admin ha la moderazione e la porta di segnalazione usa la RPC dedicata", () => {
    expect(leggi("src/components/vinea/accessori/AccessoriAdminClient.tsx")).toContain("<ModerazioneAnnunciAccessori />");
    const moderazione = senzaCommenti(leggi("src/components/vinea/accessori-vendita/ModerazioneAnnunciAccessori.tsx"));
    expect(moderazione).toContain("motivazioneValida(motivazione)");
    const segnala = leggi("src/services/phase9/supabase-moderation-service.ts");
    expect(segnala).toContain('"segnalazione_annuncio_accessorio_invia"');
    expect(leggi("src/data/moderation.ts")).toContain('| "annuncio_accessorio"');
  });

  it("l'area admin mostra i due interruttori e l'accensione chiede la conferma scritta", () => {
    expect(leggi("src/components/vinea/accessori/AccessoriAdminClient.tsx")).toContain("<AnnunciAccessoriAdmin />");
    const pannello = leggi("src/components/vinea/accessori-vendita/AnnunciAccessoriAdmin.tsx");
    expect(pannello).toContain("PAROLA_DI_RILASCIO");
    expect(pannello).toMatch(/conferma !== PAROLA_DI_RILASCIO/);
    expect(pannello).toContain("impostaPubblicazione(");
    expect(pannello).toContain("impostaCategoriaPubblicabile(");
    // una categoria si approva solo se il database la dichiara vendibile alla preparazione
    expect(pannello).toMatch(/c\.vendibile && stato\.puoRilasciare/);
  });

  it("il riepilogo non scrive mai uno zero per la spedizione: senza tariffa è «non disponibile»", () => {
    const riepilogo = senzaCommenti(leggi("src/components/vinea/accessori-vendita/RiepilogoEconomico.tsx"));
    expect(riepilogo).toContain("Preventivo non disponibile");
    expect(riepilogo).not.toMatch(/spedizione\w*Cents/);
    // il riepilogo mostra importi del database: nessun calcolo sugli importi
    expect(riepilogo).not.toMatch(/Math\.|Cents\s*[-+*/]\s*[\w(]/);
  });
});

describe("Annunci Accessori: migrazione B2 (storica, congelata)", () => {
  it("le migrazioni già distribuite non sono state toccate (hash dei contenuti)", () => {
    const hash = (percorso: string) => createHash("sha256").update(leggiRepo(percorso)).digest("hex");
    expect(hash("supabase/migrations/20261020120000_vpm_015a_accessori_fondazione.sql")).toBe(
      "27be50c9b44f5c8bf0852e0f1fda3eb19d99605060d2753940faa2f095753889",
    );
    expect(hash("supabase/migrations/20261020170000_vpm_015a_accessori_rilascio_e_media_privati.sql")).toBe(
      "918821b2d0bef4b12aaf9fd462f82157262ae9923ecea972fd7e533456271f7d",
    );
    expect(hash("supabase/migrations/20261021090000_vpm_015b1_cantina_accessori.sql")).toBe(
      "e74951a6d6299ec104287272a5dd27171ab67e8317c0e0a3e3f59d9b97e85bb5",
    );
    expect(hash(MIGRAZIONE)).toBe("8d861d4ee08f00c955cf5f9788cdfe026bf50ef6a17ef0d8b6085cec41847f40");
  });

  it("esiste ed è additiva: nessun drop di tabelle, nessuna scrittura sui dati di altri domini", () => {
    expect(existsSync(join(radiceRepo, MIGRAZIONE))).toBe(true);
    const sql = migrazione();
    expect(sql).not.toMatch(/drop\s+table/i);
    expect(sql).not.toMatch(/\bupdate\s+public\./i);
    expect(sql).not.toMatch(/\bdelete\s+from\s+public\./i);
    expect(sql).not.toMatch(/insert\s+into\s+public\./i);
    // Ritocchi ammessi a oggetti esistenti: il solo vincolo del registro e il
    // trigger sugli accessori della Cantina (che non cambia la tabella).
    const alter = [...sql.matchAll(/alter table\s+([a-z_.]+)/gi)]
      .map((m) => m[1])
      .filter((t) => !/^private\.(annunci_accessori|marketplace_margini_dominio)/.test(t));
    expect(alter).toEqual(["private.accessori_registro", "private.accessori_registro"]);
  });

  it("non cita vino, bottiglie, annunci del mercato, ordini, pagamenti: della configurazione legge solo i parametri", () => {
    const sql = migrazione();
    expect(sql).not.toMatch(
      /\b(public\.wines|bottle_units|cellar_slots|public\.listings|public\.orders|public\.payments|payouts|public\.proposals)\b/i,
    );
    // marketplace_config e solo letta
    expect(sql).not.toMatch(/(insert\s+into|update|delete\s+from)\s+public\.marketplace_config/i);
  });

  it("le tabelle nuove stanno in private, con RLS attiva e senza grant ai ruoli client", () => {
    const sql = migrazione();
    const tabelle = [...sql.matchAll(/create table\s+([a-z_.]+)/gi)].map((m) => m[1]);
    expect(tabelle).toEqual([
      "private.marketplace_margini_dominio",
      "private.annunci_accessori_impostazioni",
      "private.annunci_accessori_categorie",
      "private.annunci_accessori",
    ]);
    for (const t of tabelle) {
      expect(sql).toContain(`alter table ${t} enable row level security`);
      expect(sql).toContain(`revoke all on table ${t} from public, anon, authenticated`);
    }
    expect(sql).not.toMatch(/grant\s+(select|insert|update|delete|all)\s+on\s+(table\s+)?private\./i);
    expect(sql).not.toMatch(/create (or replace )?view/i);
    expect(sql).not.toMatch(/create policy/i);
  });

  it("(storico B2) nessuno stato acquistabile e pubblicazione vincolata a falso in quella migrazione; la B3 la sostituisce con l'interruttore e il rilascio", () => {
    const sql = migrazione();
    expect(sql).toMatch(/check \(stato in \('bozza', 'in_revisione', 'ritirato'\)\)/);
    expect(sql).toMatch(/constraint annunci_accessori_nessuna_pubblicazione check \(not pubblicazione_attiva\)/);
    expect(sql).toMatch(/preparazione_attiva boolean not null default false/);
    expect(sql).toMatch(/pubblicazione_attiva boolean not null default false/);
    expect(sql).toMatch(/hint = 'pubblicazione_chiusa'/);
  });

  it("l'interruttore è vincolato al rilascio; un solo annuncio aperto per accessorio; quantità sotto lock", () => {
    const sql = migrazione();
    expect(sql).toContain("annunci_accessori_impostazioni_guard");
    expect(sql).toContain("vinae.accessori_rilascio");
    expect(sql).toContain("accessori_rilascio_richiesto()");
    expect(sql).toMatch(/create unique index annunci_accessori_uno_aperto[\s\S]*?where stato in \('bozza', 'in_revisione'\)/);
    expect(sql).toMatch(/where id = new\.cantina_accessorio_id for update/);
    expect(sql).toMatch(/hint = 'quantita_non_disponibile'/);
    // nessuna colonna di quantità impegnata: è sempre derivata
    const tabella = /create table private\.annunci_accessori \(([\s\S]*?)\n\);/.exec(sql)?.[1] ?? "";
    expect(tabella.length).toBeGreaterThan(200);
    expect(tabella).not.toMatch(/impegnat|disponibil|prenotat/i);
  });

  it("i margini accessori sono versionati, 1000 e 1500 punti base, senza duplicare i parametri di pagamento", () => {
    const sql = migrazione();
    expect(sql).toMatch(/\('accessori_enologici', 'privato', 1000,/);
    expect(sql).toMatch(/\('accessori_enologici', 'partner', 1500,/);
    expect(sql).toMatch(/marketplace_margini_dominio_una_corrente[\s\S]*?\(dominio, classe_venditore\)\s+where valida_fino is null/);
    expect(sql).not.toMatch(/riferimento_stripe_\w+\s+integer/);
    expect(sql).toContain("private.marketplace_totale_cents(");
    expect(sql).toContain("private.pagamento_fee_accessori_cents(");
    expect(sql).toContain("private.marketplace_config_corrente(p_classe)");
    // il vino non ha margini qui: restano in marketplace_config
    expect(sql).toMatch(/check \(dominio <> 'vino'::public\.dominio_merceologico\)/);
  });

  it("le categorie sono fail-closed e il Partner non usa il percorso personale", () => {
    const sql = migrazione();
    expect(sql).toContain("annunci_accessori_categorie");
    expect(sql).toMatch(/coalesce\(\(/); // nessuna riga = non vendibile
    expect(sql).toContain("partner_percorso_non_consentito");
    expect(sql).toContain("venditore_vendite_bloccate");
    expect(sql).toContain("dichiarazione_mancante");
  });

  it("solo authenticated esegue le porte; mai anon né service_role", () => {
    const sql = migrazione();
    const grant = [...sql.matchAll(/grant execute on function (public\.[a-z_]+)\([^)]*\) to ([a-z, ]+);/gi)];
    expect(grant.length).toBe(8);
    for (const g of grant) expect(g[2].trim()).toBe("authenticated");
    expect(sql).not.toMatch(/grant execute on function private\./i);
  });

  it("ogni funzione security definer fissa il search_path vuoto", () => {
    const sql = migrazione();
    const definer = [...sql.matchAll(/security definer/gi)].length;
    const fissati = [...sql.matchAll(/security definer\s+set search_path = ''/gi)].length;
    expect(definer).toBeGreaterThan(15);
    expect(fissati).toBe(definer);
  });

  it("la griglia 12zj e la prova di concorrenza restano registrate nel gate CI", () => {
    const runner = leggiRepo("supabase/tests/12g_ci_run.sh");
    expect(runner).toContain("12zj_vpm_015b2_annunci_accessori.sql");
    expect(runner).toContain("12zj_vpm_015b2_concorrenza.sh");
    expect(existsSync(join(radiceRepo, "supabase/tests/12zj_vpm_015b2_annunci_accessori.sql"))).toBe(true);
    expect(existsSync(join(radiceRepo, "supabase/tests/12zj_vpm_015b2_concorrenza.sh"))).toBe(true);
  });
});
