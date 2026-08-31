import { NextResponse, type NextRequest } from "next/server";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import {
  ambienteCorrente,
  percorsoRelativoSicuro,
  risolviOriginePubblica,
} from "@/lib/auth/origine-redirect";
import {
  PARAMETRO_NEXT,
  PARAMETRO_SUPERFICIE,
  PERCORSO_REIMPOSTA_PASSWORD,
  PERCORSO_SUPERFICIE_AUTH,
  superficieAuthDa,
} from "@/lib/auth/ritorno-auth";
import { classificaErroreProvider, type CodiceErroreAuth } from "@/lib/auth/errori-auth";

/**
 * Callback OAuth (Fase 5b) e, più in generale, punto di ritorno per i flussi
 * che rimandano all'app con un `code` da scambiare per una sessione.
 *
 * Supabase reindirizza qui con `?code=...`; lo scambio avviene server-side e
 * scrive la sessione nei cookie, quindi il client browser la trova già pronta
 * al primo render (vedi lib/supabase/client.ts per il motivo dei cookie).
 *
 * In caso di errore il provider può invece rimandare `?error=...`: in quel
 * caso non c'è nessun code da scambiare e si torna sulla superficie di
 * partenza con un motivo, invece di lasciare l'utente su una pagina bianca.
 *
 * L'origine dei redirect è **decisa dal server** (`lib/auth/origine-redirect`)
 * e non dedotta dalla richiesta: i cookie di sessione sono legati all'hostname,
 * quindi rispondere su un dominio diverso da quello su cui l'utente resterà
 * significa scriverli dove nessuno andrà a rileggerli.
 *
 * ## Che cosa esce da questa route, dopo D5
 *
 * Prima, ogni ramo d'errore metteva nel `Location` il testo che aveva ricevuto:
 * `error_description` del provider, oppure `error.message` di Supabase. Quel
 * testo finiva nell'URL della barra degli indirizzi, nella cronologia, nei log
 * del bordo e infine, non tradotto, dentro la pagina. Ora esce **soltanto un
 * codice del vocabolario applicativo** (`lib/auth/errori-auth`), che non
 * trasporta nulla e che la pagina di destinazione valida prima di trasformarlo
 * in parole. Il dettaglio tecnico resta qui, in un log del server.
 */
export async function GET(request: NextRequest) {
  const { searchParams } = request.nextUrl;
  // L'host annunciato dal bordo è l'unico posto in cui, su una Deploy Preview,
  // sopravvive il dominio giusto: `request.nextUrl` porta quello immutabile del
  // deploy. Non è creduto sulla parola — vale solo se è un alias di questo sito.
  const hostAnnunciato =
    request.headers.get("x-forwarded-host") ?? request.headers.get("host") ?? undefined;
  const { origine, sorgente } = risolviOriginePubblica(
    request.nextUrl,
    ambienteCorrente(),
    hostAnnunciato,
  );
  const code = searchParams.get("code");
  // `next` permette di tornare da dove si è partiti; accettiamo solo percorsi
  // relativi per non trasformare questa route in un redirect aperto.
  const destinazione = percorsoRelativoSicuro(searchParams.get(PARAMETRO_NEXT)) ?? "/home";
  // Dove tornare quando il flusso **non** si completa: la pagina che lo ha
  // avviato, non una scelta fissa. Elenco chiuso di due percorsi nostri.
  const superficie = superficieAuthDa(searchParams.get(PARAMETRO_SUPERFICIE));

  /**
   * L'header nomina la regola che ha scelto l'origine, mai un valore di
   * ambiente. Serve perché su Netlify l'origine del server e quella della
   * richiesta coincidono: senza, dal solo `Location` non si distingue una
   * risoluzione corretta da una coincidenza fortunata.
   */
  const vaiA = (percorso: string) => {
    const risposta = NextResponse.redirect(`${origine}${percorso}`);
    risposta.headers.set("X-Vinea-Origine-Sorgente", sorgente);
    return risposta;
  };

  /**
   * Il rientro chiedeva di reimpostare la password.
   *
   * Si riconosce dalla destinazione e non da un parametro in più: è già
   * `AuthService.inviaRecuperoPassword` a scriverla come `next`, ed è già
   * passata da `percorsoRelativoSicuro`. Un secondo parametro sarebbe un
   * secondo posto in cui dire la stessa cosa, e uno dei due prima o poi mente.
   */
  const inRecupero = destinazione === PERCORSO_REIMPOSTA_PASSWORD;

  /**
   * Ritorno d'errore: codice applicativo e, se c'era, la destinazione richiesta.
   *
   * `next` sopravvive anche al fallimento di proposito: chi stava andando da
   * qualche parte e non è riuscito a entrare deve poter riprovare senza perdere
   * dove stava andando. È lo stesso valore già validato sopra, quindi non
   * riapre la porta che `percorsoRelativoSicuro` chiude.
   *
   * PERCHÉ IL RECUPERO NON TORNA SU /accedi. Un link di reimpostazione scaduto
   * — il caso normale, perché quei link valgono una volta sola e per poco —
   * rimandava l'utente sulla pagina di accesso con un errore di accesso. Ma
   * quella persona non stava accedendo: non ha la password, ed è esattamente
   * il motivo per cui aveva chiesto il link. La superficie del recupero è
   * `/reimposta-password`, che senza sessione mostra il messaggio mediato e
   * l'unica azione utile — chiederne uno nuovo. Resta un percorso nostro,
   * costante, quindi non è un redirect aperto nemmeno se `next` fosse stato
   * falsificato: sopravvive alla validazione solo perché è già uguale a una
   * costante di questo repository.
   *
   * `dettaglio` non entra mai nell'URL: viene registrato qui e basta.
   */
  const vaiAErrore = (codice: CodiceErroreAuth, dettaglio?: unknown) => {
    if (dettaglio) {
      console.error("[auth/callback]", codice, dettaglio);
    }
    const parametri = new URLSearchParams({ errore: codice });
    if (inRecupero) {
      return vaiA(`${PERCORSO_REIMPOSTA_PASSWORD}?${parametri.toString()}`);
    }
    if (destinazione !== "/home") parametri.set(PARAMETRO_NEXT, destinazione);
    return vaiA(`${PERCORSO_SUPERFICIE_AUTH[superficie]}?${parametri.toString()}`);
  };

  const erroreProvider = searchParams.get("error");
  const descrizioneProvider = searchParams.get("error_description");
  if (erroreProvider || descrizioneProvider) {
    // Annullamento e rifiuto sono due eventi diversi per l'utente, e la
    // distinzione si legge solo qui: dopo il redirect resta un codice.
    return vaiAErrore(
      classificaErroreProvider(erroreProvider, descrizioneProvider),
      descrizioneProvider ?? erroreProvider,
    );
  }

  if (!code) {
    return vaiAErrore("callback-senza-codice");
  }

  const supabase = await getSupabaseServerClient();
  if (!supabase) {
    return vaiAErrore("configurazione-assente");
  }

  const { error } = await supabase.auth.exchangeCodeForSession(code);
  if (error) {
    return vaiAErrore("scambio-non-riuscito", error.message);
  }

  return vaiA(destinazione);
}
