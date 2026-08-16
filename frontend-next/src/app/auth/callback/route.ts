import { NextResponse, type NextRequest } from "next/server";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import {
  ambienteCorrente,
  percorsoRelativoSicuro,
  risolviOriginePubblica,
} from "@/lib/auth/origine-redirect";

/**
 * Callback OAuth (Fase 5b) e, più in generale, punto di ritorno per i flussi
 * che rimandano all'app con un `code` da scambiare per una sessione.
 *
 * Supabase reindirizza qui con `?code=...`; lo scambio avviene server-side e
 * scrive la sessione nei cookie, quindi il client browser la trova già pronta
 * al primo render (vedi lib/supabase/client.ts per il motivo dei cookie).
 *
 * In caso di errore il provider può invece rimandare `?error=...`: in quel
 * caso non c'è nessun code da scambiare e si torna su /accedi con il motivo,
 * invece di lasciare l'utente su una pagina bianca.
 *
 * L'origine dei redirect è **decisa dal server** (`lib/auth/origine-redirect`)
 * e non dedotta dalla richiesta: i cookie di sessione sono legati all'hostname,
 * quindi rispondere su un dominio diverso da quello su cui l'utente resterà
 * significa scriverli dove nessuno andrà a rileggerli.
 */
export async function GET(request: NextRequest) {
  const { searchParams } = request.nextUrl;
  const ambiente = ambienteCorrente();
  const { origine, sorgente } = risolviOriginePubblica(request.nextUrl, ambiente);
  const code = searchParams.get("code");
  const errorDescription = searchParams.get("error_description") ?? searchParams.get("error");
  // `next` permette di tornare da dove si è partiti; accettiamo solo percorsi
  // relativi per non trasformare questa route in un redirect aperto.
  const destinazione = percorsoRelativoSicuro(searchParams.get("next")) ?? "/home";

  /**
   * L'header nomina la regola che ha scelto l'origine, mai un valore di
   * ambiente. Serve perché su Netlify l'origine del server e quella della
   * richiesta coincidono: senza, dal solo `Location` non si distingue una
   * risoluzione corretta da una coincidenza fortunata.
   */
  const vaiA = (percorso: string) => {
    const risposta = NextResponse.redirect(`${origine}${percorso}`);
    risposta.headers.set("X-Vinea-Origine-Sorgente", sorgente);
    // TEMPORANEO, da togliere prima del merge: dice quali delle quattro
    // variabili esistono a runtime, non che cosa contengono. Serve a misurare
    // in un solo deploy ciò che la prima Deploy Preview della #45 ha mostrato
    // solo di riflesso — che `CONTEXT` a runtime non c'è.
    risposta.headers.set(
      "X-Vinea-Origine-Presenti",
      Object.entries(ambiente)
        .filter(([, valore]) => Boolean(valore))
        .map(([nome]) => nome)
        .join(",") || "nessuna",
    );
    return risposta;
  };

  if (errorDescription) {
    return vaiA(`/accedi?errore=${encodeURIComponent(errorDescription)}`);
  }

  if (!code) {
    return vaiA(`/accedi?errore=${encodeURIComponent("Callback senza codice di autorizzazione.")}`);
  }

  const supabase = await getSupabaseServerClient();
  if (!supabase) {
    return vaiA(
      `/accedi?errore=${encodeURIComponent("Supabase non configurato su questo ambiente.")}`,
    );
  }

  const { error } = await supabase.auth.exchangeCodeForSession(code);
  if (error) {
    return vaiA(`/accedi?errore=${encodeURIComponent(error.message)}`);
  }

  return vaiA(destinazione);
}
