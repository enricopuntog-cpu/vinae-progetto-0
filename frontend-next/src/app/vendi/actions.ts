"use server";

import { getSupabaseServerClient } from "@/lib/supabase/server";
import { BUCKET_CANTINA } from "@/services/cellar-service";
import { BUCKET_ANNUNCI } from "@/services/listing-service";
import type { Result } from "@/services/types";

/**
 * Firma di un upload verso il bucket pubblico `annunci` o quello privato
 * `cantina`, scelto dal percorso già deciso nel wizard.
 *
 * PERCHÉ IL PERCORSO LO SCEGLIE IL SERVER. Il browser manda solo tipo e
 * dimensione del file; il percorso `<uid>/<uuid>.<estensione>` lo costruisce
 * questa funzione, dopo aver letto chi è l'utente dalla sessione. Un client che
 * proponesse il proprio percorso potrebbe tentare di scrivere nella cartella di
 * qualcun altro, o di sovrascrivere una foto esistente indovinandone il nome.
 *
 * Le policy dei due bucket ricontrollano comunque che la prima cartella del
 * percorso sia l'id di chi scrive: questa funzione è comoda, la policy è la
 * garanzia. Anche i limiti di tipo e dimensione sono doppi — qui per dare un
 * messaggio sensato, e su
 * `storage.buckets` (allowed_mime_types, file_size_limit) perché è lì che
 * vengono applicati davvero, anche a chi salta del tutto l'interfaccia.
 *
 * Le Server Function sono raggiungibili con una POST diretta, non solo dalla
 * UI: l'autorizzazione va verificata qui dentro, ed è la prima cosa che fa.
 */

/** Deve restare allineato con `allowed_mime_types` di entrambi i bucket. */
const ESTENSIONI: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "image/avif": "avif",
};

/** Deve restare allineato con `file_size_limit` di entrambi i bucket. */
const DIMENSIONE_MASSIMA = 5 * 1024 * 1024;

export type UsoFoto = "annuncio" | "cantina";
export type UploadFirmato = { bucket: string; percorso: string; token: string };

export async function firmaUploadFoto(
  mime: string,
  dimensione: number,
  uso: UsoFoto,
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
  const bucket = uso === "annuncio" ? BUCKET_ANNUNCI : BUCKET_CANTINA;

  const { data, error } = await client.storage
    .from(bucket)
    .createSignedUploadUrl(percorso);

  if (error || !data) {
    console.error("[vendi] firma upload fallita:", error);
    return { ok: false, error: "Non è stato possibile preparare il caricamento. Riprova." };
  }

  return { ok: true, data: { bucket, percorso, token: data.token } };
}

// ---------------------------------------------------------------------------
// Riuso di quello che la bottiglia ha già
// ---------------------------------------------------------------------------

/** Una fotografia pronta per lo step Foto: percorso in `annunci` più anteprima. */
export type FotoRiusata = { percorso: string; anteprima: string };

export type RiusoDaCantina = {
  foto: FotoRiusata[];
  /**
   * Il prezzo dell'ultimo annuncio di questa bottiglia, se ce n'è stato uno.
   * Serve a proporlo invece di chiederlo a vuoto — chi rimette in vendita una
   * bottiglia tolta dalla vendita un prezzo l'aveva già fatto. Va **confermato**
   * dal venditore, non applicato in silenzio: è passato del tempo, e un prezzo
   * ereditato senza che nessuno lo guardi è peggio di un campo vuoto.
   */
  prezzoCentsPrecedente: number | null;
};

/**
 * Le fotografie della bottiglia, copiate dal bucket privato `cantina` a quello
 * pubblico `annunci`, più il prezzo dell'ultimo annuncio.
 *
 * PERCHÉ SI COPIA E NON SI REFERENZIA. `cantina` è privato e si legge solo con
 * un URL firmato a scadenza; `annunci` è pubblico e `listings.immagini` viene
 * ricomposto in URL pubblico da `urlImmagine()`. Mettere un percorso di
 * `cantina` dentro `listings.immagini` produrrebbe un URL pubblico verso un
 * oggetto che in quel bucket non esiste: un'immagine rotta per chi compra. E
 * puntare l'annuncio pubblico al file privato non è comunque una scelta
 * disponibile — sarebbe pubblicare il contenuto della cantina di qualcuno per
 * il fatto di averlo messo in vendita una volta. Copiare lascia l'originale
 * privato dov'è, e mette in vendita una copia.
 *
 * PERCHÉ IL CLIENT NON MANDA I PERCORSI. Riceve solo l'id della bottiglia: i
 * percorsi li legge il server da `bottle_units.immagini`, e la RLS decide se
 * quella riga è sua. Un client che proponesse i percorsi chiederebbe di copiare
 * file scelti da lui — la stessa ragione per cui `firmaUploadFoto` costruisce
 * il percorso qui invece di accettarlo.
 *
 * La copia gira con la sessione dell'utente, quindi passa da entrambe le
 * policy: `cantina_select_propria_cartella` sull'origine e
 * `annunci_insert_propria_cartella` sulla destinazione. Il percorso nuovo
 * comincia con il suo id, com'è richiesto da tutte e due.
 */
export async function riusaFotoDellaBottiglia(
  bottleUnitId: string,
): Promise<Result<RiusoDaCantina>> {
  const client = await getSupabaseServerClient();
  if (!client) {
    return { ok: false, error: "Connessione a Supabase non configurata." };
  }

  const { data: utente, error: erroreUtente } = await client.auth.getUser();
  if (erroreUtente || !utente.user) {
    return { ok: false, error: "Devi accedere per mettere in vendita una bottiglia." };
  }
  const uid = utente.user.id;

  const { data: bottiglia, error: erroreBottiglia } = await client
    .from("bottle_units")
    .select("immagini")
    .eq("id", bottleUnitId)
    .maybeSingle();

  if (erroreBottiglia) {
    console.error("[vendi] lettura bottiglia per riuso foto fallita:", erroreBottiglia);
    return { ok: false, error: "Non è stato possibile leggere la bottiglia. Riprova." };
  }
  // Nessuna riga significa che non è sua: la RLS l'ha filtrata. Non è un
  // errore da mostrare, è semplicemente niente da riusare.
  if (!bottiglia) return { ok: true, data: { foto: [], prezzoCentsPrecedente: null } };

  const percorsiCantina = (bottiglia.immagini as string[] | null) ?? [];

  const foto: FotoRiusata[] = [];
  for (const origine of percorsiCantina) {
    // Le illustrazioni dei dati di prova (`/images/...`) non stanno in nessun
    // bucket: si passano così come sono, che è già ciò che `urlImmagine()` fa
    // con loro.
    if (origine.startsWith("/") || origine.startsWith("http")) {
      foto.push({ percorso: origine, anteprima: origine });
      continue;
    }

    const estensione = origine.split(".").pop()?.toLowerCase();
    if (!estensione || !Object.values(ESTENSIONI).includes(estensione)) continue;

    const destinazione = `${uid}/${crypto.randomUUID()}.${estensione}`;
    const { error } = await client.storage
      .from(BUCKET_CANTINA)
      .copy(origine, destinazione, { destinationBucket: BUCKET_ANNUNCI });

    if (error) {
      // Una foto che non si copia non ferma le altre: il venditore ne trova
      // qualcuna di meno e può aggiungerne, che è molto meglio di uno step
      // vuoto senza spiegazione.
      console.error(`[vendi] copia foto ${origine} fallita:`, error);
      continue;
    }

    foto.push({ percorso: destinazione, anteprima: urlPubblicoAnnunci(destinazione) });
  }

  const { data: ultimo } = await client
    .from("listings")
    .select("prezzo_cents")
    .eq("bottle_unit_id", bottleUnitId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  return {
    ok: true,
    data: { foto, prezzoCentsPrecedente: ultimo?.prezzo_cents ?? null },
  };
}

/**
 * L'URL pubblico di un oggetto di `annunci`. Ricalca `urlImmagine()` del
 * servizio invece di importarlo perché questo file gira sul server, dove
 * `NEXT_PUBLIC_SUPABASE_URL` c'è ma il modulo del servizio porterebbe con sé
 * mezzo client Supabase per una concatenazione di stringhe.
 */
function urlPubblicoAnnunci(percorso: string): string {
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL;
  if (!base) return percorso;
  return `${base}/storage/v1/object/public/${BUCKET_ANNUNCI}/${percorso}`;
}
