/**
 * «Segui una Cantina»: il lato client delle quattro porte della fondazione
 * `20260926091000`.
 *
 * PERCHÉ UN DOMINIO A SÉ. Non sta in `PublicProfileService` — che è in sola
 * lettura e serve una pagina resa dal server per chiunque, anche anonimo — né in
 * `ProfileService`, che è il proprio profilo, né in `CellarService`, che è la
 * Cantina privata del proprietario. Questo dominio è la terza cosa: una
 * relazione fra chi guarda e una Cantina altrui. Le sue tre scritture esistono
 * solo per `authenticated`, e mescolarle con letture pubbliche renderebbe
 * ambiguo quale parte di quei servizi funziona senza sessione.
 *
 * SI SEGUE LA CANTINA, NON L'UTENTE. Non è un `user-follow` generico e non deve
 * diventarlo: il nome delle RPC, il nome dei tipi e il nome di questo file
 * dicono la stessa cosa, perché è una decisione di prodotto e non un dettaglio
 * di implementazione. Un `FollowService` generico inviterebbe, il giorno dopo, a
 * seguire un venditore o un Club dalle stesse chiamate.
 *
 * NESSUN GRAFO PUBBLICO. Non esiste qui — e non esiste nel database — una
 * chiamata che risponda «chi segue questa Cantina» o «quanti la seguono»:
 * `private.cellar_follows` non è raggiungibile da PostgREST, `cantine_seguite_page`
 * non accetta alcun identificativo di utente e risponde solo per `auth.uid()`.
 * Il follower non è mai un parametro di queste funzioni, quindi non è mai un
 * parametro di questi metodi: chi segue lo decide il token, non il chiamante.
 *
 * Come `creaPublicProfileService`, prende il client Supabase come parametro
 * invece di importarlo da `@/lib/supabase/client`, che è un modulo browser. Qui
 * oggi chiama sempre il browser — le tre porte richiedono una sessione, e una
 * sessione verificata sul server non la si riusa in un componente client — ma
 * cablare il client dentro il modulo lo renderebbe non testabile e non
 * riusabile dal server il giorno in cui servisse.
 */

import { riferimentoAvatarSicuro } from "@/lib/profilo/avatar";
import type { SupabaseClient } from "@supabase/supabase-js";
import type {
  CantinaSeguita,
  CellarFollowService,
  CursoreCantinaSeguita,
  Result,
} from "./types";

/**
 * I nomi delle quattro funzioni SQL, in un posto solo.
 *
 * Nessuna di esse accetta un `follower_id`: il follower è `auth.uid()` dentro il
 * corpo `security definer`. Aggiungere qui un parametro del genere non
 * funzionerebbe — la firma non lo ha — ed è il motivo per cui questo servizio
 * non può, nemmeno per errore, agire a nome di qualcun altro.
 */
const RPC_STATO = "cantina_seguita_stato";
const RPC_SEGUI = "cantina_segui";
const RPC_SMETTI = "cantina_smetti_di_seguire";
const RPC_ELENCO = "cantine_seguite_page";

/** Vedi `public-profile-service.ts`: i nomi delle variabili d'ambiente non si dicono. */
const NON_CONFIGURATO = "Questa funzione non è disponibile in questo momento.";

const STATO_FALLITO = "Non è stato possibile verificare se segui questa Cantina.";
const SEGUI_FALLITO = "Non è stato possibile seguire questa Cantina.";
const SMETTI_FALLITO = "Non è stato possibile smettere di seguire questa Cantina.";
const ELENCO_FALLITO = "Non è stato possibile leggere le Cantine che segui.";
const CANTINA_NON_INDICATA = "Cantina non indicata.";

/**
 * Quante Cantine mostra una pagina di «Le mie Cantine».
 *
 * NON è il limite che viene chiesto al database: vedi `RICHIESTA_PER_PAGINA`.
 */
export const CANTINE_SEGUITE_PER_PAGINA = 24;

/**
 * Quante se ne chiedono per sapere se esiste una pagina dopo.
 *
 * Una in più di quelle che si mostrano, e non un `count(*)` separato. Il motivo è
 * che un conteggio è una seconda lettura che può divergere dalla prima — una
 * Cantina che smette di essere pubblica fra le due chiamate produce un «mostra
 * altre» che non porta a niente — mentre la riga in eccesso viene dalla stessa
 * query e dallo stesso istante. La funzione SQL ammette fino a 50, quindi 25 sta
 * largamente dentro il suo tetto.
 *
 * Le due costanti stanno **insieme** e in questo file solo, perché una regola
 * scritta in due punti è una regola che prima o poi divergerà: il giorno in cui
 * la pagina mostrasse 12 Cantine, qui si chiederebbero 13 senza toccare altro.
 */
export const RICHIESTA_PER_PAGINA = CANTINE_SEGUITE_PER_PAGINA + 1;

/**
 * Un identificativo malformato non arriva al database.
 *
 * Stessa forma e stessa ragione di `public-profile-service.ts`: la barriera è la
 * funzione SQL, non questa riga. Qui serve a dare la risposta giusta invece di
 * un guasto — un `uuid` che non è un `uuid` produce `22P02`, che verrebbe
 * mostrato come «non è stato possibile» dove in realtà non c'è nulla che non
 * funzioni.
 */
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function testo(valore: unknown): string {
  return typeof valore === "string" ? valore : "";
}

function intero(valore: unknown): number {
  if (typeof valore === "number") return Number.isFinite(valore) ? Math.trunc(valore) : 0;
  if (typeof valore === "string" && valore.trim() !== "") {
    const n = Number(valore);
    return Number.isFinite(n) ? Math.trunc(n) : 0;
  }
  return 0;
}

/** Il dettaglio tecnico resta nei log; al chiamante arriva una frase in italiano. */
function segnalaErrore(operazione: string, errore: unknown): void {
  console.error(`[CellarFollowService] ${operazione} fallita:`, errore);
}

/**
 * Da riga della RPC a `CantinaSeguita`, campo per campo.
 *
 * ALLOWLIST E NON UN CAST. La funzione SQL restituisce già sette colonne e nulla
 * di privato: non c'è un `follower_id` nella sua firma, non c'è uno stato di
 * moderazione, non c'è un valore. Ma la copia esplicita resta la seconda
 * barriera — una colonna aggiunta un giorno alla firma non arriva in interfaccia
 * per il solo fatto di essere stata aggiunta — ed è la stessa disciplina già
 * applicata alle bottiglie della Cantina pubblica e ai badge del profilo.
 *
 * `avatar_url` ripassa da `riferimentoAvatarSicuro`: è un campo che l'interessato
 * scrive da sé tramite `profiles_update_own`, quindi una riga può contenere un
 * URL esterno o la cartella di qualcun altro. Ciò che non supera la verifica
 * diventa stringa vuota, e `AvatarPersona` disegna la silhouette.
 *
 * Torna `null` quando manca `owner_id`, e non una scheda con un buco al posto
 * del collegamento: l'identificativo è l'unica cosa di cui questa scheda non può
 * fare a meno, perché è tutto il suo indirizzo.
 */
function mappaCantinaSeguita(riga: Record<string, unknown>): CantinaSeguita | null {
  const ownerId = testo(riga.owner_id);
  if (ownerId === "") return null;

  return {
    ownerId,
    username: testo(riga.username),
    avatarUrl: riferimentoAvatarSicuro(testo(riga.avatar_url), ownerId) ?? "",
    citta: testo(riga.citta),
    provincia: testo(riga.provincia),
    followedAt: testo(riga.followed_at),
    // `0` è una risposta legittima e non un dato mancante: una Cantina pubblica
    // ancora vuota resta seguibile, ed è proprio il caso in cui si segue per
    // aspettare la prima pubblicazione. Non diventa quindi `null` né un motivo
    // per scartare la riga.
    bottigliePubbliche: intero(riga.bottiglie_pubbliche),
  };
}

export function creaCellarFollowService(client: SupabaseClient | null): CellarFollowService {
  return {
    async stato(ownerId: string): Promise<Result<boolean>> {
      if (!client) return { ok: false, error: NON_CONFIGURATO };
      // Fail closed: un identificativo che non è un identificativo non è una
      // Cantina che si segue, ed è la risposta giusta senza disturbare il
      // database. NON è `{ ok: false }`, perché non c'è nessun guasto da
      // segnalare, e non è un errore che bloccherebbe la pagina.
      if (!UUID.test(ownerId)) return { ok: true, data: false };

      const { data, error } = await client.rpc(RPC_STATO, { p_owner_id: ownerId });

      if (error) {
        segnalaErrore("lettura dello stato del follow", error);
        return { ok: false, error: STATO_FALLITO };
      }

      // La firma promette un booleano. Un payload diverso non è «non la seguo»:
      // è una risposta illeggibile, quindi resta un errore e il comando mostra lo
      // stato neutro «Segui non disponibile» invece di inventare `false`.
      if (typeof data !== "boolean") {
        segnalaErrore("lettura dello stato del follow", new Error("Risposta non booleana."));
        return { ok: false, error: STATO_FALLITO };
      }
      return { ok: true, data };
    },

    async segui(ownerId: string): Promise<Result<boolean>> {
      if (!client) return { ok: false, error: NON_CONFIGURATO };
      // Su una scrittura il fail closed è un errore, non un esito: rispondere
      // `{ ok: true, data: false }` racconterebbe che la chiamata è andata e non
      // ha seguito nulla, cioè esattamente l'ambiguità che questo ramo evita.
      if (!UUID.test(ownerId)) return { ok: false, error: CANTINA_NON_INDICATA };

      const { data, error } = await client.rpc(RPC_SEGUI, { p_owner_id: ownerId });

      if (error) {
        // Qui finiscono anche i rifiuti previsti dalla funzione: `42501` per una
        // Cantina non raggiungibile o un profilo rimosso, `P0001` per la propria
        // Cantina. Al chiamante arriva una frase sola, perché distinguerli in
        // interfaccia direbbe a un visitatore in che stato si trova quel
        // profilo — ed è lo stesso silenzio deliberato di `profilo_pubblico`.
        segnalaErrore("follow della Cantina", error);
        return { ok: false, error: SEGUI_FALLITO };
      }

      // Lo stato finale lo dichiara il database: questa porta può dichiarare solo
      // `true`, anche quando la riga esisteva già. Qualunque altro payload non è
      // un successo alternativo, ma una violazione del contratto.
      if (data !== true) {
        segnalaErrore("follow della Cantina", new Error("Risposta finale inattesa."));
        return { ok: false, error: SEGUI_FALLITO };
      }
      return { ok: true, data: true };
    },

    async smetti(ownerId: string): Promise<Result<boolean>> {
      if (!client) return { ok: false, error: NON_CONFIGURATO };
      if (!UUID.test(ownerId)) return { ok: false, error: CANTINA_NON_INDICATA };

      const { data, error } = await client.rpc(RPC_SMETTI, { p_owner_id: ownerId });

      if (error) {
        segnalaErrore("unfollow della Cantina", error);
        return { ok: false, error: SMETTI_FALLITO };
      }

      // La funzione restituisce lo **stato finale** e non «ho cancellato una
      // riga»: è `false` sia la prima volta sia la seconda. Un valore diverso non
      // dimostra che la relazione sia stata rimossa, quindi conserva lo stato
      // precedente attraverso il ramo d'errore del componente.
      if (data !== false) {
        segnalaErrore("unfollow della Cantina", new Error("Risposta finale inattesa."));
        return { ok: false, error: SMETTI_FALLITO };
      }
      return { ok: true, data: false };
    },

    async pagina(opzioni?: {
      cursore?: CursoreCantinaSeguita | null;
      limite?: number;
    }): Promise<Result<CantinaSeguita[]>> {
      if (!client) return { ok: false, error: NON_CONFIGURATO };

      // Il cursore è **un oggetto solo** e non due parametri sciolti, ed è la
      // ragione per cui non esiste un ramo che ne manda metà: la funzione SQL
      // rifiuta con `22023` un istante senza il suo identificativo, e un tipo
      // che non permette di scrivere quel caso è più solido di un controllo che
      // lo intercetta. Prima pagina: entrambi `null`, come vuole la firma.
      const cursore = opzioni?.cursore ?? null;

      const { data, error } = await client.rpc(RPC_ELENCO, {
        p_before_created_at: cursore?.followedAt ?? null,
        p_before_owner_id: cursore?.ownerId ?? null,
        // Il limite parte da qui come preferenza; il tetto di 50 lo applica la
        // funzione. Ripeterlo qui darebbe due regole da tenere allineate, e
        // quella che conta è comunque l'altra.
        p_limit: opzioni?.limite ?? RICHIESTA_PER_PAGINA,
      });

      if (error) {
        segnalaErrore("lettura delle Cantine seguite", error);
        return { ok: false, error: ELENCO_FALLITO };
      }

      // Un elenco vuoto è una risposta normale: chi non segue nessuno esiste, e
      // non è un guasto. Le righe che non si riconoscono cadono qui invece di
      // diventare schede rotte.
      const righe = Array.isArray(data) ? data : [];
      return {
        ok: true,
        data: righe
          .filter((r): r is Record<string, unknown> => typeof r === "object" && r !== null)
          .map(mappaCantinaSeguita)
          .filter((c): c is CantinaSeguita => c !== null),
      };
    },
  };
}
