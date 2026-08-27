/**
 * Il profilo pubblico di un'altra persona, in sola lettura.
 *
 * NON HA `"use client"`, e non è una dimenticanza. La pagina che userà questo
 * servizio è una destinazione raggiunta da un link — da un annuncio, da un post
 * del Club — e va resa dal server: un profilo che esiste solo dopo l'idratazione
 * è un profilo che nessun motore di ricerca vede e che appare in ritardo a chi
 * lo apre. Il modulo prende quindi il client Supabase come parametro
 * (`creaPublicProfileService`) invece di procurarselo da
 * `@/lib/supabase/client`, che è un modulo browser: chi rende dal server passa
 * il proprio client, chi rende nel browser passa il suo. Nessuna delle due
 * strade è cablata qui.
 *
 * PERCHÉ UNA RPC E NON UNA TABELLA. `public.profiles` non è e non diventa
 * leggibile pubblicamente: la policy `profiles_select_own` resta l'unica, e la
 * migrazione 20260825180000 non l'allarga. La proiezione pubblica vive nello
 * schema `private`, dove PostgREST non arriva, e l'unica porta è
 * `public.profilo_pubblico(uuid)` — una funzione che prende un identificativo e
 * restituisce al massimo una riga. È la ragione per cui questo servizio non
 * può offrire un elenco nemmeno volendo: non esiste la chiamata.
 *
 * NIENTE DATI INVENTATI. Non c'è un rating, non c'è un conteggio di recensioni,
 * non c'è un badge di fiducia e non c'è un livello: nessuna di quelle cose ha
 * oggi una sorgente, e mostrarne una a zero o a `false` significherebbe
 * affermare qualcosa su una persona senza averlo misurato.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { riferimentoAvatarSicuro } from "@/lib/profilo/avatar";
import { COLONNE_ANNUNCIO_PUBBLICO, rigaAWine, type PublicListingRow } from "./listing-service";
import type { Esperienza } from "@/data/onboarding";
import type { Wine } from "@/data/wines";
import type {
  ProfiloPubblico,
  PublicProfileService,
  QualificaProfessionalePubblica,
  Result,
} from "./types";

const NOT_CONFIGURED_ERROR =
  "Supabase non configurato: imposta NEXT_PUBLIC_SUPABASE_URL e NEXT_PUBLIC_SUPABASE_ANON_KEY in frontend-next/.env.local.";

const LETTURA_FALLITA = "Non è stato possibile leggere questo profilo.";
const ANNUNCI_FALLITI = "Non è stato possibile leggere gli annunci di questa persona.";

/**
 * Il nome della funzione SQL, in un posto solo. La firma è
 * `profilo_pubblico(p_user_id uuid)` e restituisce le sette colonne
 * dell'allowlist: nessun parametro di ricerca, nessun limite, nessun offset —
 * aggiungerne uno qui non servirebbe a niente, perché la funzione non li ha.
 */
const RPC_PROFILO_PUBBLICO = "profilo_pubblico";

/**
 * Un identificativo malformato non arriva al database.
 *
 * Non è una convalida di sicurezza — la barriera è la funzione SQL, non questa
 * riga — ma un modo di dare la risposta giusta: passare `"pippo"` a un
 * parametro `uuid` produce un errore PostgreSQL (`22P02`), che finirebbe nel
 * ramo «lettura fallita» e mostrerebbe un guasto dove invece c'è semplicemente
 * un indirizzo che non corrisponde a nessuno. Un id che non è un id non è un
 * profilo: è un «non trovato».
 */
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const ESPERIENZE: readonly Esperienza[] = [
  "curioso",
  "appassionato",
  "collezionista",
  "esperto",
] as const;

function esperienzaValida(valore: unknown): Esperienza {
  return ESPERIENZE.includes(valore as Esperienza) ? (valore as Esperienza) : "curioso";
}

function testo(valore: unknown): string {
  return typeof valore === "string" ? valore : "";
}

function testoOpzionale(valore: unknown): string | null {
  return typeof valore === "string" && valore !== "" ? valore : null;
}

/**
 * Errori: al chiamante arriva un messaggio in italiano, mai quello di
 * PostgreSQL. Il dettaglio resta nei log, dove serve a chi ripara.
 */
function segnalaErrore(operazione: string, errore: unknown): void {
  console.error(`[PublicProfileService] ${operazione} fallita:`, errore);
}

/**
 * Da riga della RPC a `ProfiloPubblico`.
 *
 * L'avatar passa da `riferimentoAvatarSicuro(valore, userId)` e non viene
 * copiato così com'è, benché sia lo stesso valore che il database ha appena
 * restituito. `profiles.avatar_url` è scrivibile dall'interessato tramite
 * `profiles_update_own`: è un campo di testo che una persona controlla, quindi
 * una riga può contenere un URL esterno o il percorso della cartella di
 * qualcun altro. La fondazione avatar CHIUSA verifica entrambe le cose —
 * catalogo dei preset, oppure cartella che coincide con `user_id` — e qui si
 * riusa invece di riscriverla. Ciò che non supera la verifica diventa stringa
 * vuota, che `risolviAvatarPersona` traduce nella silhouette: nessuna richiesta
 * di rete verso un indirizzo scelto da un utente, e nessuna immagine rotta.
 *
 * Le colonne sono quelle che la funzione dichiara. Non c'è una mappatura per
 * `email`, `dob`, `stato_utente` o le certificazioni perché la RPC non le
 * restituisce: non sono state omesse qui, non arrivano proprio.
 *
 * La spunta e i badge arrivano dalla STESSA riga. Non c'è una seconda chiamata
 * per le qualifiche, e non deve nascerne una: una pagina di profilo è un uuid e
 * una lettura, e una RPC di badge interrogabile su un elenco di uuid sarebbe una
 * sonda su chi è verificato. `seller_verificato` non entra qui in nessuna forma:
 * è un attributo di annuncio e dice un'altra cosa.
 */
function mappaProfiloPubblico(riga: Record<string, unknown>): ProfiloPubblico {
  const userId = testo(riga.user_id);
  return {
    userId,
    username: testo(riga.username),
    bio: testo(riga.bio),
    citta: testo(riga.citta),
    provincia: testo(riga.provincia),
    esperienza: esperienzaValida(riga.esperienza),
    avatarUrl: riferimentoAvatarSicuro(testo(riga.avatar_url), userId) ?? "",
    professionistaVerificato: riga.professionista_verificato === true,
    qualificheProfessionali: mappaQualifichePubbliche(riga.qualifiche_professionali),
  };
}

/**
 * I badge pubblici, copiati campo per campo.
 *
 * COPIA ESPLICITA E NON UN CAST. Il database restituisce già la sola allowlist —
 * `private.qualifiche_professionali_valide` non contiene nemmeno
 * `credential_reference` — ma qui si riscrive comunque l'oggetto: una colonna
 * aggiunta un giorno alla vista non arriverebbe in interfaccia per il solo fatto
 * di essere stata aggiunta. Un elemento che non è un oggetto o che non ha un
 * titolo viene scartato invece di diventare un badge vuoto.
 */
function mappaQualifichePubbliche(valore: unknown): QualificaProfessionalePubblica[] {
  if (!Array.isArray(valore)) return [];
  const badge: QualificaProfessionalePubblica[] = [];
  for (const voce of valore) {
    if (typeof voce !== "object" || voce === null) continue;
    const riga = voce as Record<string, unknown>;
    const titolo = testo(riga.titolo);
    if (titolo === "") continue;
    badge.push({
      titolo,
      enteEmittente: testo(riga.ente_emittente),
      paese: testoOpzionale(riga.paese),
      issuedOn: testoOpzionale(riga.issued_on),
      expiresOn: testoOpzionale(riga.expires_on),
    });
  }
  return badge;
}

export function creaPublicProfileService(client: SupabaseClient | null): PublicProfileService {
  return {
    async profilo(userId: string): Promise<Result<ProfiloPubblico | null>> {
      if (!client) return { ok: false, error: NOT_CONFIGURED_ERROR };
      if (!UUID.test(userId)) return { ok: true, data: null };

      const { data, error } = await client.rpc(RPC_PROFILO_PUBBLICO, { p_user_id: userId });

      if (error) {
        segnalaErrore("lettura del profilo pubblico", error);
        return { ok: false, error: LETTURA_FALLITA };
      }

      // La funzione restituisce un insieme, quindi PostgREST risponde con un
      // array. Zero righe significa «non esiste» oppure «non visibile» — la
      // persona è stata rimossa, o è chi guarda a esserlo — e i due casi
      // arrivano qui identici. È voluto: distinguerli direbbe a un visitatore
      // che quell'identificativo appartiene a qualcuno, e in che stato si
      // trova, cioè esattamente lo stato di moderazione che non è pubblico.
      const righe = Array.isArray(data) ? data : [];
      const riga = righe[0];
      if (!riga || typeof riga !== "object") return { ok: true, data: null };

      return { ok: true, data: mappaProfiloPubblico(riga as Record<string, unknown>) };
    },

    async annunciAttivi(userId: string): Promise<Result<Wine[]>> {
      if (!client) return { ok: false, error: NOT_CONFIGURED_ERROR };
      if (!UUID.test(userId)) return { ok: true, data: [] };

      // `public_listings` ha già tutto: filtra `stato = 'attivo'`, la scadenza e
      // lo stato del venditore dentro la propria definizione, ed espone
      // `seller_id`. Non serve — e non va creato — alcun oggetto di database per
      // questa sezione. Il filtro qui è una comodità di lettura, non una
      // barriera: le barriere sono nella vista.
      const { data, error } = await client
        .from("public_listings")
        .select(COLONNE_ANNUNCIO_PUBBLICO)
        .eq("seller_id", userId)
        .order("pubblicato_at", { ascending: false });

      if (error) {
        segnalaErrore("lettura degli annunci attivi", error);
        return { ok: false, error: ANNUNCI_FALLITI };
      }

      // Un elenco vuoto è una risposta normale e non un errore: il profilo
      // pubblico esiste anche per chi non ha mai messo in vendita nulla, ed è
      // il motivo per cui questa lettura è separata da `profilo()` invece di
      // essere un suo campo.
      const righe = (data ?? []) as unknown as PublicListingRow[];
      return { ok: true, data: righe.map(rigaAWine) };
    },
  };
}
