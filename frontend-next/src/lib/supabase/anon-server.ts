import { createClient, type SupabaseClient } from "@supabase/supabase-js";

/**
 * Client Supabase server **senza sessione**: usa soltanto la chiave anon e non
 * legge né scrive cookie. È riservato alle porte della Market Validation, dove
 * l'unica identità del tester è codice Vxxx + capability anonima verificati
 * dalle RPC dedicate.
 *
 * Con `getSupabaseServerClient()` un cookie di sessione Vinea presente nel
 * browser (scaduto, revocato o di un altro ambiente) veniva inoltrato a
 * PostgREST: la richiesta falliva con PGRST301 prima ancora di arrivare alla
 * RPC e il tester restava senza codice. Qui nessun JWT utente parte mai.
 *
 * Nuovo client per ogni chiamata: nessuno stato condiviso fra richieste.
 * Ritorna null se le variabili non sono configurate, come gli altri client.
 */
export function getSupabaseAnonServerClient(): SupabaseClient | null {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !anonKey) return null;

  return createClient(url, anonKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });
}
