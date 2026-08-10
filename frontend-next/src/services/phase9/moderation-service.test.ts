import { describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  codaContestazioni,
  createSupabaseModerationService,
  mapAuditEntry,
  mapDisputeRow,
  mapMyReport,
  mapQueueReport,
  motiviAmmessi,
} from "@/services/phase9/supabase-moderation-service";
import { Phase9Error } from "@/services/phase9/shared";
import { priorityFromReason, reportReasons } from "@/data/moderation";

// ---------------------------------------------------------------------------
// Doppio del client: registra le tabelle interrogate, cosi un test puo provare
// che l'adapter non tocca mai una tabella base.
// ---------------------------------------------------------------------------

type Risposta = { data?: unknown; error?: { code?: string; message?: string } | null };

const fakeClient = (
  risposte: Record<string, Risposta>,
  rpc: Risposta = { data: null },
) => {
  const tabelleLette: string[] = [];
  const rpcChiamate: { nome: string; args: unknown }[] = [];

  const builder = (tabella: string) => {
    tabelleLette.push(tabella);
    const risultato = risposte[tabella] ?? { data: [] };
    const chain: Record<string, unknown> = {};
    for (const metodo of ["select", "order", "limit", "in", "eq"]) {
      chain[metodo] = () => chain;
    }
    chain.maybeSingle = () => Promise.resolve(risultato);
    // Il builder di supabase-js e thenable: await su di esso risolve la query.
    chain.then = (onOk: (v: Risposta) => unknown) => Promise.resolve(risultato).then(onOk);
    return chain;
  };

  const client = {
    from: (tabella: string) => builder(tabella),
    rpc: (nome: string, args: unknown) => {
      rpcChiamate.push({ nome, args });
      return Promise.resolve(rpc);
    },
  } as unknown as SupabaseClient;

  return { client, tabelleLette, rpcChiamate };
};

// ---------------------------------------------------------------------------
// Righe di riferimento
// ---------------------------------------------------------------------------

const queueRow: Parameters<typeof mapQueueReport>[0] = {
  id: "r1",
  codice: "SEG-2026-0001",
  target_tipo: "annuncio",
  target_label: "Barolo 2015",
  target_id: "l1",
  motivo: "Descrizione ingannevole",
  descrizione: "Le foto non corrispondono",
  foto: null,
  stato: "inviata",
  priorita: "media",
  reporter_id: "u1",
  reporter_username: "elena",
  club_slug: null,
  created_at: "2026-08-10T10:00:00.000Z",
  updated_at: "2026-08-10T10:00:00.000Z",
};

// my_reports non ha reporter_id ne reporter_username: la proiezione del
// segnalante non li contiene. Questo helper produce la riga come arriva da
// quella vista, invece di destrutturare via due campi in ogni test.
const senzaSegnalante = (row: typeof queueRow): Parameters<typeof mapMyReport>[0] => {
  const copia: Record<string, unknown> = { ...row };
  delete copia.reporter_id;
  delete copia.reporter_username;
  return copia as Parameters<typeof mapMyReport>[0];
};

const auditRow: Parameters<typeof mapAuditEntry>[0] = {
  id: "a1",
  ts: "2026-08-10T11:00:00.000Z",
  attore_username: "moderatore",
  scope: "piattaforma",
  club_slug: null,
  azione: "ammonizione",
  target_tipo: "annuncio",
  target_id: "l1",
  target_label: "Barolo 2015",
  motivazione: "Descrizione non conforme",
  durata: null,
  report_id: "r1",
};

describe("Fase 9a - mappatura", () => {
  it("separa storia visibile e note interne per il moderatore", () => {
    const report = mapQueueReport(queueRow, [
      {
        id: "e1",
        report_id: "r1",
        visibile: true,
        testo: "Segnalazione ricevuta",
        autore_etichetta: "Moderazione",
        created_at: "2026-08-10T10:00:00.000Z",
      },
      {
        id: "e2",
        report_id: "r1",
        visibile: false,
        testo: "Nota riservata",
        autore_etichetta: "moderatore",
        created_at: "2026-08-10T10:05:00.000Z",
      },
    ]);
    expect(report.storia.map((v: { testo: string }) => v.testo)).toEqual(["Segnalazione ricevuta"]);
    expect(report.noteInterne.map((v: { testo: string }) => v.testo)).toEqual(["Nota riservata"]);
  });

  it("decisione 7.4: il moderatore legge il segnalante", () => {
    expect(mapQueueReport(queueRow).reporter).toBe("elena");
  });

  it("decisione 7.4: la vista del segnalante non porta l'identita del segnalante", () => {
    const mia = senzaSegnalante(queueRow);
    expect(mapMyReport(mia).reporter).toBe("");
  });

  it("le note interne sono vuote per costruzione lato segnalante", () => {
    const mia = senzaSegnalante(queueRow);
    const report = mapMyReport(mia, [
      {
        id: "e1",
        report_id: "r1",
        testo: "Segnalazione ricevuta",
        autore_etichetta: "Moderazione",
        created_at: "2026-08-10T10:00:00.000Z",
      },
    ]);
    expect(report.storia).toHaveLength(1);
    expect(report.noteInterne).toEqual([]);
  });

  it("decisione 7.5: nessun report mappato porta un assignee", () => {
    expect(mapQueueReport(queueRow).assignee).toBeUndefined();
  });

  it("decisione 7.8b: nessuna voce di audit porta un ricorso", () => {
    expect(mapAuditEntry(auditRow).ricorso).toBeUndefined();
  });

  it("mappa durata e clubSlug solo quando valorizzati", () => {
    expect(mapAuditEntry(auditRow).durata).toBeUndefined();
    expect(mapAuditEntry({ ...auditRow, durata: "7 giorni" }).durata).toBe("7 giorni");
    expect(mapAuditEntry({ ...auditRow, scope: "club", club_slug: "barolo" }).clubSlug).toBe(
      "barolo",
    );
  });

  it("foto nulla diventa array vuoto e non undefined", () => {
    expect(mapQueueReport(queueRow).foto).toEqual([]);
    expect(mapQueueReport({ ...queueRow, foto: ["a.png"] }).foto).toEqual(["a.png"]);
  });

  it("mappa la riga della coda contestazioni conservando i due totali", () => {
    const riga = mapDisputeRow({
      id: "d1",
      order_id: "o1",
      aperta_da: "u1",
      aperta_da_username: "compratore",
      seller_id: "u2",
      seller_username: "venditore",
      motivo: "Bottiglia non conforme",
      descrizione: "",
      foto: null,
      stato: "aperta",
      esito_nota: null,
      risolta_da: null,
      apertura_at: "2026-08-10T09:00:00.000Z",
      chiusura_at: null,
      ordine_stato: "contestato",
      ordine_payout_stato: "bloccato",
      totale_cents: 12000,
      addebito_totale_cents: 12500,
    });
    // I due totali restano distinti: l'imballaggio della 7c sta nel secondo.
    expect(riga.totaleCents).toBe(12000);
    expect(riga.addebitoTotaleCents).toBe(12500);
    expect(riga.foto).toEqual([]);
  });
});

describe("Fase 9a - lettura", () => {
  it("la coda passa dalla proiezione e non dalle tabelle base", async () => {
    const { client, tabelleLette } = fakeClient({
      moderation_report_queue: { data: [queueRow] },
      moderation_report_events: { data: [] },
    });
    const service = createSupabaseModerationService(client);
    const coda = await service.coda();
    expect(coda).toHaveLength(1);
    expect(tabelleLette).toEqual(["moderation_report_queue", "moderation_report_events"]);
    expect(tabelleLette).not.toContain("reports");
    expect(tabelleLette).not.toContain("report_events");
  });

  it("l'audit passa dalla proiezione e non da audit_log", async () => {
    const { client, tabelleLette } = fakeClient({
      moderation_audit_log: { data: [auditRow] },
    });
    const voci = await createSupabaseModerationService(client).auditLog();
    expect(voci).toHaveLength(1);
    expect(tabelleLette).toEqual(["moderation_audit_log"]);
    expect(tabelleLette).not.toContain("audit_log");
  });

  it("con coda vuota non interroga la tabella degli eventi", async () => {
    const { client, tabelleLette } = fakeClient({ moderation_report_queue: { data: [] } });
    expect(await createSupabaseModerationService(client).coda()).toEqual([]);
    expect(tabelleLette).toEqual(["moderation_report_queue"]);
  });

  it("segnalazioniUtente non filtra lato client: il filtro e nella vista", async () => {
    const mia = senzaSegnalante(queueRow);
    const { client, tabelleLette } = fakeClient({
      my_reports: { data: [mia] },
      my_report_events: { data: [] },
    });
    // L'id passato e di un altro utente: deve essere ignorato, non usato.
    const righe = await createSupabaseModerationService(client).segnalazioniUtente("altro-utente");
    expect(righe).toHaveLength(1);
    expect(tabelleLette).toEqual(["my_reports", "my_report_events"]);
  });

  it("la coda contestazioni passa dalla propria proiezione", async () => {
    const { client, tabelleLette } = fakeClient({ moderation_dispute_queue: { data: [] } });
    expect(await codaContestazioni(client)).toEqual([]);
    expect(tabelleLette).toEqual(["moderation_dispute_queue"]);
    expect(tabelleLette).not.toContain("disputes");
  });

  it("i motivi ammessi arrivano raggruppati per tipo di bersaglio", async () => {
    const { client } = fakeClient({
      report_reasons: {
        data: [
          { target_tipo: "annuncio", motivo: "Prezzo anomalo", ordine: 4 },
          { target_tipo: "annuncio", motivo: "Annuncio duplicato", ordine: 6 },
          { target_tipo: "profilo", motivo: "Identita sospetta", ordine: 1 },
        ],
      },
    });
    expect(await motiviAmmessi(client)).toEqual({
      annuncio: ["Prezzo anomalo", "Annuncio duplicato"],
      profilo: ["Identita sospetta"],
    });
  });
});

describe("Fase 9a - scrittura e limiti dichiarati", () => {
  it("segnala chiama la RPC e non scrive mai in reports", async () => {
    const mia = senzaSegnalante(queueRow);
    const { client, tabelleLette, rpcChiamate } = fakeClient(
      { my_reports: { data: mia } },
      { data: "r1" },
    );
    const creata = await createSupabaseModerationService(client).segnala({
      targetType: "annuncio",
      targetId: "l1",
      targetLabel: "Barolo 2015",
      reason: "Descrizione ingannevole",
      descrizione: "Le foto non corrispondono",
      foto: [],
      priorita: "bassa",
      reporter: "chiunque",
      updatedAt: "2026-01-01T00:00:00.000Z",
      storia: [],
      noteInterne: [],
    });
    expect(rpcChiamate[0]?.nome).toBe("segnalazione_invia");
    expect(tabelleLette).toEqual(["my_reports"]);
    // Priorita e stato vengono riletti dal server, non da cio che il client ha
    // passato: aveva chiesto "bassa" e la riga canonica dice "media".
    expect(creata.priorita).toBe("media");
    expect(creata.stato).toBe("inviata");
  });

  it("la RPC non riceve ne priorita ne stato ne identita del segnalante", async () => {
    const mia = senzaSegnalante(queueRow);
    const { client, rpcChiamate } = fakeClient({ my_reports: { data: mia } }, { data: "r1" });
    await createSupabaseModerationService(client).segnala({
      targetType: "annuncio",
      targetId: "l1",
      targetLabel: "Barolo 2015",
      reason: "Prezzo anomalo",
      descrizione: "",
      foto: [],
      priorita: "alta",
      reporter: "qualcun-altro",
      updatedAt: "2026-01-01T00:00:00.000Z",
      storia: [],
      noteInterne: [],
    });
    const args = rpcChiamate[0]?.args as Record<string, unknown>;
    expect(Object.keys(args).sort()).toEqual([
      "p_club_slug",
      "p_descrizione",
      "p_foto",
      "p_motivo",
      "p_target_id",
      "p_target_label",
      "p_target_tipo",
    ]);
  });

  it("le due azioni di moderazione dichiarano di appartenere al 9b", async () => {
    const service = createSupabaseModerationService(fakeClient({}).client);
    expect(service.aggiornaStato("r1", "risolta")).rejects.toThrow("checkpoint 9b");
    expect(
      service.eseguiAzione({ tipo: "annuncio", id: "l1" }, "ammonizione", "motivo"),
    ).rejects.toThrow("checkpoint 9b");
  });

  it("senza client configurato solleva un errore leggibile", async () => {
    const service = createSupabaseModerationService(null);
    expect(service.coda()).rejects.toThrow("Supabase non configurata");
  });

  it("un errore di Postgres non leggibile non raggiunge la UI", async () => {
    const { client } = fakeClient({
      moderation_report_queue: { error: { code: "42P01", message: 'relation "x" does not exist' } },
    });
    try {
      await createSupabaseModerationService(client).coda();
      throw new Error("doveva sollevare");
    } catch (e) {
      expect(e).toBeInstanceOf(Phase9Error);
      expect((e as Error).message).not.toContain("relation");
      expect((e as Phase9Error).code).toBe("42P01");
    }
  });

  it("un errore dichiarato dalla RPC resta leggibile", async () => {
    const { client } = fakeClient(
      {},
      { error: { code: "P0001", message: "Hai gia una segnalazione aperta su questo contenuto." } },
    );
    expect(
      createSupabaseModerationService(client).segnala({
        targetType: "annuncio",
        targetId: "l1",
        targetLabel: "X",
        reason: "Prezzo anomalo",
        descrizione: "",
        foto: [],
        priorita: "bassa",
        reporter: "",
        updatedAt: "",
        storia: [],
        noteInterne: [],
      }),
    ).rejects.toThrow("Hai gia una segnalazione aperta");
  });
});

describe("Fase 9a - parita con il mock legacy", () => {
  // La priorita e derivata dal server. Questi casi provano che la regola SQL e
  // la copia TypeScript danno la stessa risposta sugli stessi motivi: se
  // divergessero, la coda mostrerebbe una priorita diversa da quella su cui e
  // ordinata.
  it("priorityFromReason concorda con la regola SQL su tutti i motivi reali", () => {
    const attesi: Record<string, string> = {
      "Tentativo di truffa": "alta",
      "Sospetta frode": "alta",
      "Molestie ripetute": "alta",
      "Richiesta di pagamento fuori piattaforma": "alta",
      "Truffa in corso": "alta",
      "Contenuto offensivo": "media",
      "Comunicazione offensiva": "media",
      "Recensione falsa": "media",
      "Foto non veritiere o riciclate": "media",
      "Descrizione ingannevole": "media",
      "Prezzo anomalo": "bassa",
      "Annuncio duplicato": "bassa",
      "Identita sospetta": "bassa",
    };
    for (const [motivo, atteso] of Object.entries(attesi)) {
      expect(priorityFromReason(motivo)).toBe(atteso as never);
    }
  });

  it("decisione 7.6a: i motivi portati sono i cinque tipi, senza post e commento", () => {
    const portati = ["annuncio", "profilo", "messaggio", "conversazione", "recensione"] as const;
    const totale = portati.reduce((n, tipo) => n + reportReasons[tipo].length, 0);
    // Ventuno righe in public.report_reasons: e lo stesso numero che il caso 20
    // della griglia statica verifica a database.
    expect(totale).toBe(21);
    expect(reportReasons.post.length + reportReasons.commento.length).toBe(7);
  });
});
