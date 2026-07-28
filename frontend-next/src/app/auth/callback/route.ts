import { NextResponse, type NextRequest } from "next/server";
import { getSupabaseServerClient } from "@/lib/supabase/server";

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
 */
export async function GET(request: NextRequest) {
  const { searchParams, origin } = request.nextUrl;
  const code = searchParams.get("code");
  const errorDescription = searchParams.get("error_description") ?? searchParams.get("error");
  // `next` permette di tornare da dove si è partiti; accettiamo solo percorsi
  // relativi per non trasformare questa route in un redirect aperto.
  const nextParam = searchParams.get("next");
  const destinazione = nextParam && nextParam.startsWith("/") ? nextParam : "/home";

  if (errorDescription) {
    return NextResponse.redirect(
      `${origin}/accedi?errore=${encodeURIComponent(errorDescription)}`,
    );
  }

  if (!code) {
    return NextResponse.redirect(
      `${origin}/accedi?errore=${encodeURIComponent("Callback senza codice di autorizzazione.")}`,
    );
  }

  const supabase = await getSupabaseServerClient();
  if (!supabase) {
    return NextResponse.redirect(
      `${origin}/accedi?errore=${encodeURIComponent("Supabase non configurato su questo ambiente.")}`,
    );
  }

  const { error } = await supabase.auth.exchangeCodeForSession(code);
  if (error) {
    return NextResponse.redirect(`${origin}/accedi?errore=${encodeURIComponent(error.message)}`);
  }

  return NextResponse.redirect(`${origin}${destinazione}`);
}
