"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { getSupabaseClient } from "@/lib/supabase/client";
import {
  BUCKET_QUALIFICHE,
  percorsoDocumento,
  validaDocumento,
  validaQualifica,
} from "@/lib/qualifiche/validazione";
import type {
  ProfessionalQualificationService,
  QualificaDocumento,
  QualificaProfessionale,
  QualificaProfessionaleInput,
  QualificaProfessionaleStato,
  Result,
} from "./types";

/**
 * L'adattatore Supabase del dominio professionale, lato browser.
 *
 * QUI NON ESISTE UN VERDETTO. Non c'è un metodo che approvi, che rifiuti, che
 * scriva `reviewed_at` o che parli con un fornitore: `review_apply` è concessa
 * al solo `service_role` e non è raggiungibile da questo client, che porta la
 * chiave pubblicabile. Se questa classe crescesse fino ad avere un `approva()`,
 * la porta fidata sarebbe già stata spostata nel posto sbagliato.
 *
 * Ogni scrittura passa da una RPC: `INSERT`, `UPDATE` e `DELETE` diretti sulle
 * due tabelle sono revocati per `authenticated`, quindi non c'è una seconda
 * strada da tenere allineata.
 */

const NON_CONFIGURATO =
  "Supabase non configurato: imposta NEXT_PUBLIC_SUPABASE_URL e NEXT_PUBLIC_SUPABASE_ANON_KEY in frontend-next/.env.local.";

const NESSUNA_SESSIONE = "Nessuna sessione attiva.";

const senzaClient = <T>(): Result<T> => ({ ok: false, error: NON_CONFIGURATO });

/**
 * La mediazione degli errori. `P0001` è la classe che le RPC del dominio usano
 * per le proprie regole — «allega almeno un documento», «la qualifica non è più
 * modificabile» — e quei messaggi sono scritti per essere letti da chi li
 * riceve: si passano. Tutto il resto diventa una frase neutra, perché un
 * dettaglio di PostgreSQL in interfaccia racconta lo schema a chi guarda.
 */
const erroreServizio = (
  operazione: string,
  errore: { message?: string; code?: string } | null,
  ricaduta: string,
): string => {
  console.error(`[qualifiche] ${operazione} fallita:`, errore);
  if (errore?.code === "P0001" && errore.message) return errore.message;
  if (errore?.code === "42501") {
    return "Questa operazione non è consentita sulla qualifica in questo stato.";
  }
  return ricaduta;
};

type RigaDocumento = {
  id?: unknown;
  storage_path?: unknown;
  mime_type?: unknown;
  size_bytes?: unknown;
  created_at?: unknown;
};

type RigaQualifica = {
  id?: unknown;
  titolo?: unknown;
  ente_emittente?: unknown;
  paese?: unknown;
  credential_reference?: unknown;
  issued_on?: unknown;
  expires_on?: unknown;
  stato?: unknown;
  submitted_at?: unknown;
  reviewed_at?: unknown;
  created_at?: unknown;
  valida?: unknown;
  documenti_elenco?: unknown;
};

const STATI: readonly QualificaProfessionaleStato[] = [
  "bozza",
  "inviata",
  "approvata",
  "rifiutata",
  "ritirata",
];

const testo = (valore: unknown): string => (typeof valore === "string" ? valore : "");

const testoOpzionale = (valore: unknown): string | null =>
  typeof valore === "string" && valore !== "" ? valore : null;

const statoValido = (valore: unknown): QualificaProfessionaleStato =>
  STATI.includes(valore as QualificaProfessionaleStato)
    ? (valore as QualificaProfessionaleStato)
    : "bozza";

const mappaDocumento = (riga: RigaDocumento): QualificaDocumento => ({
  id: testo(riga.id),
  storagePath: testo(riga.storage_path),
  mimeType: testo(riga.mime_type),
  sizeBytes: typeof riga.size_bytes === "number" ? riga.size_bytes : 0,
  createdAt: testo(riga.created_at),
});

const mappaQualifica = (riga: RigaQualifica): QualificaProfessionale => ({
  id: testo(riga.id),
  titolo: testo(riga.titolo),
  enteEmittente: testo(riga.ente_emittente),
  paese: testoOpzionale(riga.paese),
  credentialReference: testoOpzionale(riga.credential_reference),
  issuedOn: testoOpzionale(riga.issued_on),
  expiresOn: testoOpzionale(riga.expires_on),
  stato: statoValido(riga.stato),
  submittedAt: testoOpzionale(riga.submitted_at),
  reviewedAt: testoOpzionale(riga.reviewed_at),
  createdAt: testo(riga.created_at),
  documenti: Array.isArray(riga.documenti_elenco)
    ? (riga.documenti_elenco as RigaDocumento[]).map(mappaDocumento)
    : [],
  valida: riga.valida === true,
});

const argomenti = (input: QualificaProfessionaleInput) => ({
  p_titolo: input.titolo,
  p_ente_emittente: input.enteEmittente,
  p_paese: input.paese,
  p_credential_reference: input.credentialReference,
  p_issued_on: input.issuedOn,
  p_expires_on: input.expiresOn,
});

/**
 * Le stesse regole del form, applicate anche qui: il pannello non è l'unico
 * chiamante possibile, e una RPC invocata con un titolo vuoto tornerebbe con un
 * errore del database invece che con una frase comprensibile.
 */
const normalizza = (input: QualificaProfessionaleInput) =>
  validaQualifica({
    titolo: input.titolo,
    enteEmittente: input.enteEmittente,
    paese: input.paese ?? "",
    credentialReference: input.credentialReference ?? "",
    issuedOn: input.issuedOn ?? "",
    expiresOn: input.expiresOn ?? "",
  });

export function creaProfessionalQualificationService(
  supabase: SupabaseClient | null,
): ProfessionalQualificationService {
  return {
    async elenco(): Promise<Result<QualificaProfessionale[]>> {
      if (!supabase) return senzaClient();
      const { data, error } = await supabase.rpc("professional_qualifications_me");
      if (error) {
        return {
          ok: false,
          error: erroreServizio(
            "lettura qualifiche",
            error,
            "Non è stato possibile leggere le tue qualifiche.",
          ),
        };
      }
      const righe = Array.isArray(data) ? (data as RigaQualifica[]) : [];
      return { ok: true, data: righe.map(mappaQualifica) };
    },

    async crea(input: QualificaProfessionaleInput): Promise<Result<string>> {
      if (!supabase) return senzaClient();
      const esito = normalizza(input);
      if (!esito.valido) return { ok: false, error: esito.errore };

      const { data, error } = await supabase.rpc(
        "professional_qualification_create",
        argomenti(esito.valore),
      );
      if (error) {
        return {
          ok: false,
          error: erroreServizio(
            "creazione qualifica",
            error,
            "Non è stato possibile creare la qualifica.",
          ),
        };
      }
      return { ok: true, data: testo(data) };
    },

    async aggiorna(id: string, input: QualificaProfessionaleInput): Promise<Result<void>> {
      if (!supabase) return senzaClient();
      const esito = normalizza(input);
      if (!esito.valido) return { ok: false, error: esito.errore };

      const { error } = await supabase.rpc("professional_qualification_update", {
        p_id: id,
        ...argomenti(esito.valore),
      });
      if (error) {
        return {
          ok: false,
          error: erroreServizio(
            "modifica qualifica",
            error,
            "Non è stato possibile salvare le modifiche.",
          ),
        };
      }
      return { ok: true, data: undefined };
    },

    /**
     * Prima l'oggetto, poi il metadato — e l'ordine non è indifferente.
     *
     * `document_register` verifica che l'oggetto esista davvero nel bucket:
     * registrare per primo il metadato significherebbe farlo fallire sempre. Se
     * invece è la registrazione a fallire, resta un oggetto privato senza riga,
     * e il rimedio è qui sotto: si prova a toglierlo. Se anche quel tentativo
     * fallisce l'oggetto resta orfano nel bucket privato — invisibile a
     * chiunque, non allegato a niente, e mai contato da un invio, che conta
     * soltanto i metadati con un oggetto corrispondente.
     */
    async caricaDocumento(qualificationId: string, file: File): Promise<Result<void>> {
      if (!supabase) return senzaClient();

      const controllo = validaDocumento(file);
      if (!controllo.valido) return { ok: false, error: controllo.errore };

      const { data: sessione } = await supabase.auth.getSession();
      const utente = sessione.session?.user;
      if (!utente) return { ok: false, error: NESSUNA_SESSIONE };

      const percorso = percorsoDocumento(
        utente.id,
        qualificationId,
        crypto.randomUUID(),
        controllo.estensione,
      );
      if (!percorso) return { ok: false, error: "Riferimento del documento non valido." };

      const { error: erroreUpload } = await supabase.storage
        .from(BUCKET_QUALIFICHE)
        .upload(percorso, file, { contentType: controllo.mime, upsert: false });
      if (erroreUpload) {
        console.error("[qualifiche] caricamento documento fallito:", erroreUpload);
        return { ok: false, error: "Non è stato possibile caricare il documento. Riprova." };
      }

      const { error: erroreRegistrazione } = await supabase.rpc(
        "professional_qualification_document_register",
        {
          p_qualification_id: qualificationId,
          p_storage_path: percorso,
          p_mime_type: controllo.mime,
          p_size_bytes: file.size,
        },
      );
      if (erroreRegistrazione) {
        await supabase.storage
          .from(BUCKET_QUALIFICHE)
          .remove([percorso])
          .catch(() => undefined);
        return {
          ok: false,
          error: erroreServizio(
            "registrazione documento",
            erroreRegistrazione,
            "Non è stato possibile allegare il documento.",
          ),
        };
      }
      return { ok: true, data: undefined };
    },

    /**
     * Prima l'oggetto, poi il metadato. La policy Storage consente la rimozione
     * solo mentre la qualifica è in bozza; se l'oggetto non viene rimosso, la
     * RPC non parte e il riferimento resta disponibile per riprovare. Il
     * servizio dichiara successo soltanto quando entrambe le metà sono sparite.
     */
    async eliminaDocumento(documento: QualificaDocumento): Promise<Result<void>> {
      if (!supabase) return senzaClient();

      const { error: erroreStorage } = await supabase.storage
        .from(BUCKET_QUALIFICHE)
        .remove([documento.storagePath]);
      if (erroreStorage) {
        return {
          ok: false,
          error: erroreServizio(
            "rimozione oggetto documento",
            erroreStorage,
            "Non è stato possibile eliminare il documento.",
          ),
        };
      }

      const { error } = await supabase.rpc("professional_qualification_document_delete", {
        p_document_id: documento.id,
      });
      if (error) {
        return {
          ok: false,
          error: erroreServizio(
            "eliminazione metadato documento",
            error,
            "Il documento è stato rimosso, ma non è stato possibile aggiornare la qualifica. Riprova.",
          ),
        };
      }
      return { ok: true, data: undefined };
    },

    async invia(id: string): Promise<Result<QualificaProfessionaleStato>> {
      if (!supabase) return senzaClient();
      const { data, error } = await supabase.rpc("professional_qualification_submit", {
        p_id: id,
      });
      if (error) {
        return {
          ok: false,
          error: erroreServizio(
            "invio qualifica",
            error,
            "Non è stato possibile inviare la qualifica.",
          ),
        };
      }
      return { ok: true, data: statoValido(data) };
    },

    async ritira(id: string): Promise<Result<QualificaProfessionaleStato>> {
      if (!supabase) return senzaClient();
      const { data, error } = await supabase.rpc("professional_qualification_withdraw", {
        p_id: id,
      });
      if (error) {
        return {
          ok: false,
          error: erroreServizio(
            "ritiro qualifica",
            error,
            "Non è stato possibile ritirare la qualifica.",
          ),
        };
      }
      return { ok: true, data: statoValido(data) };
    },
  };
}

/** Istanza usata dall'app, costruita sul client del browser. */
export const professionalQualificationService = (): ProfessionalQualificationService =>
  creaProfessionalQualificationService(getSupabaseClient());
