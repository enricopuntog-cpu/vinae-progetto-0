import { describe, expect, it } from "bun:test";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

/**
 * VPM-015B1 — contratto della Cantina Accessori personale, scritto come test.
 *
 * Gli accessori posseduti dagli utenti NON sono in vendita: niente prezzo,
 * annuncio, ordine, pagamento; niente righe in `wines`, `bottle_units` o
 * `cellar_slots`; foto private e firmate; proprietario sempre dal contesto
 * autenticato. Il contratto guarda il CODICE (non i commenti) e la migrazione,
 * cosi che aggiungere una scorciatoia faccia fallire la build invece di
 * passare in una PR.
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
  "src/lib/cantina-accessori",
  "src/services/cantina-accessori-service.ts",
  "src/components/vinea/cantina-accessori",
];

const codice = (): Array<{ file: string; codice: string }> =>
  SUPERFICI.flatMap((voce) => {
    const assoluto = join(progetto, voce);
    const file = voce.endsWith(".ts") ? [assoluto] : fileRicorsivi(assoluto);
    return file
      .filter((f) => /\.(ts|tsx)$/.test(f) && !/\.test\.tsx?$/.test(f))
      .map((f) => ({ file: f, codice: senzaCommenti(readFileSync(f, "utf8")) }));
  });

const MIGRAZIONE = "supabase/migrations/20261021090000_vpm_015b1_cantina_accessori.sql";
const migrazione = () => senzaCommentiSql(leggiRepo(MIGRAZIONE));

describe("Cantina Accessori: nessun percorso di transazione", () => {
  it("il codice non importa checkout, ordini, proposte, pagamenti, annunci o logistica", () => {
    const vietati =
      /(checkout|phase7|proposal|payment|pagament|orders?-service|order-service|listing-service|partner-scorte|payouts|balance|stripe|preventivo|logistic|cellar-service)/i;
    for (const { file, codice: c } of codice()) {
      for (const i of c.match(/from\s+["'][^"']+["']/g) ?? []) {
        expect({ file, importo: i, vietato: vietati.test(i) }).toEqual({ file, importo: i, vietato: false });
      }
    }
  });

  it("nessuna superficie linka percorsi di acquisto o di vendita", () => {
    const percorsiVietati = /["'`]\/(checkout|ordine|acquisti|vendite|vendi|annuncio)\b/;
    for (const { file, codice: c } of codice()) {
      expect({ file, trovato: percorsiVietati.test(c) }).toEqual({ file, trovato: false });
    }
  });

  it("nessun campo o etichetta di prezzo, valuta, carrello, acquisto o commissione", () => {
    const economico =
      /(prezzo|price|valuta\b|currency|cents|carrello|\bcart\b|\bacquista\b|\bcompra\b|checkout|commission)/i;
    for (const { file, codice: c } of codice()) {
      expect({ file, trovato: economico.exec(c)?.[0] ?? null }).toEqual({ file, trovato: null });
    }
  });

  it("non tocca le tabelle del vino né del mercato", () => {
    const tabelle = /(wines|bottle_units|cellar_slots|cellar_|listings|orders|payments|marketplace_config)/;
    for (const { file, codice: c } of codice()) {
      expect({ file, trovato: tabelle.exec(c)?.[0] ?? null }).toEqual({ file, trovato: null });
    }
  });

  it("nessuna variabile d'ambiente nuova: gli interruttori vivono solo nel database", () => {
    for (const { file, codice: c } of codice()) {
      expect({ file, env: /process\.env/.test(c) }).toEqual({ file, env: false });
    }
    expect(leggi(".env.example")).not.toMatch(/CANTINA_ACCESSORI/i);
    expect(leggiRepo("docs/ENVIRONMENT.md")).not.toMatch(/CANTINA_ACCESSORI/i);
  });
});

describe("Cantina Accessori: servizio", () => {
  const servizio = senzaCommenti(leggi("src/services/cantina-accessori-service.ts"));

  it("chiama solo funzioni cantina_accessori_* e il bucket privato, mai le tabelle", () => {
    const rpc = [...servizio.matchAll(/\.rpc\(\s*"([a-z_]+)"/g)].map((m) => m[1]);
    const dinamiche = [...servizio.matchAll(/accessorio\(\s*"([a-z_]+)"/g)].map((m) => m[1]);
    for (const nome of [...rpc, ...dinamiche]) expect(nome).toMatch(/^cantina_accessori_/);
    expect(rpc.length + dinamiche.length).toBeGreaterThanOrEqual(10);
    expect(servizio).not.toMatch(/\.from\(\s*["'`]/);
  });

  it("il proprietario non è mai un parametro delle porte: solo la porta pubblica riceve un profilo", () => {
    expect(servizio).not.toMatch(/p_owner|owner_id\s*:|p_proprietario/);
    expect([...servizio.matchAll(/p_user_id/g)]).toHaveLength(1);
  });

  it("le foto sono sempre firmate: nessun URL pubblico dello Storage", () => {
    for (const { file, codice: c } of codice()) {
      expect({ file, pubblico: /getPublicUrl|object\/public/.test(c) }).toEqual({ file, pubblico: false });
    }
    expect(servizio).toContain("createSignedUrls");
    expect(servizio).toContain("upsert: false");
  });
});

describe("Cantina Accessori: superfici", () => {
  it("il componente pubblico non ha stato né azioni e non porta note, proprietario o legami", () => {
    const pubblico = senzaCommenti(leggi("src/components/vinea/cantina-accessori/AccessoriCantinaPubblici.tsx"));
    expect(pubblico).not.toMatch(/"use client"/);
    expect(pubblico).not.toMatch(/<button|<form|onClick|useState|useEffect/);
    expect(pubblico).not.toMatch(/\.note\b|catalogo|owner|proprietario|visibilita\b/);
  });

  it("il tipo pubblico ha l'elenco chiuso di campi", () => {
    const lib = leggi("src/lib/cantina-accessori/cantina-accessori.ts");
    const blocco = /export type AccessorioPubblico = \{([\s\S]*?)\n\};/.exec(lib)?.[1] ?? "";
    const campi = [...blocco.matchAll(/^\s{2}([a-zA-Z]+)\??:/gm)].map((m) => m[1]).sort();
    expect(campi).toEqual([
      "categoriaNome", "categoriaSlug", "condizione", "descrizione", "genitoreNome", "id",
      "immagini", "marchio", "nome", "quantita",
    ]);
  });

  it("la Cantina personale integra la sezione Accessori senza toccare le bottiglie", () => {
    const cantina = leggi("src/app/cantina/page-client.tsx");
    expect(cantina).toContain("<CantinaAccessori />");
    expect(cantina).toContain("<BottiglieView");
    expect(cantina).toContain("<ContabilitaCantina");
    // La sezione è un componente a parte: la pagina non importa il servizio.
    expect(cantina).not.toContain("cantina-accessori-service");
  });

  it("profilo e Cantina pubblica leggono gli esposti dalla funzione fail-closed e non per la vetrina Partner", () => {
    const profilo = leggi("src/app/profilo/[id]/page.tsx");
    expect(profilo).toContain("leggiAccessoriPubblici");
    expect(profilo).toContain("<AccessoriCantinaPubblici");
    expect(profilo).toMatch(/vetrina \? Promise\.resolve\(\{ accessori: \[\], url: \{\} \}\)/);
    const cantina = leggi("src/app/profilo/[id]/cantina/page.tsx");
    expect(cantina).toContain("leggiAccessoriPubblici");
    expect(cantina).toContain("<AccessoriCantinaPubblici");
    expect(cantina).toContain("<CollezionePubblica");
  });

  it("l'area admin mostra i due interruttori e l'accensione chiede la conferma scritta", () => {
    const admin = leggi("src/components/vinea/accessori/AccessoriAdminClient.tsx");
    expect(admin).toContain("<CantinaAccessoriAdmin />");
    const pannello = leggi("src/components/vinea/cantina-accessori/CantinaAccessoriAdmin.tsx");
    expect(pannello).toContain("PAROLA_DI_RILASCIO");
    expect(pannello).toMatch(/conferma !== PAROLA_DI_RILASCIO/);
  });
});

describe("Cantina Accessori: contratto della migrazione", () => {
  it("esiste ed è additiva: nessun drop di tabelle, nessun update di dati di altri domini", () => {
    expect(existsSync(join(radiceRepo, MIGRAZIONE))).toBe(true);
    const sql = migrazione();
    expect(sql).not.toMatch(/drop\s+table/i);
    // Le sole scritture sono quelle sulle due tabelle nuove (le porte del proprietario e degli interruttori).
    expect(sql).not.toMatch(/\bupdate\s+(?!private\.cantina_accessori)(public|private)\./i);
    expect(sql).not.toMatch(/\bdelete\s+from\s+(?!private\.cantina_accessori)/i);
    // Unico ritocco a un oggetto esistente: il vincolo del registro.
    const alter = [...sql.matchAll(/alter table\s+([a-z_.]+)/gi)]
      .map((m) => m[1])
      .filter((t) => !t.startsWith("private.cantina_accessori"));
    expect(alter).toEqual(["private.accessori_registro", "private.accessori_registro"]);
  });

  it("non cita vino, bottiglie, annunci, ordini, pagamenti o configurazione commerciale", () => {
    expect(migrazione()).not.toMatch(
      /\b(wines|bottle_units|cellar_slots|listings|orders|payments|payouts|proposals|marketplace_config)\b/i,
    );
  });

  it("nessuna colonna economica né numero di serie", () => {
    const sql = migrazione();
    expect(sql).not.toMatch(/\b(prezzo|price|valuta|currency|iva|vat|commissione|serial|matricola)\w*\s+(text|integer|numeric|bigint)/i);
  });

  it("le tabelle stanno in private, con RLS attiva e senza grant ai ruoli client", () => {
    const sql = migrazione();
    const tabelle = [...sql.matchAll(/create table\s+([a-z_.]+)/gi)].map((m) => m[1]);
    expect(tabelle).toEqual(["private.cantina_accessori", "private.cantina_accessori_impostazioni"]);
    for (const t of tabelle) {
      expect(sql).toContain(`alter table ${t} enable row level security`);
      expect(sql).toContain(`revoke all on table ${t} from public, anon, authenticated`);
    }
    expect(sql).not.toMatch(/grant\s+(select|insert|update|delete|all)\s+on\s+(table\s+)?private\./i);
    expect(sql).not.toMatch(/create (or replace )?view\s+public\./i);
    expect(sql).toMatch(/revoke all on private\.cantina_accessori_pubblica from public, anon, authenticated/);
  });

  it("i due interruttori nascono spenti e l'accensione è vincolata al rilascio", () => {
    const sql = migrazione();
    expect(sql).toMatch(/funzione_attiva boolean not null default false/);
    expect(sql).toMatch(/visibilita_pubblica boolean not null default false/);
    expect(sql).toContain("cantina_accessori_impostazioni_guard");
    expect(sql).toContain("vinae.accessori_rilascio");
    expect(sql).toContain("accessori_rilascio_richiesto()");
  });

  it("un accessorio nasce privato e si espone solo dalla porta (marker nello stesso trigger)", () => {
    const sql = migrazione();
    expect(sql).toMatch(/visibilita text not null default 'privata'/);
    expect(sql).toContain("vinae.cantina_accessori_espone");
    expect(sql).toContain("esposizione_non_autorizzata");
  });

  it("la categoria è una FK sulla tassonomia esistente e nessuna porta crea categorie", () => {
    const sql = migrazione();
    expect(sql).toMatch(/categoria_id uuid not null references private\.accessori_categorie \(id\) on delete restrict/);
    expect(sql).not.toMatch(/insert into private\.accessori_categorie/i);
    expect(sql).not.toMatch(/update private\.accessori_categorie/i);
    expect(sql).toContain("sottocategoria_obbligatoria");
  });

  it("il bucket è privato e solo la lettura delle foto esposte è concessa ad anon", () => {
    const sql = migrazione();
    expect(sql).toMatch(/values \('cantina-accessori-foto', 'cantina-accessori-foto', false,/);
    const policy = [...sql.matchAll(/create policy "([^"]+)"\s+on storage\.objects\s+for (\w+)\s+to ([a-z, ]+)/gi)];
    const perAnon = policy.filter((p) => /\banon\b/.test(p[3]));
    expect(perAnon.map((p) => `${p[1]}:${p[2].toLowerCase()}`)).toEqual([
      "cantina_accessori_media_select_esposte:select",
    ]);
    expect(policy.some((p) => p[2].toLowerCase() === "update")).toBe(false);
    expect(sql).not.toMatch(/public\s*=\s*true/i);
  });

  it("solo la porta pubblica è concessa ad anon; le altre sono per authenticated", () => {
    const sql = migrazione();
    const anon = [...sql.matchAll(/grant execute on function (public\.[a-z_]+)\([^)]*\) to ([a-z, ]+);/gi)]
      .filter((m) => /\banon\b/.test(m[2]))
      .map((m) => m[1]);
    expect(anon).toEqual(["public.cantina_accessori_pubblica_profilo"]);
    expect(sql).not.toMatch(/grant execute on function private\.[a-z_]+\([^)]*\) to [^;]*\bservice_role/i);
  });

  it("ogni funzione security definer fissa il search_path vuoto", () => {
    const sql = migrazione();
    const definer = [...sql.matchAll(/security definer/gi)].length;
    const fissati = [...sql.matchAll(/security definer\s+set search_path = ''/gi)].length;
    expect(definer).toBeGreaterThan(15);
    expect(fissati).toBe(definer);
  });

  it("la proiezione pubblica è una vista chiusa con filtro esplicito e senza colonne private", () => {
    const sql = migrazione();
    const vista = /create view private\.cantina_accessori_pubblica[\s\S]*?;\n/i.exec(sql)?.[0] ?? "";
    expect(vista).toContain("security_invoker = off");
    expect(vista).toContain("security_barrier = true");
    expect(vista).toContain("a.visibilita = 'cantina_pubblica'");
    expect(vista).toContain("a.archiviato_at is null");
    expect(vista).toContain("profili_pubblici");
    expect(vista).not.toMatch(/note_private|catalogo_id|archiviato_at\s+as|\bselect\s+a\.\*|\*\s+from/i);
  });

  it("la griglia 12zi è registrata nel gate CI e il suo conteggio resta nel piano", () => {
    expect(leggiRepo("supabase/tests/12g_ci_run.sh")).toContain("12zi_vpm_015b1_cantina_accessori.sql");
    expect(existsSync(join(radiceRepo, "supabase/tests/12zi_vpm_015b1_cantina_accessori.sql"))).toBe(true);
  });
});
