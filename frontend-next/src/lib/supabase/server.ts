import { createServerClient } from "@supabase/ssr";
import type { SupabaseClient } from "@supabase/supabase-js";
import { cookies } from "next/headers";

/**
 * Client Supabase per contesti server (route handler, Server Component).
 * Legge e scrive la sessione nei cookie della richiesta corrente, così il
 * code exchange PKCE fatto in /auth/callback condivide lo stesso storage del
 * client browser (vedi il commento in lib/supabase/client.ts).
 *
 * Va creato uno per richiesta: non riusare né memoizzare fra richieste
 * diverse, altrimenti la sessione di un utente finirebbe nel contesto di un
 * altro.
 *
 * Come per il client browser, ritorna null quando le variabili d'ambiente non
 * sono configurate, invece di lanciare: la build e le pagine senza
 * autenticazione non devono rompersi.
 */
export async function getSupabaseServerClient(): Promise<SupabaseClient | null> {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !anonKey) return null;

  const cookieStore = await cookies();

  return createServerClient(url, anonKey, {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        // In una route handler la scrittura è consentita. Il try/catch copre
        // il caso in cui questo client venga usato da un Server Component,
        // dove Next.js non permette di modificare i cookie durante il render:
        // in quel contesto il refresh del token viene comunque scritto alla
        // richiesta successiva che passa da un contesto scrivibile.
        try {
          for (const { name, value, options } of cookiesToSet) {
            cookieStore.set(name, value, options);
          }
        } catch {
          // contesto in sola lettura: ignorato intenzionalmente
        }
      },
    },
  });
}
