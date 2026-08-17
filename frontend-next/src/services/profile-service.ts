"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { getSupabaseClient } from "@/lib/supabase/client";
import type { Esperienza } from "@/data/onboarding";
import type { ProfileService, ProfiloCorrente, ProfiloModifica, Result } from "./types";

const NOT_CONFIGURED_ERROR =
  "Supabase non configurato: imposta NEXT_PUBLIC_SUPABASE_URL e NEXT_PUBLIC_SUPABASE_ANON_KEY in frontend-next/.env.local.";

const NESSUNA_SESSIONE = "Nessuna sessione attiva.";

/**
 * Elenco chiuso invece di `select("*")`, come `order-service.ts` e
 * `payment-service.ts`: `profiles` porta anche le quattro colonne di moderazione
 * della 9b, che l'utente può leggere di sé ma che non appartengono a questa
 * schermata. Una colonna aggiunta domani resta fuori finché qualcuno non la
 * nomina qui.
 */
const COLONNE_PROFILO = "id, username, bio, citta, provincia, esperienza, avatar_url, dob";

const ESPERIENZE: readonly Esperienza[] = [
  "curioso",
  "appassionato",
  "collezionista",
  "esperto",
] as const;

/**
 * Il CHECK su `profiles.esperienza` ammette quattro valori. Un valore fuori
 * elenco non può arrivare dal nostro form, ma può stare in una riga scritta
 * altrove: ricadere su `curioso` è preferibile a far esplodere la lettura di un
 * profilo per una casella di selezione.
 */
function esperienzaValida(valore: unknown): Esperienza {
  return ESPERIENZE.includes(valore as Esperienza) ? (valore as Esperienza) : "curioso";
}

function testo(valore: unknown): string {
  return typeof valore === "string" ? valore : "";
}

type RigaProfilo = Record<string, unknown>;

function mappaProfilo(riga: RigaProfilo, email: string | null): ProfiloCorrente {
  return {
    userId: testo(riga.id),
    email,
    username: testo(riga.username),
    bio: testo(riga.bio),
    citta: testo(riga.citta),
    provincia: testo(riga.provincia),
    esperienza: esperienzaValida(riga.esperienza),
    avatarUrl: testo(riga.avatar_url),
    dob: typeof riga.dob === "string" ? riga.dob : null,
  };
}

/**
 * Traduce in italiano i soli errori che l'utente può correggere da solo; per
 * gli altri resta il messaggio del server, che non espone dettagli interni
 * perché arriva già filtrato da PostgREST.
 *
 * `23505` è la violazione di unicità su `profiles.username`. È il caso normale
 * e non un'anomalia: il nome di partenza lo assegna il trigger
 * `handle_new_user()` e due persone possono volere lo stesso.
 */
function messaggioErrore(errore: { code?: string; message: string }): string {
  if (errore.code === "23505" || errore.message.includes("profiles_username_key")) {
    return "Questo nome utente è già in uso. Scegline un altro.";
  }
  if (errore.code === "23514" && errore.message.includes("dob")) {
    return "Devi avere almeno 18 anni per usare Vinea.";
  }
  return errore.message;
}

/**
 * Profilo del solo utente collegato.
 *
 * L'identificativo non è un parametro: viene risolto qui dalla sessione. La
 * policy `profiles_update_own` (`using`/`with check` su `auth.uid() = id`)
 * resta la barriera autoritativa, e il `GRANT UPDATE` per colonna della 9b
 * limita comunque la scrittura alle otto colonne del profilo pubblico — nessuna
 * delle quattro di moderazione è raggiungibile da qui.
 */
export function creaProfileService(supabase: SupabaseClient): ProfileService {
  const servizio: ProfileService = {
    async leggiProfiloCorrente(): Promise<Result<ProfiloCorrente | null>> {
      const { data: sessione } = await supabase.auth.getSession();
      const utente = sessione.session?.user;
      if (!utente) return { ok: true, data: null };

      const { data, error } = await supabase
        .from("profiles")
        .select(COLONNE_PROFILO)
        .eq("id", utente.id)
        .maybeSingle();
      if (error) return { ok: false, error: messaggioErrore(error) };
      if (!data) return { ok: true, data: null };

      return { ok: true, data: mappaProfilo(data as RigaProfilo, utente.email ?? null) };
    },

    async aggiornaProfiloCorrente(patch: ProfiloModifica): Promise<Result<ProfiloCorrente>> {
      const { data: sessione } = await supabase.auth.getSession();
      const utente = sessione.session?.user;
      if (!utente) return { ok: false, error: NESSUNA_SESSIONE };

      // Solo le chiavi davvero presenti finiscono nell'UPDATE: un `undefined`
      // inviato a PostgREST sovrascriverebbe la colonna con NULL, e su
      // `username`, che è `not null`, sarebbe un errore al posto di un no-op.
      const scrittura: Record<string, string> = {};
      if (patch.username !== undefined) scrittura.username = patch.username.trim();
      if (patch.bio !== undefined) scrittura.bio = patch.bio;
      if (patch.citta !== undefined) scrittura.citta = patch.citta.trim();
      if (patch.provincia !== undefined) scrittura.provincia = patch.provincia.trim();
      if (patch.esperienza !== undefined) scrittura.esperienza = patch.esperienza;
      if (patch.avatarUrl !== undefined) scrittura.avatar_url = patch.avatarUrl;
      if (patch.dob !== undefined) scrittura.dob = patch.dob;

      if (Object.keys(scrittura).length === 0) {
        const attuale = await servizio.leggiProfiloCorrente();
        if (!attuale.ok) return attuale;
        if (!attuale.data) return { ok: false, error: NESSUNA_SESSIONE };
        return { ok: true, data: attuale.data };
      }

      // Una sola istruzione per tutti i campi: il completamento del profilo
      // scrive nome utente e data di nascita **insieme**, così non esiste uno
      // stato intermedio in cui uno dei due è passato e l'altro no.
      const { data, error } = await supabase
        .from("profiles")
        .update(scrittura)
        .eq("id", utente.id)
        .select(COLONNE_PROFILO)
        .maybeSingle();
      if (error) return { ok: false, error: messaggioErrore(error) };
      if (!data) return { ok: false, error: "Profilo non trovato." };

      return { ok: true, data: mappaProfilo(data as RigaProfilo, utente.email ?? null) };
    },
  };

  return servizio;
}

/**
 * Istanza usata dall'app, costruita sul client del browser. Resta separata
 * dalla fabbrica perché `getSupabaseClient()` può tornare `null` quando le
 * variabili non sono configurate: in quel caso la superficie fallisce chiusa
 * con un messaggio, invece di costruire un servizio su un client inesistente.
 */
export const supabaseProfileService: ProfileService = {
  async leggiProfiloCorrente() {
    const supabase = getSupabaseClient();
    if (!supabase) return { ok: false, error: NOT_CONFIGURED_ERROR };
    return creaProfileService(supabase).leggiProfiloCorrente();
  },
  async aggiornaProfiloCorrente(patch) {
    const supabase = getSupabaseClient();
    if (!supabase) return { ok: false, error: NOT_CONFIGURED_ERROR };
    return creaProfileService(supabase).aggiornaProfiloCorrente(patch);
  },
} satisfies ProfileService;
