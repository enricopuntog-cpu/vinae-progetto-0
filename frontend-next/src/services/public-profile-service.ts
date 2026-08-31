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
 * NIENTE DATI INVENTATI. La regola non è cambiata, è cambiato che cosa ha una
 * sorgente. La reputazione ora ce l'ha — `order_reviews`, scritta solo da chi
 * ha davvero comprato — e quindi entra; il conteggio arriva sempre, anche a
 * zero, perché «nessuna recensione» è un fatto misurato; le medie arrivano
 * `null` quando non c'è niente da mediare, perché 0/5 sarebbe un giudizio che
 * nessuno ha espresso. Non c'è ancora, e non va inventato, un livello o un
 * badge di fiducia che non sia calcolato da righe reali.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { riferimentoAvatarSicuro } from "@/lib/profilo/avatar";
import { COLONNE_ANNUNCIO_PUBBLICO, rigaAWine, type PublicListingRow } from "./listing-service";
import type { Esperienza } from "@/data/onboarding";
import type { Wine } from "@/data/wines";
import type {
  MedieRecensioni,
  ProfiloPubblico,
  PublicProfileService,
  QualificaProfessionalePubblica,
  RecensionePubblica,
  Result,
} from "./types";

/** Vedi `profile-service.ts`: il nome delle variabili d'ambiente non è una cosa
 *  da dire a chi visita un profilo pubblico. */
const NOT_CONFIGURED_ERROR = "Questo profilo non è disponibile in questo momento.";

const LETTURA_FALLITA = "Non è stato possibile leggere questo profilo.";
const ANNUNCI_FALLITI = "Non è stato possibile leggere gli annunci di questa persona.";
const RECENSIONI_FALLITE = "Non è stato possibile leggere le recensioni di questa persona.";

/**
 * Il nome della funzione SQL, in un posto solo. La firma è
 * `profilo_pubblico(p_user_id uuid)` e restituisce le sette colonne
 * dell'allowlist: nessun parametro di ricerca, nessun limite, nessun offset —
 * aggiungerne uno qui non servirebbe a niente, perché la funzione non li ha.
 */
const RPC_PROFILO_PUBBLICO = "profilo_pubblico";

/**
 * L'elenco paginato delle recensioni ricevute. È l'unica altra porta pubblica
 * del dominio: `order_reviews` non è leggibile se non si è parte dell'ordine, e
 * la proiezione pubblica sta in `private`, dove PostgREST non arriva.
 */
const RPC_RECENSIONI_PUBBLICHE = "recensioni_pubbliche_elenco";

/** Quante recensioni per pagina, se il chiamante non lo dice. */
const RECENSIONI_PER_PAGINA = 10;

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
 * PostgREST serializza `numeric` come stringa, per non perdere precisione: le
 * medie arrivano come `"4.33"`, non come `4.33`. Vanno convertite qui e non
 * stampate così come sono, altrimenti `toFixed` su una stringa esplode e un
 * confronto numerico mente.
 */
function numero(valore: unknown): number | null {
  if (typeof valore === "number") return Number.isFinite(valore) ? valore : null;
  if (typeof valore === "string" && valore.trim() !== "") {
    const n = Number(valore);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

function intero(valore: unknown): number {
  const n = numero(valore);
  return n === null ? 0 : Math.trunc(n);
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
    recensioniTotali: intero(riga.recensioni_totali),
    recensioniMedie: mappaMedie(riga.recensioni_medie),
  };
}

/**
 * Le medie, o `null`.
 *
 * `null` è la risposta del database quando non c'è nessuna recensione, e
 * **resta** `null` fin qui: non diventa un oggetto di zeri lungo la strada.
 * Diventa `null` anche quando una delle quattro medie manca o non è un numero,
 * perché mezze medie non sono un riepilogo — sono un riepilogo sbagliato.
 */
function mappaMedie(valore: unknown): MedieRecensioni | null {
  if (typeof valore !== "object" || valore === null) return null;
  const riga = valore as Record<string, unknown>;
  const voto = numero(riga.voto);
  const conformita = numero(riga.conformita);
  const imballaggio = numero(riga.imballaggio);
  const comunicazione = numero(riga.comunicazione);
  if (voto === null || conformita === null || imballaggio === null || comunicazione === null) {
    return null;
  }
  return { voto, conformita, imballaggio, comunicazione };
}

/**
 * Una recensione pubblica, copiata campo per campo.
 *
 * Stessa ragione della copia esplicita dei badge: la funzione SQL restituisce
 * già solo le colonne ammesse — non c'è `order_id` nella vista sorgente, quindi
 * non c'è niente dell'ordine da filtrare — ma una colonna aggiunta un giorno
 * alla firma non arriverebbe in interfaccia per il solo fatto di essere stata
 * aggiunta. L'avatar dell'autore passa dalla stessa verifica del profilo: è un
 * campo che l'interessato controlla.
 */
function mappaRecensionePubblica(riga: Record<string, unknown>): RecensionePubblica {
  const autoreId = testo(riga.autore_id);
  const rispostaTesto = testoOpzionale(riga.risposta_testo);
  const rispostaCreatedAt = testoOpzionale(riga.risposta_created_at);
  return {
    id: testo(riga.review_id),
    voto: intero(riga.voto),
    conformita: intero(riga.conformita),
    imballaggio: intero(riga.imballaggio),
    comunicazione: intero(riga.comunicazione),
    testo: testoOpzionale(riga.testo),
    createdAt: testo(riga.created_at),
    autore: {
      userId: autoreId,
      username: testo(riga.autore_username),
      avatarUrl: riferimentoAvatarSicuro(testo(riga.autore_avatar_url), autoreId) ?? "",
    },
    risposta:
      rispostaTesto !== null && rispostaCreatedAt !== null
        ? { testo: rispostaTesto, createdAt: rispostaCreatedAt }
        : null,
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

    async recensioni(
      userId: string,
      opzioni?: { limite?: number; offset?: number },
    ): Promise<Result<RecensionePubblica[]>> {
      if (!client) return { ok: false, error: NOT_CONFIGURED_ERROR };
      if (!UUID.test(userId)) return { ok: true, data: [] };

      // Il limite e l'offset arrivano come sono: la funzione SQL taglia il
      // limite a 50 e riporta a zero un offset negativo nel proprio corpo. Un
      // parametro che parte da qui non decide quanto lavoro fa il database, e
      // ripetere il taglio in questo file darebbe una seconda regola da tenere
      // allineata alla prima.
      const { data, error } = await client.rpc(RPC_RECENSIONI_PUBBLICHE, {
        p_user_id: userId,
        p_limit: opzioni?.limite ?? RECENSIONI_PER_PAGINA,
        p_offset: opzioni?.offset ?? 0,
      });

      if (error) {
        segnalaErrore("lettura delle recensioni pubbliche", error);
        return { ok: false, error: RECENSIONI_FALLITE };
      }

      const righe = Array.isArray(data) ? data : [];
      return {
        ok: true,
        data: righe
          .filter((r): r is Record<string, unknown> => typeof r === "object" && r !== null)
          .map(mappaRecensionePubblica),
      };
    },
  };
}
