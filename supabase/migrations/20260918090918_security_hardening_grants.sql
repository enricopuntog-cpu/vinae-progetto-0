-- ===========================================================================
-- Security hardening post-audit del 17 settembre 2026 — least-privilege grant
-- ===========================================================================
--
-- PERCHÉ. `public.profiles` contiene PII (`dob`) e in produzione aveva, per i
-- default privileges di Supabase, un grant di tabella completo per `anon` e
-- INSERT/DELETE/TRUNCATE/REFERENCES/TRIGGER per `authenticated`. Oggi l'RLS
-- regge (una DELETE anonima risponde 204 con zero righe), ma la richiesta
-- raggiunge la tabella: una policy futura troppo larga o una RLS disattivata
-- esporrebbe o cancellerebbe l'intera anagrafica. `orders` e `reports`, senza
-- grant, rispondono già 401: è il comportamento voluto.
--
-- DEVIAZIONE DICHIARATA DAL TESTO APPROVATO. Il testo dell'audit prevedeva
-- `grant select, update on public.profiles to authenticated`. Letto in
-- produzione il 2026-09-18: `authenticated` NON ha UPDATE di tabella ma solo
-- UPDATE di colonna sulle otto colonne sotto, per scelta della Fase 9b
-- (20260810180000, righe 66-77): un UPDATE di tabella renderebbe scrivibili dal
-- client `stato_utente`, `provvedimenti`, `stato_utente_at`,
-- `stato_utente_motivo`, `id`, `created_at` e `updated_at`, e resterebbe il
-- solo trigger `profiles_stato_utente_guard` a impedire a un utente sospeso di
-- togliersi la sospensione. `revoke all` revoca anche i privilegi di colonna,
-- quindi qui il grant di colonna viene ricreato identico: SELECT di tabella e
-- UPDATE di colonna, nient'altro.

-- Least-privilege su public.profiles (contiene PII: dob).
-- anon non deve raggiungere la tabella: il profilo pubblico passa da public.profilo_pubblico().
revoke all on public.profiles from anon;
revoke all on public.profiles from authenticated;

-- authenticated legge e aggiorna solo la propria riga (RLS: auth.uid() = id).
-- L'INSERT resta escluso: la riga nasce dal trigger on_auth_user_created
-- (public.handle_new_user, SECURITY DEFINER owner postgres).
-- L'UPDATE è di colonna (Fase 9b): le colonne di moderazione restano fuori.
grant select on public.profiles to authenticated;
grant update (
  username, bio, citta, provincia, esperienza, avatar_url, dob, obiettivi
) on public.profiles to authenticated;

-- Difesa in profondità: l'RLS si applica anche al proprietario della tabella.
-- Sicuro: postgres ha rolbypassrls = true, quindi handle_new_user continua a funzionare.
alter table public.profiles force row level security;

-- Vista di configurazione: sola lettura, non scrittura.
revoke all on public.public_marketplace_config from anon, authenticated;
grant select on public.public_marketplace_config to anon, authenticated;

-- Hardening: search_path fisso (linter 0011).
alter function private.professional_qualification_reviews_append_only()
  set search_path = '';
