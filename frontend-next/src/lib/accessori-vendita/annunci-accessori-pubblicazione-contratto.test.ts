import { describe, expect, it } from "bun:test";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

/**
 * VPM-015B3 — contratto della pubblicazione automatica e della moderazione
 * successiva degli annunci Accessori, scritto come test sulle migrazioni.
 *
 * La decisione del titolare riguarda il MODELLO (nessuna approvazione
 * preventiva), non il rilascio: tutto parte spento, nessuna categoria è
 * pubblicabile per default, nessun ruolo di rilascio è assegnato, e visibile
 * non è acquistabile. Questi test fanno fallire la build se una migrazione
 * futura o questa lo contraddice.
 */

const progetto = join(import.meta.dir, "../../..");
const radiceRepo = join(progetto, "..");
const leggiRepo = (percorso: string) => readFileSync(join(radiceRepo, percorso), "utf8");
const senzaCommentiSql = (sorgente: string) =>
  sorgente.replace(/--.*$/gm, "").replace(/comment on [^;]*;/gi, "");

const ENUM = "supabase/migrations/20261022090000_vpm_015b3_report_target_annuncio_accessorio.sql";
const MIGRAZIONE = "supabase/migrations/20261022091000_vpm_015b3_pubblicazione_accessori.sql";
const sql = () => senzaCommentiSql(leggiRepo(MIGRAZIONE));

/** Il corpo di una funzione SQL (da `create ... function nome` al `$$;` che la chiude). */
const corpoFunzione = (nome: string): string => {
  const sorgente = sql();
  const inizio = sorgente.search(new RegExp(`create (?:or replace )?function ${nome.replace(/\./g, "\\.")}\\(`));
  expect(inizio).toBeGreaterThanOrEqual(0);
  const apre = sorgente.indexOf("$$", inizio);
  const chiude = sorgente.indexOf("$$;", apre + 2);
  return sorgente.slice(inizio, chiude + 3);
};

describe("B3: migrazioni additive e distinte", () => {
  it("il valore dell'enum sta in un file proprio, committato prima della migrazione principale", () => {
    expect(existsSync(join(radiceRepo, ENUM))).toBe(true);
    expect(existsSync(join(radiceRepo, MIGRAZIONE))).toBe(true);
    expect(senzaCommentiSql(leggiRepo(ENUM)).trim()).toBe(
      "alter type public.report_target_tipo add value if not exists 'annuncio_accessorio';",
    );
    expect(ENUM < MIGRAZIONE).toBe(true);
    // nessuna migrazione successiva alle B2 oltre alle due di B3
    const nuove = readdirSync(join(radiceRepo, "supabase/migrations")).filter((f) => f.slice(0, 14) > "20261021150000");
    expect(nuove.sort()).toEqual([ENUM, MIGRAZIONE].map((f) => f.replace("supabase/migrations/", "")));
  });

  it("nessuna riga di vendita: non tocca ordini, pagamenti, annunci del mercato, vino né configurazione economica", () => {
    const s = sql();
    expect(s).not.toMatch(
      /\b(public\.wines|bottle_units|cellar_slots|public\.listings\b|public\.orders|public\.payments|payouts|public\.proposals)\b/i,
    );
    expect(s).not.toMatch(/(insert\s+into|update|delete\s+from)\s+public\.marketplace_config/i);
    expect(s).not.toMatch(/\bdrop\s+table\b/i);
    expect(s).not.toMatch(/create (or replace )?view\s+(?!public\.moderation_report_queue)/i);
  });
});

describe("B3: tutto spento e chiuso di default", () => {
  it("nessun ruolo accessori_release assegnato e nessuna scrittura in user_roles", () => {
    const s = sql();
    expect(s).not.toMatch(/insert\s+into\s+public\.user_roles/i);
    expect(s).not.toMatch(/user_roles[^;]*accessori_release[^;]*insert/i);
  });

  it("nessuna categoria è pubblicabile per default: nessun seme né backfill da «vendibile»", () => {
    const s = sql();
    expect(s).not.toMatch(/^insert into private\.annunci_accessori_categorie_pubblicabili/m);
    // la tabella nuova non si popola leggendo la regola di preparazione
    expect(s).not.toMatch(/insert into private\.annunci_accessori_categorie_pubblicabili[\s\S]{0,300}from private\.annunci_accessori_categorie\b/);
    // «vendibile» non cambia e non diventa un consenso alla pubblicazione
    expect(s).not.toMatch(/update\s+private\.annunci_accessori_categorie\b/);
    expect(s).not.toMatch(/alter table private\.annunci_accessori_categorie\b(?!_pubblicabili)/);
  });

  it("l'interruttore di pubblicazione resta spento e si accende solo dal rilascio, anche per i writer privilegiati", () => {
    const s = sql();
    expect(s).not.toMatch(/update\s+private\.annunci_accessori_impostazioni\s+set\s+(?:[a-z_]+\s*=\s*[^,;]+,\s*)*pubblicazione_attiva\s*=\s*true/i);
    const guardia = corpoFunzione("private.annunci_accessori_impostazioni_guard");
    expect(guardia).toContain("new.pubblicazione_attiva and not old.pubblicazione_attiva");
    expect(guardia).toContain("vinae.accessori_rilascio");
    expect(guardia).toContain("rilascio_non_autorizzato");
    const porta = corpoFunzione("public.annunci_accessori_admin_pubblicazione_imposta");
    expect(porta).toContain("private.accessori_rilascio_richiesto()");
    expect(porta).toContain("private.accessori_admin_richiesto()");
    expect(porta).toContain("motivo_obbligatorio");
  });

  it("le categorie si approvano solo dal rilascio e mai se chiuse alla preparazione", () => {
    const guardia = corpoFunzione("private.annunci_accessori_categorie_pubblicabili_guard");
    expect(guardia).toContain("vinae.accessori_rilascio");
    expect(guardia).toContain("private.annuncio_accessorio_categoria_vendibile(new.categoria_id)");
    expect(guardia).toContain("categoria_genitore_non_approvata");
    const pubblicabile = corpoFunzione("private.annuncio_accessorio_categoria_pubblicabile");
    expect(pubblicabile).toContain("private.annuncio_accessorio_categoria_vendibile(p_categoria)");
    expect(pubblicabile).toContain("coalesce(");
  });
});

describe("B3: guardia unica sulle transizioni", () => {
  const guardia = () => corpoFunzione("private.annunci_accessori_guard");

  it("entrare in «pubblicato» richiede ogni requisito, per ogni writer", () => {
    const g = guardia();
    for (const requisito of [
      "private.annunci_accessori_pubblicazione_aperta()",
      "private.annuncio_accessorio_venditore(new.seller_id)",
      "private.annuncio_accessorio_categoria_pubblicabile(",
      "new.dichiarazione_conforme",
      "cardinality(v_imm) < 1",
      "private.annuncio_accessorio_testo_vietato(",
      "ripubblicazione_bloccata",
      "modifiche_non_effettuate",
      "private.preventivo_dominio(",
      "quantita_non_disponibile",
    ]) {
      expect(g).toContain(requisito);
    }
  });

  it("oscurare, chiedere modifiche e riaprire richiedono il marcatore della moderazione", () => {
    const g = guardia();
    expect(g).toContain("vinae.annuncio_accessorio_moderazione");
    expect(g).toContain("moderazione_riservata");
    expect(g).toMatch(/new\.stato = 'oscurato'/);
    expect(g).toMatch(/old\.stato = 'oscurato' and new\.stato <> 'ritirato'/);
  });

  it("un annuncio pubblicato si modifica solo con l'aggiornamento controllato, che incrementa la versione", () => {
    const g = guardia();
    expect(g).toContain("vinae.annuncio_accessorio_aggiorna");
    expect(g).toContain("new.versione := old.versione + 1");
    expect(g).toContain("annuncio_non_modificabile");
  });

  it("nessuno stato acquistabile: gli stati sono cinque e nessuno è «attivo»", () => {
    const s = sql();
    expect(s).toMatch(
      /check \(stato in \('bozza', 'pubblicato', 'modifiche_richieste', 'oscurato', 'ritirato'\)\)/,
    );
    // gli stati dell'annuncio non includono nulla di acquistabile (i valori 'attivo' delle azioni su listings sono un altro dominio)
    expect(/check (stato in (([^)]*)))/.exec(s)?.[1] ?? "").not.toMatch(/attivo|acquist|venduto|riservato/);
    // «in_revisione» sparisce: le righe esistenti tornano bozza, nessuna è cancellata
    expect(s).toMatch(/set stato = 'bozza', inviato_at = null\s+where stato = 'in_revisione'/);
    expect(s).not.toMatch(/delete\s+from\s+private\.annunci_accessori\b/i);
  });

  it("un annuncio oscurato continua a impegnare l'accessorio (un solo annuncio aperto, ritirato escluso)", () => {
    const s = sql();
    expect(s).toMatch(/create unique index annunci_accessori_uno_aperto[\s\S]*?where stato <> 'ritirato'/);
  });
});

describe("B3: snapshot pubblico separato dalla Cantina", () => {
  it("la forma pubblica non legge la Cantina né le note private", () => {
    const pubblico = corpoFunzione("private.annuncio_accessorio_pubblico_json");
    expect(pubblico).not.toMatch(/cantina_accessori/);
    // nessuna di queste è una chiave della forma pubblica (seller_id compare solo come join con il profilo pubblico)
    expect(pubblico).not.toMatch(/'(note_private|note|seller_id|cantina_id|cantina_accessorio_id|prezzo_unitario_cents)'/);
    expect(pubblico).not.toMatch(/note_private/);
    expect(pubblico).toContain("annunci_accessori_snapshot");
    expect(pubblico).toContain("'acquistabile', false");
  });

  it("lo snapshot si scrive solo alla pubblicazione e non si cancella da solo", () => {
    const guardia = corpoFunzione("private.annunci_accessori_snapshot_guard");
    expect(guardia).toContain("vinae.annuncio_accessorio_snapshot");
    expect(guardia).toContain("snapshot_protetto");
    expect(sql()).toMatch(/create constraint trigger annunci_accessori_snapshot_presente[\s\S]*?deferrable initially deferred/);
  });

  it("non si rifà alla riapertura da oscurato: l'amministrazione ha giudicato lo snapshot", () => {
    const t = corpoFunzione("private.annunci_accessori_snapshot_aggiorna");
    expect(t).toContain("old.stato <> 'oscurato'");
  });

  it("le foto restano nel bucket privato: firma solo per annunci visibili, mai la copia dei file", () => {
    const s = sql();
    expect(s).not.toMatch(/update\s+storage\.buckets/i);
    expect(s).not.toMatch(/insert\s+into\s+storage\.(buckets|objects)/i);
    expect(s).toContain('create policy "cantina_accessori_media_select_annunci_pubblicati"');
    expect(s).toContain('create policy "cantina_accessori_media_select_annunci_moderazione"');
    const pubblica = corpoFunzione("private.annuncio_accessorio_media_pubblica");
    expect(pubblica).toContain("private.annuncio_accessorio_visibile(s.annuncio_id)");
    const cancellabile = corpoFunzione("private.cantina_accessorio_media_cancellabile");
    expect(cancellabile).toContain("annunci_accessori_snapshot");
    // un file citato da un annuncio non ritirato non si cancella
    expect(cancellabile).toContain("an.stato <> 'ritirato'");
  });

  it("la visibilità richiede pubblicazione aperta, categoria ancora approvata e venditore ammesso", () => {
    const v = corpoFunzione("private.annuncio_accessorio_visibile");
    expect(v).toContain("private.annunci_accessori_pubblicazione_aperta()");
    expect(v).toContain("a.stato = 'pubblicato'");
    expect(v).toContain("private.annuncio_accessorio_categoria_pubblicabile(s.categoria_id)");
    expect(v).toContain("private.annuncio_accessorio_venditore(a.seller_id)");
  });
});

describe("B3: moderazione sul sistema esistente", () => {
  it("estende reports e le azioni esistenti: un bersaglio in più, nessun sistema parallelo", () => {
    const s = sql();
    expect(s).toContain("add column target_annuncio_accessorio_id uuid");
    expect(s).toMatch(/references private\.annunci_accessori \(id\) on delete set null/);
    for (const azione of [
      "public.moderazione_richiesta_modifiche",
      "public.moderazione_sospensione",
      "public.moderazione_rimozione",
      "public.moderazione_ripristino",
    ]) {
      expect(corpoFunzione(azione)).toContain("private.moderazione_annuncio_accessorio_transizione(");
    }
    // nessuna nuova tabella di segnalazioni, di audit o di ruoli
    const tabelle = [...s.matchAll(/create table\s+([a-z_.]+)/gi)].map((m) => m[1]);
    expect(tabelle).toEqual([
      "private.annunci_accessori_categorie_pubblicabili",
      "private.annunci_accessori_snapshot",
    ]);
  });

  it("il motore verifica lo stato, registra l'audit esistente, avvisa il venditore e usa il marcatore", () => {
    const m = corpoFunzione("private.moderazione_annuncio_accessorio_transizione");
    expect(m).toContain("private.audit_registra(");
    expect(m).toContain("public.notifications");
    expect(m).toContain("vinae.annuncio_accessorio_moderazione");
    expect(m).toContain("Motivazione obbligatoria.");
    // stesso ordine dei lock del venditore: accessorio, poi annuncio
    expect(m.indexOf("from private.cantina_accessori where id = v_cantina for update")).toBeLessThan(
      m.indexOf("from private.annunci_accessori where id = p_id for update"),
    );
  });

  it("la segnalazione è solo per utenti autenticati: nessuna porta anonima, con rate limit e dedupe", () => {
    const f = corpoFunzione("public.segnalazione_annuncio_accessorio_invia");
    expect(f).toContain("v_uid uuid := auth.uid()");
    expect(f).toContain("Autenticazione richiesta.");
    expect(f).toContain("private.rate_limit_consume('report:submit'");
    expect(f).toContain("Hai gia una segnalazione aperta");
    expect(f).toContain("private.annuncio_accessorio_visibile(p_id)");
    const s = sql();
    expect(s).toMatch(/revoke all on function public\.segnalazione_annuncio_accessorio_invia\(uuid, text, text\)\s+from public, anon, authenticated, service_role;/);
    expect(s).toMatch(/grant execute on function public\.segnalazione_annuncio_accessorio_invia\(uuid, text, text\) to authenticated;/);
  });

  it("le porte admin verificano il moderatore dentro la funzione", () => {
    for (const nome of [
      "public.annunci_accessori_admin_modera",
      "public.annunci_accessori_admin_elenca",
      "public.annunci_accessori_admin_dettaglio",
    ]) {
      expect(corpoFunzione(nome)).toContain("private.moderazione_attore()");
    }
  });
});

describe("B3: privilegi", () => {
  it("anon esegue solo le due letture pubbliche; mai service_role; ogni funzione fissa il search_path", () => {
    const s = sql();
    const grant = [...s.matchAll(/grant execute on function (public\.[a-z_]+)\([^)]*\) to ([a-z, ]+);/gi)];
    expect(grant.length).toBe(9);
    const anon = grant.filter((g) => /anon/.test(g[2])).map((g) => g[1]).sort();
    expect(anon).toEqual(["public.annunci_accessori_pubblici_elenca", "public.annunci_accessori_pubblico_dettaglio"]);
    for (const g of grant.filter((x) => !/anon/.test(x[2]))) expect(g[2].trim()).toBe("authenticated");
    // gli unici helper privati eseguibili dai ruoli client sono i due delle policy di Storage (che girano col chiamante)
    const privati = [...s.matchAll(/grant execute on function (private\.[a-z_]+)\([^)]*\) to ([a-z, ]+);/gi)].map(
      (m) => m[1],
    );
    expect(privati.sort()).toEqual([
      "private.annuncio_accessorio_media_moderabile",
      "private.annuncio_accessorio_media_pubblica",
    ]);
    expect(s).not.toMatch(/to service_role/i);
    const definer = [...s.matchAll(/security definer/gi)].length;
    const fissati = [...s.matchAll(/security definer\s+set search_path = ''/gi)].length;
    expect(definer).toBeGreaterThan(20);
    expect(fissati).toBe(definer);
  });

  it("le tabelle nuove stanno in private, con RLS attiva e senza grant ai ruoli client", () => {
    const s = sql();
    for (const t of ["private.annunci_accessori_categorie_pubblicabili", "private.annunci_accessori_snapshot"]) {
      expect(s).toContain(`alter table ${t} enable row level security`);
      expect(s).toContain(`revoke all on table ${t} from public, anon, authenticated`);
    }
    expect(s).not.toMatch(/grant\s+(select|insert|update|delete|all)\s+on\s+(table\s+)?private\./i);
  });
});

describe("B3: prove nel gate CI", () => {
  it("la griglia 12zk e la prova di concorrenza sono registrate e le mutazioni di controllo documentate", () => {
    const runner = leggiRepo("supabase/tests/12g_ci_run.sh");
    expect(runner).toContain("12zk_vpm_015b3_pubblicazione_accessori.sql");
    expect(runner).toContain("12zk_vpm_015b3_concorrenza.sh");
    expect(existsSync(join(radiceRepo, "supabase/tests/12zk_vpm_015b3_pubblicazione_accessori.sql"))).toBe(true);
    expect(existsSync(join(radiceRepo, "supabase/tests/12zk_vpm_015b3_concorrenza.sh"))).toBe(true);
    // prova con token reali (GoTrue, PostgREST, Storage), fixture e pulizia nel runner
    for (const file of ["e2e.mjs", "e2e_fixture.sql", "e2e_cleanup.sql"]) {
      expect(existsSync(join(radiceRepo, `supabase/tests/12zk_vpm_015b3_${file}`))).toBe(true);
    }
    expect(runner).toContain("12zk_vpm_015b3_e2e.mjs");
    expect(runner).toContain("12zk_vpm_015b3_e2e_cleanup.sql");
    expect(leggiRepo("supabase/tests/12zk_vpm_015b3_e2e.mjs")).toContain("limite documentato");
    expect(leggiRepo("docs/VPM_015B3_PUBBLICAZIONE_ACCESSORI.md")).toContain("Mutazioni di controllo");
  });
});
