"use server";

import { getSupabaseServerClient } from "@/lib/supabase/server";
import { BUCKET_ANNUNCI } from "@/services/listing-service";
import type { Result } from "@/services/types";

/**
 * Firma di un upload verso il bucket `annunci`.
 *
 * PERCHÉ IL PERCORSO LO SCEGLIE IL SERVER. Il browser manda solo tipo e
 * dimensione del file; il percorso `<uid>/<uuid>.<estensione>` lo costruisce
 * questa funzione, dopo aver letto chi è l'utente dalla sessione. Un client che
 * proponesse il proprio percorso potrebbe tentare di scrivere nella cartella di
 * qualcun altro, o di sovrascrivere una foto esistente indovinandone il nome.
 *
 * La policy `annunci_insert_propria_cartella` su storage.objects ricontrolla
 * comunque che la prima cartella del percorso sia l'id di chi scrive: questa
 * funzione è comoda, la policy è la garanzia. Anche i limiti di tipo e
 * dimensione sono doppi — qui per dare un messaggio sensato, e su
 * `storage.buckets` (allowed_mime_types, file_size_limit) perché è lì che
 * vengono applicati davvero, anche a chi salta del tutto l'interfaccia.
 *
 * Le Server Function sono raggiungibili con una POST diretta, non solo dalla
 * UI: l'autorizzazione va verificata qui dentro, ed è la prima cosa che fa.
 */

/** Deve restare allineato con `allowed_mime_types` del bucket `annunci`. */
const ESTENSIONI: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "image/avif": "avif",
};

/** Deve restare allineato con `file_size_limit` del bucket `annunci`. */
const DIMENSIONE_MASSIMA = 5 * 1024 * 1024;

export type UploadFirmato = { percorso: string; token: string };

export async function firmaUploadFoto(
  mime: string,
  dimensione: number,
): Promise<Result<UploadFirmato>> {
  const client = await getSupabaseServerClient();
  if (!client) {
    return { ok: false, error: "Connessione a Supabase non configurata." };
  }

  const { data: utente, error: erroreUtente } = await client.auth.getUser();
  if (erroreUtente || !utente.user) {
    return { ok: false, error: "Devi accedere per caricare una fotografia." };
  }

  const estensione = ESTENSIONI[mime];
  if (!estensione) {
    return { ok: false, error: "Formato non supportato: usa JPEG, PNG, WebP o AVIF." };
  }
  if (!Number.isFinite(dimensione) || dimensione <= 0 || dimensione > DIMENSIONE_MASSIMA) {
    return { ok: false, error: "La fotografia non può superare 5 MB." };
  }

  const percorso = `${utente.user.id}/${crypto.randomUUID()}.${estensione}`;

  const { data, error } = await client.storage
    .from(BUCKET_ANNUNCI)
    .createSignedUploadUrl(percorso);

  if (error || !data) {
    console.error("[vendi] firma upload fallita:", error);
    return { ok: false, error: "Non è stato possibile preparare il caricamento. Riprova." };
  }

  return { ok: true, data: { percorso, token: data.token } };
}
