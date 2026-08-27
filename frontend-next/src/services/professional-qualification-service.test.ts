import { afterAll, beforeAll, describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import { creaProfessionalQualificationService } from "@/services/professional-qualification-service";
import type { QualificaDocumento } from "@/services/types";

const OWNER = "d1a00000-0000-4000-8000-000000000001";
const QUALIFICA = "d1b00000-0000-4000-8000-000000000002";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type ErroreFinto = { message?: string; code?: string } | null;

type Copione = {
  rpc?: Record<string, { data?: unknown; error?: ErroreFinto }>;
  upload?: ErroreFinto;
  remove?: ErroreFinto;
  sessione?: boolean;
};

type Registro = {
  rpc: { nome: string; argomenti: Record<string, unknown> }[];
  upload: { percorso: string; opzioni: Record<string, unknown> }[];
  remove: string[][];
  operazioni: string[];
};

function clientFinto(copione: Copione = {}): { client: SupabaseClient; registro: Registro } {
  const registro: Registro = { rpc: [], upload: [], remove: [], operazioni: [] };
  const bucket = {
    async upload(percorso: string, _file: unknown, opzioni: Record<string, unknown>) {
      registro.upload.push({ percorso, opzioni });
      registro.operazioni.push("upload");
      return { data: null, error: copione.upload ?? null };
    },
    async remove(percorsi: string[]) {
      registro.remove.push(percorsi);
      registro.operazioni.push("remove");
      return { data: null, error: copione.remove ?? null };
    },
  };
  const client = {
    async rpc(nome: string, argomenti: Record<string, unknown> = {}) {
      registro.rpc.push({ nome, argomenti });
      registro.operazioni.push(`rpc:${nome}`);
      const risposta = copione.rpc?.[nome] ?? {};
      return { data: risposta.data ?? null, error: risposta.error ?? null };
    },
    auth: {
      async getSession() {
        return {
          data: {
            session: copione.sessione === false ? null : { user: { id: OWNER } },
          },
        };
      },
    },
    storage: { from: () => bucket },
  };
  return { client: client as unknown as SupabaseClient, registro };
}

const documento: QualificaDocumento = {
  id: "d1c00000-0000-4000-8000-000000000003",
  storagePath: `${OWNER}/${QUALIFICA}/d1c00000-0000-4000-8000-000000000003.pdf`,
  mimeType: "application/pdf",
  sizeBytes: 2048,
  createdAt: "2026-08-01T10:00:00Z",
};

const pdf = (dimensione = 2048): File =>
  ({ type: "application/pdf", size: dimensione, name: "diploma.pdf" }) as unknown as File;

const input = {
  titolo: "Sommelier professionista",
  enteEmittente: "Associazione Italiana Sommelier",
  paese: null,
  credentialReference: null,
  issuedOn: null,
  expiresOn: null,
};

// I fallimenti attesi passano per `console.error` — è dove il dettaglio tecnico
// deve restare. Qui si tace per non sporcare l'output della suite.
const erroreOriginale = console.error;
beforeAll(() => {
  console.error = () => {};
});
afterAll(() => {
  console.error = erroreOriginale;
});

describe("ProfessionalQualificationService", () => {
  it("senza client configurato nessuna operazione parte", async () => {
    const servizio = creaProfessionalQualificationService(null);
    for (const esito of [
      await servizio.elenco(),
      await servizio.crea(input),
      await servizio.invia(QUALIFICA),
      await servizio.ritira(QUALIFICA),
      await servizio.caricaDocumento(QUALIFICA, pdf()),
      await servizio.eliminaDocumento(documento),
    ]) {
      expect(esito.ok).toBe(false);
    }
  });

  it("non espone nessun metodo di verdetto: la porta fidata non è qui", () => {
    const { client } = clientFinto();
    const chiavi = Object.keys(creaProfessionalQualificationService(client));
    expect(chiavi).toEqual([
      "elenco",
      "crea",
      "aggiorna",
      "caricaDocumento",
      "eliminaDocumento",
      "invia",
      "ritira",
    ]);
    expect(chiavi.join(" ")).not.toMatch(/approv|rifiut|review|verdict|provider/i);
  });
});

describe("elenco", () => {
  it("mappa la riga della RPC, documenti compresi", async () => {
    const { client, registro } = clientFinto({
      rpc: {
        professional_qualifications_me: {
          data: [
            {
              id: QUALIFICA,
              titolo: "Enologo",
              ente_emittente: "Ordine",
              paese: "IT",
              credential_reference: "AB-12",
              issued_on: "2019-06-01",
              expires_on: null,
              stato: "approvata",
              submitted_at: "2026-08-01T09:00:00Z",
              reviewed_at: "2026-08-02T09:00:00Z",
              created_at: "2026-07-31T09:00:00Z",
              valida: true,
              documenti_elenco: [
                {
                  id: documento.id,
                  storage_path: documento.storagePath,
                  mime_type: "application/pdf",
                  size_bytes: 2048,
                  created_at: documento.createdAt,
                },
              ],
            },
          ],
        },
      },
    });

    const esito = await creaProfessionalQualificationService(client).elenco();
    expect(registro.rpc).toEqual([{ nome: "professional_qualifications_me", argomenti: {} }]);
    expect(esito.ok && esito.data).toEqual([
      {
        id: QUALIFICA,
        titolo: "Enologo",
        enteEmittente: "Ordine",
        paese: "IT",
        credentialReference: "AB-12",
        issuedOn: "2019-06-01",
        expiresOn: null,
        stato: "approvata",
        submittedAt: "2026-08-01T09:00:00Z",
        reviewedAt: "2026-08-02T09:00:00Z",
        createdAt: "2026-07-31T09:00:00Z",
        documenti: [documento],
        valida: true,
      },
    ]);
  });

  it("uno stato sconosciuto non diventa un permesso: ricade in bozza", async () => {
    const { client } = clientFinto({
      rpc: {
        professional_qualifications_me: {
          data: [{ id: QUALIFICA, titolo: "X", stato: "approvatissima", valida: "true" }],
        },
      },
    });
    const esito = await creaProfessionalQualificationService(client).elenco();
    expect(esito.ok && esito.data[0]?.stato).toBe("bozza");
    // `valida` è booleano, e una stringa non lo è: la spunta resta spenta.
    expect(esito.ok && esito.data[0]?.valida).toBe(false);
    expect(esito.ok && esito.data[0]?.documenti).toEqual([]);
  });
});

describe("mediazione degli errori", () => {
  const conErrore = (errore: ErroreFinto) =>
    creaProfessionalQualificationService(
      clientFinto({ rpc: { professional_qualification_submit: { error: errore } } }).client,
    ).invia(QUALIFICA);

  it("la regola di dominio arriva a chi la legge", async () => {
    const esito = await conErrore({ code: "P0001", message: "Allega almeno un documento." });
    expect(esito).toEqual({ ok: false, error: "Allega almeno un documento." });
  });

  it("un permesso negato diventa una frase sullo stato, non sul database", async () => {
    const esito = await conErrore({ code: "42501", message: "permission denied for table ..." });
    expect(esito.ok).toBe(false);
    expect(!esito.ok && esito.error).toBe(
      "Questa operazione non è consentita sulla qualifica in questo stato.",
    );
  });

  it("ogni altro errore non racconta PostgreSQL", async () => {
    const esito = await conErrore({ code: "22P02", message: 'invalid input syntax for type uuid' });
    expect(!esito.ok && esito.error).toBe("Non è stato possibile inviare la qualifica.");
  });
});

describe("crea", () => {
  it("una qualifica senza titolo non raggiunge il database", async () => {
    const { client, registro } = clientFinto();
    const esito = await creaProfessionalQualificationService(client).crea({
      ...input,
      titolo: "  ",
    });
    expect(esito.ok).toBe(false);
    expect(registro.rpc).toEqual([]);
  });

  it("passa i campi normalizzati alla RPC e restituisce l'identificativo", async () => {
    const { client, registro } = clientFinto({
      rpc: { professional_qualification_create: { data: QUALIFICA } },
    });
    const esito = await creaProfessionalQualificationService(client).crea({
      ...input,
      titolo: "  Enologo  ",
      paese: "it",
    });
    expect(esito).toEqual({ ok: true, data: QUALIFICA });
    expect(registro.rpc[0]?.argomenti).toEqual({
      p_titolo: "Enologo",
      p_ente_emittente: "Associazione Italiana Sommelier",
      p_paese: "IT",
      p_credential_reference: null,
      p_issued_on: null,
      p_expires_on: null,
    });
  });
});

describe("caricaDocumento", () => {
  it("un tipo non ammesso non tocca il bucket", async () => {
    const { client, registro } = clientFinto();
    const esito = await creaProfessionalQualificationService(client).caricaDocumento(
      QUALIFICA,
      { type: "application/zip", size: 10, name: "prove.zip" } as unknown as File,
    );
    expect(esito.ok).toBe(false);
    expect(registro.upload).toEqual([]);
    expect(registro.rpc).toEqual([]);
  });

  it("senza sessione non si carica nulla", async () => {
    const { client, registro } = clientFinto({ sessione: false });
    const esito = await creaProfessionalQualificationService(client).caricaDocumento(
      QUALIFICA,
      pdf(),
    );
    expect(esito.ok).toBe(false);
    expect(registro.upload).toEqual([]);
  });

  it("scrive in `<titolare>/<qualifica>/<file>.<ext>` e non sovrascrive", async () => {
    const { client, registro } = clientFinto();
    const esito = await creaProfessionalQualificationService(client).caricaDocumento(
      QUALIFICA,
      pdf(),
    );
    expect(esito.ok).toBe(true);
    const [caricamento] = registro.upload;
    const parti = caricamento!.percorso.split("/");
    expect(parti[0]).toBe(OWNER);
    expect(parti[1]).toBe(QUALIFICA);
    expect(parti[2]?.replace(/\.pdf$/, "")).toMatch(UUID);
    expect(caricamento!.opzioni).toEqual({ contentType: "application/pdf", upsert: false });
    // Prima l'oggetto, poi il metadato: `document_register` verifica che
    // l'oggetto esista.
    expect(registro.rpc).toHaveLength(1);
    expect(registro.rpc[0]?.nome).toBe("professional_qualification_document_register");
    expect(registro.rpc[0]?.argomenti).toEqual({
      p_qualification_id: QUALIFICA,
      p_storage_path: caricamento!.percorso,
      p_mime_type: "application/pdf",
      p_size_bytes: 2048,
    });
  });

  it("un upload fallito non registra alcun metadato", async () => {
    const { client, registro } = clientFinto({ upload: { message: "quota" } });
    const esito = await creaProfessionalQualificationService(client).caricaDocumento(
      QUALIFICA,
      pdf(),
    );
    expect(esito.ok).toBe(false);
    expect(registro.rpc).toEqual([]);
  });

  it("se la registrazione fallisce l'oggetto caricato viene ritirato", async () => {
    const { client, registro } = clientFinto({
      rpc: {
        professional_qualification_document_register: {
          error: { code: "P0001", message: "La qualifica non è più modificabile." },
        },
      },
    });
    const esito = await creaProfessionalQualificationService(client).caricaDocumento(
      QUALIFICA,
      pdf(),
    );
    expect(esito).toEqual({ ok: false, error: "La qualifica non è più modificabile." });
    expect(registro.remove).toEqual([[registro.upload[0]!.percorso]]);
  });
});

describe("eliminaDocumento", () => {
  it("rimuove prima l'oggetto e poi il metadato", async () => {
    const { client, registro } = clientFinto();
    const esito = await creaProfessionalQualificationService(client).eliminaDocumento(documento);
    expect(esito.ok).toBe(true);
    expect(registro.remove).toEqual([[documento.storagePath]]);
    expect(registro.rpc).toEqual([
      {
        nome: "professional_qualification_document_delete",
        argomenti: { p_document_id: documento.id },
      },
    ]);
    expect(registro.operazioni).toEqual([
      "remove",
      "rpc:professional_qualification_document_delete",
    ]);
  });

  it("se l'oggetto non si lascia togliere il metadato resta per poter riprovare", async () => {
    const { client, registro } = clientFinto({ remove: { message: "storage unavailable" } });
    const esito = await creaProfessionalQualificationService(client).eliminaDocumento(documento);
    expect(esito).toEqual({
      ok: false,
      error: "Non è stato possibile eliminare il documento.",
    });
    expect(registro.rpc).toEqual([]);
  });

  it("non dichiara successo se la rimozione del metadato fallisce", async () => {
    const { client, registro } = clientFinto({
      rpc: {
        professional_qualification_document_delete: {
          error: { code: "42501", message: "permission denied" },
        },
      },
    });
    const esito = await creaProfessionalQualificationService(client).eliminaDocumento(documento);
    expect(esito.ok).toBe(false);
    expect(registro.remove).toEqual([[documento.storagePath]]);
  });
});

describe("invia e ritira", () => {
  it("restituiscono lo stato deciso dal database", async () => {
    const { client, registro } = clientFinto({
      rpc: {
        professional_qualification_submit: { data: "inviata" },
        professional_qualification_withdraw: { data: "ritirata" },
      },
    });
    const servizio = creaProfessionalQualificationService(client);
    expect(await servizio.invia(QUALIFICA)).toEqual({ ok: true, data: "inviata" });
    expect(await servizio.ritira(QUALIFICA)).toEqual({ ok: true, data: "ritirata" });
    expect(registro.rpc.map((c) => c.nome)).toEqual([
      "professional_qualification_submit",
      "professional_qualification_withdraw",
    ]);
    expect(registro.rpc.every((c) => c.argomenti.p_id === QUALIFICA)).toBe(true);
  });
});
