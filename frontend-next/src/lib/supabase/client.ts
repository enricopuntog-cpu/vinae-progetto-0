"use client";

import { createBrowserClient } from "@supabase/ssr";
import type { SupabaseClient } from "@supabase/supabase-js";

let client: SupabaseClient | null | undefined;

/**
 * Client Supabase lato browser, solo anon/publishable key (mai service_role).
 *
 * Usa `createBrowserClient` di @supabase/ssr e non `createClient` di
 * supabase-js: la differenza è dove vive la sessione. `createBrowserClient`
 * la salva nei cookie invece che in localStorage, ed è ciò che permette alla
 * route handler server-side /auth/callback di leggere il code verifier PKCE
 * e completare lo scambio del code per una sessione. Con la sessione in
 * localStorage il server non vedrebbe nulla e il login OAuth non potrebbe
 * concludersi lato server.
 *
 * Conseguenza sui flussi email/password e magic link introdotti in Fase 5a:
 * continuano a funzionare identici, ma la loro sessione è ora su cookie.
 *
 * Ritorna null — invece di lanciare — quando NEXT_PUBLIC_SUPABASE_URL /
 * NEXT_PUBLIC_SUPABASE_ANON_KEY non sono configurate, così build, typecheck
 * e le pagine che non richiedono autenticazione restano funzionanti.
 */
export function getSupabaseClient(): SupabaseClient | null {
  if (client !== undefined) return client;

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!url || !anonKey) {
    client = null;
    return client;
  }

  client = createBrowserClient(url, anonKey);
  return client;
}
