/**
 * D10 — l'Area Admin come contratto.
 *
 * Due affermazioni, e vanno provate in due modi diversi.
 *
 * La prima riguarda **chi entra**, ed è una proprietà del sorgente: che la
 * route e il pannello non leggano il ruolo del selettore demo non si può
 * osservare montando un componente — con lo switcher spento i due valori
 * coincidono, e un test che passasse in quella configurazione non direbbe
 * niente sull'altra. Si legge il codice, come fanno già
 * `ReviewPanel.test.ts` e `seller-status.test.ts`.
 *
 * La seconda riguarda **che cosa la porta accetta**, ed è comportamento: il
 * doppio del client mostra quale RPC parte, con quali argomenti, e che cosa
 * torna. Il confine autoritativo resta comunque il database — `user_roles`, le
 * viste `moderation_*`, il controllo di ruolo in testa alla RPC — e quello lo
 * prova la griglia `supabase/tests/d10_admin_area.sql`, non questo file.
 */

import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { SupabaseClient } from "@supabase/supabase-js";
import { eAdminReale, ruoloDaSessione } from "@/lib/auth/role";
import {
  mapMyReport,
  mapQueueReport,
  risolviContestazione,
} from "@/services/phase9/supabase-moderation-service";
import { Phase9Error } from "@/services/phase9/shared";

const progetto = join(import.meta.dir, "../../../..");
const leggi = (percorso: string) => readFileSync(join(progetto, percorso), "utf8");

/**
 * Il sorgente senza commenti. Un contratto che vieta una parola deve guardare
 * il codice: la prosa che spiega *perché* quella parola è vietata la contiene
 * quasi sempre, e farebbe fallire la verifica per la ragione sbagliata.
 */
const senzaCommenti = (sorgente: string) =>
  sorgente
    .replace(/\{\s*\/\*(?:(?!\*\/)[\s\S])*\*\/\s*\}/g, "")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/.*$/gm, "$1");

const pagina = leggi("src/app/admin/page.tsx");
const paginaNuda = senzaCommenti(pagina);
const pannello = leggi("src/components/vinea/moderation/ModerationPanelClient.tsx");
const pannelloNudo = senzaCommenti(pannello);
const layoutNudo = senzaCommenti(leggi("src/components/vinea/Layout.tsx"));
const adapterNudo = senzaCommenti(leggi("src/services/phase9/supabase-moderation-service.ts"));
const controllerNudo = senzaCommenti(leggi("src/lib/phase9/use-phase9-moderation.ts"));

const MIGRAZIONE = readFileSync(
  join(progetto, "../supabase/migrations/20260828120000_d10_admin_dispute_gate.sql"),
  "utf8",
);

/**
 * Il SQL eseguibile, senza la prosa. Via le righe `--` e via l'istruzione
 * `comment on ...`: quel testo *descrive* la porta, e per farlo nomina
 * `rimborsata` e il rimborso. Cercare quelle parole nel file intero
 * significherebbe far fallire la verifica proprio sulla frase che dice che
 * sono fuori.
 */
const sqlEseguibile = (sorgente: string) =>
  sorgente
    .split("\n")
    .filter((riga) => !riga.trimStart().startsWith("--"))
    .join("\n")
    .replace(/comment on [\s\S]*?;/g, "");
const MIGRAZIONE_SQL = sqlEseguibile(MIGRAZIONE);
const MIGRAZIONE_9A = readFileSync(
  join(progetto, "../supabase/migrations/20260810152000_phase_9a_moderation_schema.sql"),
  "utf8",
);

// ---------------------------------------------------------------------------
// Doppio del client — stessa forma di moderation-service.test.ts
// ---------------------------------------------------------------------------

type Risposta = { data?: unknown; error?: { code?: string; message?: string } | null };

const fakeClient = (rpc: Risposta = { data: null }) => {
  const rpcChiamate: { nome: string; args: unknown }[] = [];
  const client = {
    from: () => {
      throw new Error("la risoluzione di una controversia non legge tabelle");
    },
    rpc: (nome: string, args: unknown) => {
      rpcChiamate.push({ nome, args });
      return Promise.resolve(rpc);
    },
  } as unknown as SupabaseClient;
  return { client, rpcChiamate };
};

// ---------------------------------------------------------------------------
// Il ruolo reale
// ---------------------------------------------------------------------------

describe("D10 - il ruolo reale e quello demo non sono lo stesso dato", () => {
  it("eAdminReale guarda i ruoli letti, non una stringa scelta", () => {
    expect(eAdminReale(["admin"])).toBe(true);
    expect(eAdminReale(["user", "admin"])).toBe(true);
    expect(eAdminReale([])).toBe(false);
    expect(eAdminReale(["user"])).toBe(false);
    // Nessuna scorciatoia sul nome: "amministratore", "Admin" e un ruolo che
    // contiene la parola non sono il ruolo.
    expect(eAdminReale(["Admin"])).toBe(false);
    expect(eAdminReale(["amministratore"])).toBe(false);
    expect(eAdminReale(["club_admin"])).toBe(false);
  });

  it("una sessione senza il ruolo a database non e admin, comunque la si guardi", () => {
    const sessione = { userId: "u1" };
    expect(ruoloDaSessione(sessione, [])).toBe("user");
    expect(ruoloDaSessione(sessione, ["admin"])).toBe("admin");
    expect(ruoloDaSessione(null, ["admin"])).toBe("guest");
  });

  it("lo switcher demo sostituisce `ruolo` e non tocca `authRuolo`", () => {
    // La riga che rende `ruolo` inaffidabile per un'autorizzazione: con la demo
    // accesa il valore e quello scelto a mano. Se questa forma cambiasse, il
    // resto di questo file starebbe difendendo un problema che non esiste piu -
    // ed e giusto accorgersene qui.
    const dominio = senzaCommenti(leggi("src/lib/store/auth-domain.ts"));
    expect(dominio).toInclude("ruolo: demoAbilitata ? ruolo : ruoloReale");
    // `authRuolo` viene dall'altro dominio, quello che legge user_roles.
    const reale = senzaCommenti(leggi("src/lib/store/real-auth-domain.ts"));
    expect(reale).toInclude("const authRuolo = ruoloDaSessione(authUser, ruoliCorrenti);");
    expect(reale).toInclude('supabaseAuthService.ruoliProfilo(userId)');
    // E lo store lo espone col suo tipo, altrimenti nessuna superficie puo
    // consumarlo e resta la sola via demo.
    expect(senzaCommenti(leggi("src/lib/vinea-store.tsx"))).toInclude("authRuolo: DemoRuolo;");
  });
});

// ---------------------------------------------------------------------------
// Il cancello di /admin
// ---------------------------------------------------------------------------

describe("D10 - /admin decide sul server", () => {
  it("verifica la sessione e i ruoli prima di rendere alcunche", () => {
    expect(paginaNuda).toInclude("await connection();");
    expect(paginaNuda).toInclude("await client.auth.getUser()");
    expect(paginaNuda).toInclude('.from("user_roles")');
    expect(paginaNuda).toInclude('.select("role")');
    expect(paginaNuda).toInclude("eAdminReale(ruoli)");
    // Le due uscite chiuse: anonimo alla pagina d'accesso, autenticato senza
    // ruolo a notFound(). Nessun ramo che renda il pannello senza il controllo.
    expect(paginaNuda).toInclude("redirect(PERCORSO_ACCESSO)");
    expect(paginaNuda).toInclude("if (!eAdminReale(ruoli)) notFound();");
    const posizionePannello = paginaNuda.indexOf("<ModerationPanelClient />");
    expect(posizionePannello).toBeGreaterThan(paginaNuda.indexOf("if (!eAdminReale(ruoli))"));
  });

  it("il client senza sessione, o assente del tutto, cade nel ramo chiuso", () => {
    // `!client` insieme a `!utente`: con Supabase non configurato non esiste
    // sessione verificabile, e la pagina non deve aprirsi "perche non si sa".
    expect(paginaNuda).toInclude("if (!client || !utente) redirect(PERCORSO_ACCESSO);");
  });

  it("un errore di lettura dei ruoli non apre la porta", () => {
    // Il ramo dell'errore produce l'insieme vuoto, cioe il ruolo meno
    // privilegiato. Un guasto non e un permesso.
    expect(paginaNuda).toMatch(/const ruoli = error\s*\?\s*\[\]/);
  });

  it("nessuna chiave di servizio nel percorso della pagina", () => {
    // Il client e quello anon coi cookie della richiesta: la lettura passa dalla
    // stessa RLS del browser. Una service key qui dentro salterebbe il confine.
    expect(paginaNuda).not.toMatch(/service_role|SERVICE_ROLE|SUPABASE_SERVICE/);
    expect(paginaNuda).toInclude("getSupabaseServerClient()");
  });

  it("la pagina resta fuori dagli indici", () => {
    expect(pagina).toInclude("robots: { index: false, follow: false }");
  });
});

describe("D10 - il pannello e la shell leggono il ruolo reale", () => {
  it("il pannello non decide su `ruolo`", () => {
    expect(pannelloNudo).toInclude("const { authRuolo } = useVinea();");
    expect(pannelloNudo).toInclude('const moderatore = authRuolo === "admin";');
    // La forma vecchia non deve tornare: era `const { ruolo } = useVinea()` con
    // `ruolo === "admin"`, cioe il selettore demo come autorizzazione.
    expect(pannelloNudo).not.toMatch(/\bruolo === "admin"/);
    expect(pannelloNudo).not.toMatch(/\{\s*ruolo\s*\}\s*=\s*useVinea/);
  });

  it("la voce Admin della shell compare sul ruolo reale", () => {
    expect(layoutNudo).toInclude('{authRuolo === "admin" && (');
    expect(layoutNudo).not.toMatch(/\{ruolo === "admin" &&/);
    // Il resto della shell continua a usare `ruolo`: la demo serve ancora a
    // esplorare guest e user, e toglierla non era il compito.
    expect(layoutNudo).toInclude('ruolo !== "guest"');
  });
});

// ---------------------------------------------------------------------------
// La coda: nessun sistema parallelo
// ---------------------------------------------------------------------------

describe("D10 - la moderazione resta quella della Fase 9", () => {
  it("le letture passano dalle proiezioni esistenti e da nessuna tabella base", () => {
    for (const vista of [
      "moderation_report_queue",
      "moderation_report_events",
      "moderation_audit_log",
      "moderation_dispute_queue",
      "my_reports",
      "my_report_events",
    ]) {
      expect(adapterNudo).toInclude(`"${vista}"`);
    }
    // Nessuna `.from()` su una tabella base di moderazione, e nessuna seconda
    // coda: niente moderation_v2, niente reports_v2, niente audit nuovo.
    expect(adapterNudo).not.toMatch(/\.from\("(reports|report_events|audit_log|disputes)"\)/);
    expect(adapterNudo).not.toMatch(/moderation_v2|reports_v2|audit_log_v2|_v2"/);
  });

  it("filtra le azioni secondo gli effetti realmente supportati dal bersaglio", () => {
    expect(pannelloNudo).toInclude(
      'if (report.targetType === "club") return ["info_richieste", "chiusura"]',
    );
    expect(pannelloNudo).toInclude(
      'if (report.targetType === "annuncio" || report.targetType === "profilo")',
    );
    expect(pannelloNudo).toInclude("return AZIONI_CON_ENFORCEMENT;");
    expect(pannelloNudo).toInclude("return AZIONI_SOLO_PRATICA;");
    expect(pannelloNudo).toInclude("azioniPerPratica(report).map");
    expect(pannelloNudo).not.toMatch(/report\.targetType === "club"[\s\S]{0,80}(sospensione|rimozione)/);
    expect(adapterNudo).toInclude('targetId: row.target_id ?? ""');
    expect(adapterNudo).not.toMatch(/moderation_v2|reports_v2|ModerationServiceV2/);
  });

  it("guida la lavorazione con una sola azione e una CTA contestuale", () => {
    expect(pannelloNudo).toInclude("const [azione, setAzione] = useState<ModAction | null>(null);");
    expect(pannelloNudo).toInclude('aria-label="Azione di moderazione"');
    expect(pannelloNudo).toInclude("AZIONE_UX[azione].cta");
    expect(pannelloNudo).toInclude('cta: "Chiudi segnalazione"');
    expect(pannelloNudo).toInclude(">Annulla</Button>");
    expect(pannelloNudo).not.toInclude(">Chiudi</Button>");
  });

  it("rende motivazione, durata e invio contestuali", () => {
    expect(pannelloNudo).toInclude("const pronta = azione !== null && motivazione.trim().length > 0;");
    expect(pannelloNudo).toInclude('{azione === "sospensione" ? (');
    expect(pannelloNudo).toInclude('durata: azione === "sospensione" ? durata : undefined');
    expect(pannelloNudo).toInclude(
      "if (!azione || !pronta || occupato || invioLocale.current) return;",
    );
    expect(pannelloNudo).toInclude("const invioLocale = useRef(false);");
    expect(pannelloNudo).toInclude("Visibile solo al team Vinea.");
  });

  it("Annulla chiude solo il dialogo, mentre chiusura passa alla RPC della pratica", () => {
    expect(pannelloNudo).toMatch(/<Button variant="ghost" onClick=\{onChiudi\}[^>]*>Annulla<\/Button>/);
    expect(pannelloNudo).toMatch(/await onAzione\(\{[\s\S]*azione,[\s\S]*\}\)/);
    expect(adapterNudo).toInclude('chiusura: "moderazione_chiusura"');
  });

  it("le pratiche terminali non espongono azioni", () => {
    expect(pannelloNudo).toInclude('report.stato === "risolta" || report.stato === "respinta"');
    expect(pannelloNudo).toInclude("{onApri && !chiusa(report) ? (");
  });

  it("le segnalazioni su recensione non hanno una coda propria", () => {
    // D9 manda le segnalazioni di una recensione nel sistema esistente:
    // `recensione` e un valore di report_target_tipo e `target_review_id` una
    // colonna di reports. Il pannello le mostra perche sono nella stessa coda,
    // non perche qualcuno le abbia ricablate.
    expect(MIGRAZIONE_9A).toInclude("'recensione'");
    expect(MIGRAZIONE_9A).toInclude("target_review_id uuid references public.order_reviews (id)");

    const report = mapQueueReport({
      id: "r9",
      codice: "SEG-2026-0009",
      target_tipo: "recensione",
      target_label: "Recensione di elena",
      target_id: "rev-1",
      motivo: "Contenuto offensivo",
      descrizione: "Insulti nel testo",
      foto: null,
      stato: "inviata",
      priorita: "alta",
      reporter_id: "u1",
      reporter_username: "elena",
      club_slug: null,
      created_at: "2026-08-27T10:00:00.000Z",
      updated_at: "2026-08-27T10:00:00.000Z",
    });
    expect(report.targetType).toBe("recensione");
    expect(report.targetId).toBe("rev-1");
    // Il segnalante e visibile al moderatore: decisione 7.4, invariata.
    expect(report.reporter).toBe("elena");
  });

  it("le note interne non raggiungono il segnalante", () => {
    // Il moderatore le separa dalla storia; la proiezione del segnalante non le
    // contiene affatto, quindi l'array e vuoto per costruzione.
    const eventi = [
      { id: "e1", report_id: "r1", visibile: true, testo: "pubblico", autore_etichetta: "mod", created_at: "2026-08-10T10:00:00.000Z" },
      { id: "e2", report_id: "r1", visibile: false, testo: "interno", autore_etichetta: "mod", created_at: "2026-08-10T11:00:00.000Z" },
    ];
    const perModeratore = mapQueueReport(
      {
        id: "r1", codice: "SEG-1", target_tipo: "annuncio", target_label: "x", target_id: "l1",
        motivo: "m", descrizione: "", foto: null, stato: "inviata", priorita: "media",
        reporter_id: "u1", reporter_username: "elena", club_slug: null,
        created_at: "2026-08-10T10:00:00.000Z", updated_at: "2026-08-10T10:00:00.000Z",
      },
      eventi,
    );
    expect(perModeratore.noteInterne.map((n) => n.testo)).toEqual(["interno"]);

    const perSegnalante = mapMyReport(
      {
        id: "r1", codice: "SEG-1", target_tipo: "annuncio", target_label: "x", target_id: "l1",
        motivo: "m", descrizione: "", foto: null, stato: "inviata", priorita: "media",
        club_slug: null, created_at: "2026-08-10T10:00:00.000Z", updated_at: "2026-08-10T10:00:00.000Z",
      },
      [{ id: "e1", report_id: "r1", testo: "pubblico", autore_etichetta: "mod", created_at: "2026-08-10T10:00:00.000Z" }],
    );
    expect(perSegnalante.noteInterne).toEqual([]);
    expect(perSegnalante.reporter).toBe("");
  });
});

// ---------------------------------------------------------------------------
// La porta delle controversie
// ---------------------------------------------------------------------------

describe("D10 - risolviContestazione", () => {
  it("chiama la porta stretta e non il motore di back-office", async () => {
    const { client, rpcChiamate } = fakeClient({
      data: {
        order_id: "o1",
        dispute_stato: "risolta",
        chiusura_at: "2026-08-28T10:00:00.000Z",
        gia_chiusa: false,
      },
    });
    const esito = await risolviContestazione(client, {
      orderId: "o1",
      esito: "risolta",
      nota: "  Accordo fra le parti  ",
    });

    expect(rpcChiamate).toHaveLength(1);
    expect(rpcChiamate[0].nome).toBe("moderazione_contestazione_risolvi");
    // Mai `ordine_contestazione_risolvi` dal browser: quella resta al
    // service_role, e la sua firma include `rimborsata`.
    expect(rpcChiamate[0].nome).not.toBe("ordine_contestazione_risolvi");
    expect(rpcChiamate[0].args).toEqual({
      p_order_id: "o1",
      p_esito: "risolta",
      p_nota: "Accordo fra le parti",
    });
    expect(esito).toEqual({
      orderId: "o1",
      disputeStato: "risolta",
      chiusuraAt: "2026-08-28T10:00:00.000Z",
      giaChiusa: false,
    });
  });

  it("respinge accetta la stessa porta", async () => {
    const { client, rpcChiamate } = fakeClient({
      data: { order_id: "o2", dispute_stato: "respinta", chiusura_at: null, gia_chiusa: false },
    });
    await risolviContestazione(client, { orderId: "o2", esito: "respinta", nota: "Prove insufficienti" });
    expect((rpcChiamate[0].args as { p_esito: string }).p_esito).toBe("respinta");
  });

  it("una motivazione vuota non arriva nemmeno al database", async () => {
    const { client, rpcChiamate } = fakeClient();
    await expect(
      risolviContestazione(client, { orderId: "o1", esito: "risolta", nota: "   " }),
    ).rejects.toThrow(Phase9Error);
    expect(rpcChiamate).toHaveLength(0);
  });

  it("un retry su pratica gia chiusa torna `giaChiusa` invece di un errore", async () => {
    const { client } = fakeClient({
      data: { order_id: "o1", dispute_stato: "risolta", chiusura_at: "2026-08-28T09:00:00.000Z", gia_chiusa: true },
    });
    const esito = await risolviContestazione(client, {
      orderId: "o1",
      esito: "risolta",
      nota: "Secondo invio",
    });
    expect(esito.giaChiusa).toBe(true);
    expect(esito.disputeStato).toBe("risolta");
  });

  it("l'errore del database non esce grezzo verso la pagina", async () => {
    const { client } = fakeClient({
      error: { code: "42501", message: "Non autorizzato a risolvere una contestazione." },
    });
    const errore = await risolviContestazione(client, {
      orderId: "o1",
      esito: "risolta",
      nota: "tentativo",
    }).catch((e: unknown) => e);
    expect(errore).toBeInstanceOf(Phase9Error);
    expect((errore as Phase9Error).code).toBe("42501");

    const opaco = await risolviContestazione(client, { orderId: "o1", esito: "risolta", nota: "x" })
      .catch((e: unknown) => e);
    expect((opaco as Error).message).not.toInclude("public.");
  });

  it("senza client configurato l'azione fallisce chiusa", async () => {
    await expect(
      risolviContestazione(null, { orderId: "o1", esito: "risolta", nota: "x" }),
    ).rejects.toThrow(Phase9Error);
  });

  it("il tipo dell'esito non contempla il rimborso", () => {
    // `EsitoContestazioneAdmin` e "risolta" | "respinta". La prova sta nel
    // sorgente perche un tipo non esiste a runtime: se qualcuno aggiungesse
    // "rimborsata" all'unione, questa riga cadrebbe.
    expect(adapterNudo).toInclude('export type EsitoContestazioneAdmin = "risolta" | "respinta";');
    expect(adapterNudo).not.toMatch(/p_esito:\s*"rimborsata"/);
  });
});

// ---------------------------------------------------------------------------
// La scheda Controversie
// ---------------------------------------------------------------------------

describe("D10 - la scheda Controversie", () => {
  it("offre due comandi soli e nessun rimborso", () => {
    expect(pannelloNudo).toInclude('void esegui("risolta")');
    expect(pannelloNudo).toInclude('void esegui("respinta")');
    // Nessun pulsante di rimborso, nessuna chiamata a un fornitore, nessuna
    // scrittura sui campi del pagamento: refund e provider restano spenti.
    expect(pannelloNudo).not.toMatch(/rimborsat|Rimborsa|refund|stripe|payment_status|payout_stato\s*=/i);
  });

  it("una pratica terminale non ha comandi attivi", () => {
    expect(pannelloNudo).toMatch(
      /riga\.stato === "aperta" \|\| riga\.stato === "in_valutazione"/,
    );
    expect(pannelloNudo).toInclude("{onRisolvi && lavorabile ? (");
  });

  it("il doppio invio e impedito dalla stessa chiave che il controller alza", () => {
    // I due pulsanti sono disabilitati mentre un'azione e in volo, e la nota
    // vuota li tiene spenti comunque.
    expect(pannelloNudo).toMatch(/disabled=\{!pronta \|\| occupato\}/);
    expect(pannelloNudo).toInclude("const occupato = inCorso !== null;");
    // La guardia si e stretta con le azioni controllate: alla chiave del
    // controller si e aggiunto il `ref` locale, che chiude la finestra fra il
    // click e il primo render disabilitato.
    expect(pannelloNudo).toInclude(
      "if (!onRisolvi || !pronta || occupato || invioLocale.current) return;",
    );
    // La chiave e per ordine, come per le segnalazioni: un flag globale
    // spegnerebbe i comandi di tutte le righe della coda.
    expect(controllerNudo).toInclude("setInCorso(`${orderId}:${esito}`);");
  });

  it("dopo il successo la coda si rilegge e l'errore finisce nello stato", () => {
    expect(controllerNudo).toMatch(
      /await risolviContestazione\(client, \{ orderId, esito, nota \}\);\s*setError\(null\);\s*await reload\(\);/,
    );
    expect(controllerNudo).toMatch(/catch \(e\) \{\s*setError\(messaggio\(e\)\);\s*throw e;/);
    // Senza servizio il comando non esiste, invece di esistere e non fare nulla.
    expect(controllerNudo).toInclude("risolviControversia: null,");
  });

  it("il componente non ricostruisce lo stato dell'ordine dal client", () => {
    // Nessuna sorgente di verita nuova nel frontend: la riga arriva dalla vista
    // e la scheda non deduce ne payout ne stato dell'ordine.
    expect(pannelloNudo).not.toMatch(/"completato"|"consegnato"|"trattenuto"|contestato_at/);
  });
});

// ---------------------------------------------------------------------------
// La migrazione
// ---------------------------------------------------------------------------

describe("D10 - la migrazione della porta admin", () => {
  it("e una funzione nuova, non una modifica del motore congelato", () => {
    expect(MIGRAZIONE).toInclude(
      "create or replace function public.moderazione_contestazione_risolvi(",
    );
    // Il motore della 7f non viene ridefinito qui.
    expect(MIGRAZIONE).not.toMatch(
      /create or replace function public\.ordine_contestazione_risolvi/,
    );
    // Viene invocato, quella si: la semantica di dominio resta una sola.
    expect(MIGRAZIONE).toInclude("perform public.ordine_contestazione_risolvi(");
  });

  it("richiede sessione e ruolo reale", () => {
    expect(MIGRAZIONE).toInclude("security definer");
    expect(MIGRAZIONE).toInclude("set search_path = ''");
    expect(MIGRAZIONE).toInclude("v_uid     uuid := auth.uid();");
    expect(MIGRAZIONE).toMatch(/if v_uid is null then\s*raise exception[\s\S]*?42501/);
    expect(MIGRAZIONE).toMatch(/if not public\.has_role\(v_uid, 'admin'\) then/);
  });

  it("ammette due esiti e non il rimborso", () => {
    expect(MIGRAZIONE).toInclude("p_esito not in ('risolta', 'respinta')");
    // `rimborsata` compare solo nella prosa che spiega perche e fuori: nel
    // codice non esiste un ramo che la accetti.
    expect(MIGRAZIONE_SQL).not.toInclude("rimborsata");
    // La firma prende `text` e non l'enum: con l'enum, `rimborsata` sarebbe un
    // valore legale fermato solo da un controllo che si puo dimenticare.
    expect(MIGRAZIONE).toInclude("p_esito    text,");
  });

  it("valida ordine e motivazione sul server", () => {
    expect(MIGRAZIONE).toInclude("from public.orders o where o.id = p_order_id");
    expect(MIGRAZIONE).toMatch(/if length\(v_nota\) = 0 then/);
    expect(MIGRAZIONE).toMatch(/if length\(v_nota\) > 1000 then/);
  });

  it("e idempotente e serializza due moderatori", () => {
    expect(MIGRAZIONE).toInclude("for update");
    expect(MIGRAZIONE).toMatch(/if v_dispute\.stato not in \('aperta', 'in_valutazione'\) then/);
    expect(MIGRAZIONE).toInclude("'gia_chiusa',    true");
  });

  it("non restituisce la riga di orders", () => {
    // Una SECURITY DEFINER che torna un rowtype consegna ogni colonna: i GRANT
    // di colonna non si applicano al risultato di una funzione.
    expect(MIGRAZIONE).toInclude("returns jsonb");
    expect(MIGRAZIONE).not.toMatch(/returns public\.orders/);
  });

  it("chiude i permessi e non tocca il denaro", () => {
    expect(MIGRAZIONE).toMatch(
      /revoke all on function public\.moderazione_contestazione_risolvi\(uuid, text, text\)\s*from public, anon, service_role;/,
    );
    expect(MIGRAZIONE).toMatch(
      /grant execute on function public\.moderazione_contestazione_risolvi\(uuid, text, text\)\s*to authenticated;/,
    );
    // `service_role` compare una volta sola, e nel revoke. Non basta ometterlo
    // dal grant: il progetto Supabase ha un `alter default privileges ... grant
    // all on functions to ... service_role`, quindi la funzione nasce gia con
    // quel permesso e va tolto esplicitamente. Un permesso che non si puo
    // esercitare - la porta pretende `auth.uid()`, che una chiave di servizio
    // non porta - invita a rendere facoltativa la sessione per farlo servire a
    // qualcosa: e da li che nascerebbe la regressione.
    const menzioniServiceRole = MIGRAZIONE_SQL.match(/service_role/g) ?? [];
    expect(menzioniServiceRole).toHaveLength(1);
    expect(MIGRAZIONE_SQL).not.toMatch(/grant[^;]*service_role/i);
    // Nessuna scrittura diretta su denaro o stato dell'ordine: tutto passa dal
    // motore. Nessun UPDATE in questo file, e nessun refund.
    expect(MIGRAZIONE_SQL).not.toMatch(/update public\.(orders|payouts|payments|disputes)/i);
    expect(MIGRAZIONE_SQL).not.toMatch(
      /payment_status|charges_enabled|payouts_enabled|transfer_data|on_behalf_of|refund|stripe/i,
    );
  });
});
