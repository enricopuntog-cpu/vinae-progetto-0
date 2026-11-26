-- WI-010: budget GLOBALE delle funzioni AI, interruttore sui guasti del fornitore e consuntivo dei consumi.
--
-- Esisteva solo il limite per utente (`rate_limit_consume`, 40/ora per la chat): nessun tetto complessivo nell'applicazione.
--
--   * CHIUSO PER DIFETTO: senza un tetto giornaliero E mensile configurati nessuna chiamata al fornitore parte.
--     Questa migration non sceglie alcun budget: i due valori restano NULL e li imposta solo il proprietario del database.
--   * L'unità è la richiesta al fornitore (il costo di ciascuna è limitato da AI_MAX_OUTPUT_TOKENS e dai limiti di
--     contesto delle function). Nessun prezzo e nessuna stima di spesa.
--   * Interruttore: dopo N guasti consecutivi del fornitore le chiamate si fermano per una pausa; scaduta la pausa
--     un solo guasto la riapre, un successo la chiude e azzera.
--   * Consuntivo: contatori per giorno (UTC) e funzione. NESSUN dato dell'utente, nessun testo.
--
-- Additiva. Nessun flag AI viene acceso.

create table private.ai_budget_settings (
  singleton boolean primary key default true check (singleton),
  richieste_giorno integer check (richieste_giorno >= 0),
  richieste_mese integer check (richieste_mese >= 0),
  guasti_per_apertura integer not null default 5 check (guasti_per_apertura between 1 and 100),
  pausa_secondi integer not null default 300 check (pausa_secondi between 30 and 86400),
  guasti_consecutivi integer not null default 0 check (guasti_consecutivi >= 0),
  aperto_fino_a timestamptz,
  updated_at timestamptz not null default now()
);
insert into private.ai_budget_settings default values;

create table private.ai_consumo_giornaliero (
  giorno date not null,
  scope text not null check (scope in ('ai:chat', 'ai:pairing', 'ai:catalogo')),
  consentite bigint not null default 0,
  rifiutate_budget bigint not null default 0,
  rifiutate_interruttore bigint not null default 0,
  guasti_fornitore bigint not null default 0,
  primary key (giorno, scope)
);

alter table private.ai_budget_settings enable row level security;
alter table private.ai_consumo_giornaliero enable row level security;
revoke all on private.ai_budget_settings, private.ai_consumo_giornaliero from public, anon, authenticated, service_role;

-- Consuma una richiesta. La riga singleton è bloccata per la sola durata della chiamata: due richieste concorrenti non
-- superano mai il tetto. Risponde con un codice e non solleva: il contatore dei rifiuti deve restare registrato.
create or replace function public.ai_budget_consuma(p_scope text)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  s private.ai_budget_settings%rowtype;
  v_oggi date := (clock_timestamp() at time zone 'utc')::date;
  v_esito text;
begin
  if p_scope is null or p_scope not in ('ai:chat', 'ai:pairing', 'ai:catalogo') then
    raise exception 'ai_budget: funzione sconosciuta' using errcode = '22023';
  end if;
  select * into strict s from private.ai_budget_settings where singleton for update;
  if s.richieste_giorno is null or s.richieste_mese is null then
    v_esito := 'non_configurato';
  elsif s.aperto_fino_a is not null and s.aperto_fino_a > clock_timestamp() then
    v_esito := 'interruttore_aperto';
  elsif (select coalesce(sum(c.consentite), 0) from private.ai_consumo_giornaliero c where c.giorno = v_oggi) >= s.richieste_giorno then
    v_esito := 'giorno_esaurito';
  elsif (select coalesce(sum(c.consentite), 0) from private.ai_consumo_giornaliero c
          where c.giorno >= date_trunc('month', v_oggi)::date and c.giorno <= v_oggi) >= s.richieste_mese then
    v_esito := 'mese_esaurito';
  else
    v_esito := 'consentito';
  end if;

  insert into private.ai_consumo_giornaliero as c (giorno, scope, consentite, rifiutate_budget, rifiutate_interruttore)
  values (v_oggi, p_scope, (v_esito = 'consentito')::int,
          (v_esito in ('non_configurato', 'giorno_esaurito', 'mese_esaurito'))::int,
          (v_esito = 'interruttore_aperto')::int)
  on conflict (giorno, scope) do update
    set consentite = c.consentite + excluded.consentite,
        rifiutate_budget = c.rifiutate_budget + excluded.rifiutate_budget,
        rifiutate_interruttore = c.rifiutate_interruttore + excluded.rifiutate_interruttore;
  return v_esito;
end;
$$;

-- Esito della chiamata al fornitore: alimenta l'interruttore.
create or replace function public.ai_budget_esito(p_scope text, p_riuscita boolean)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  s private.ai_budget_settings%rowtype;
begin
  if p_scope is null or p_scope not in ('ai:chat', 'ai:pairing', 'ai:catalogo') or p_riuscita is null then
    raise exception 'ai_budget: parametri non validi' using errcode = '22023';
  end if;
  select * into strict s from private.ai_budget_settings where singleton for update;
  if p_riuscita then
    if s.guasti_consecutivi <> 0 or s.aperto_fino_a is not null then
      update private.ai_budget_settings set guasti_consecutivi = 0, aperto_fino_a = null where singleton;
    end if;
    return;
  end if;
  if s.guasti_consecutivi + 1 >= s.guasti_per_apertura then
    -- resta a un passo dalla soglia: dopo la pausa un solo guasto riapre
    update private.ai_budget_settings
       set guasti_consecutivi = s.guasti_per_apertura - 1,
           aperto_fino_a = clock_timestamp() + make_interval(secs => s.pausa_secondi)
     where singleton;
  else
    update private.ai_budget_settings set guasti_consecutivi = s.guasti_consecutivi + 1 where singleton;
  end if;
  insert into private.ai_consumo_giornaliero as c (giorno, scope, guasti_fornitore)
  values ((clock_timestamp() at time zone 'utc')::date, p_scope, 1)
  on conflict (giorno, scope) do update set guasti_fornitore = c.guasti_fornitore + 1;
end;
$$;

-- Lettura per il monitoraggio (mai al client): configurazione, interruttore e totali di oggi e del mese.
create or replace function public.ai_budget_stato()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with oggi as (select (now() at time zone 'utc')::date as g),
  mese as (
    select c.* from private.ai_consumo_giornaliero c, oggi
     where c.giorno >= date_trunc('month', oggi.g)::date and c.giorno <= oggi.g)
  select jsonb_build_object(
    'configurato', s.richieste_giorno is not null and s.richieste_mese is not null,
    'richieste_giorno', s.richieste_giorno, 'richieste_mese', s.richieste_mese,
    'interruttore_aperto_fino_a', case when s.aperto_fino_a > now() then s.aperto_fino_a end,
    'oggi', (select jsonb_build_object('consentite', coalesce(sum(m.consentite), 0),
               'rifiutate_budget', coalesce(sum(m.rifiutate_budget), 0),
               'rifiutate_interruttore', coalesce(sum(m.rifiutate_interruttore), 0),
               'guasti_fornitore', coalesce(sum(m.guasti_fornitore), 0)) from mese m, oggi where m.giorno = oggi.g),
    'mese', (select jsonb_build_object('consentite', coalesce(sum(m.consentite), 0),
               'rifiutate_budget', coalesce(sum(m.rifiutate_budget), 0),
               'guasti_fornitore', coalesce(sum(m.guasti_fornitore), 0)) from mese m))
    from private.ai_budget_settings s where s.singleton;
$$;

revoke all on function public.ai_budget_consuma(text), public.ai_budget_esito(text, boolean), public.ai_budget_stato()
  from public, anon, authenticated;
grant execute on function public.ai_budget_consuma(text), public.ai_budget_esito(text, boolean), public.ai_budget_stato()
  to service_role;

comment on table private.ai_budget_settings is
  'WI-010. Tetto complessivo delle richieste AI (giorno e mese, UTC) e interruttore sui guasti. NULL = non configurato = nessuna chiamata. Si imposta solo da SQL del proprietario.';
comment on table private.ai_consumo_giornaliero is
  'WI-010. Consuntivo per giorno e funzione: contatori soltanto, nessun dato dell''utente.';
