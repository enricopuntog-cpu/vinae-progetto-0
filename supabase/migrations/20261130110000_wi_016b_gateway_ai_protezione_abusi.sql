-- WI-016 B — contratto comune del gateway AI, protezione dagli abusi e quarantena delle proposte sospette.
--
-- Nulla viene acceso e nessun valore commerciale è scelto: AI_ENABLED, tetti, tariffe e modelli restano del founder.
--
--   * Il gateway passa da UNA porta di ingresso per identità: sospensioni, richiesta ripetuta, concorrenza per utente
--     e globale, quota ridotta per gli account nuovi, blocco temporaneo dopo anomalie ripetute. Il soggetto è un
--     identificativo pseudonimo e le righe durano al massimo 48 ore.
--   * Tentativi e modello di riserva stanno in una tabella del proprietario: di base UN tentativo e NESSUNA riserva.
--     Ogni tentativo prenota il proprio budget (WI-010/WI-015): una riserva non moltiplica la spesa oltre i tetti.
--   * Il gateway distingue guasto del fornitore, errore dell'applicazione, errore dell'utente e disconnessione.
--   * Catalog poisoning: una proposta con contenuto o ritmo sospetto va in QUARANTENA; resta visibile al curatore,
--     non entra nella coda automatica e non può diventare un vino canonico finché una persona non la rilascia.

-- =============================================================================================
-- 1. Configurazione per funzione
-- =============================================================================================
create table private.ai_funzioni (
  scope text primary key check (scope in ('ai:chat', 'ai:pairing', 'ai:catalogo')),
  -- tentativi TOTALI per richiesta (1 = nessun ritentativo); ognuno prenota il proprio budget
  max_tentativi smallint not null default 1 check (max_tentativi between 1 and 2),
  -- riserva autorizzata dal proprietario: NULL = nessun fallback
  modello_riserva text check (modello_riserva is null or modello_riserva ~ '^[A-Za-z0-9._:/-]{1,80}$'),
  max_input_caratteri integer not null check (max_input_caratteri between 100 and 60000),
  concorrenza_utente smallint not null default 2 check (concorrenza_utente between 1 and 10),
  concorrenza_globale smallint not null default 20 check (concorrenza_globale between 1 and 500),
  -- quota oraria ridotta per gli account più giovani di `eta_account_nuovo_giorni`
  quota_account_nuovo smallint not null check (quota_account_nuovo between 0 and 1000),
  eta_account_nuovo_giorni smallint not null default 3 check (eta_account_nuovo_giorni between 0 and 90),
  -- la richiesta identica ANCORA IN CORSO è sempre rifiutata; questa finestra estende il rifiuto dopo una risposta
  -- riuscita (di base 0: la sceglie il proprietario). Una richiesta fallita non blocca il nuovo tentativo.
  finestra_replay_secondi smallint not null default 0 check (finestra_replay_secondi between 0 and 600),
  -- anomalie dello stesso soggetto nelle 24 ore oltre le quali la funzione si sospende per quel soggetto
  soglia_anomalie smallint not null default 10 check (soglia_anomalie between 1 and 1000),
  updated_at timestamptz not null default now()
);
-- I valori restano entro i limiti orari già decisi (40, 15, 10): la quota dei nuovi account li riduce.
insert into private.ai_funzioni (scope, max_input_caratteri, quota_account_nuovo) values
  ('ai:chat', 20000, 15),
  ('ai:pairing', 16000, 6),
  ('ai:catalogo', 4000, 4);

create table private.ai_porte (
  id uuid primary key default gen_random_uuid(),
  scope text not null references private.ai_funzioni(scope),
  soggetto text not null check (length(soggetto) = 32),
  impronta text not null check (length(impronta) between 8 and 128),
  aperta_il timestamptz not null default clock_timestamp(),
  scade_il timestamptz not null,
  chiusa_il timestamptz
);
create index ai_porte_soggetto_idx on private.ai_porte (soggetto, scope, aperta_il desc);
create index ai_porte_aperte_idx on private.ai_porte (scade_il) where chiusa_il is null;
create index ai_porte_pulizia_idx on private.ai_porte (aperta_il);

create table private.ai_segnalazioni (
  id bigint generated always as identity primary key,
  scope text not null references private.ai_funzioni(scope),
  soggetto text not null check (length(soggetto) = 32),
  tipo text not null check (tipo in ('dati_sensibili', 'istruzioni_sospette', 'output_scartato', 'richiesta_ripetuta',
                                     'input_eccessivo')),
  registrata_il timestamptz not null default clock_timestamp()
);
create index ai_segnalazioni_soggetto_idx on private.ai_segnalazioni (soggetto, registrata_il desc);
create index ai_segnalazioni_recenti_idx on private.ai_segnalazioni (registrata_il);

alter table private.ai_funzioni enable row level security;
alter table private.ai_porte enable row level security;
alter table private.ai_segnalazioni enable row level security;
revoke all on private.ai_funzioni, private.ai_porte, private.ai_segnalazioni from public, anon, authenticated, service_role;

-- Pseudonimo stabile del soggetto: non è l'identificativo dell'account e non esce dal database.
create or replace function private.ai_soggetto(p_user uuid)
returns text language sql immutable set search_path = '' as $$
  select md5('ai-soggetto:' || p_user::text);
$$;

-- Ingresso per identità. Va chiamata dopo l'autenticazione e PRIMA della prenotazione del budget.
create or replace function public.ai_porta_apri(p_user uuid, p_scope text, p_impronta text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  f private.ai_funzioni%rowtype;
  v_soggetto text;
  v_creato timestamptz;
  v_id uuid;
  v_esito text;
begin
  if p_user is null or p_impronta is null or length(p_impronta) not between 8 and 128 then
    raise exception 'ai_porta: parametri non validi' using errcode = '22023';
  end if;
  select * into f from private.ai_funzioni x where x.scope = p_scope;
  if not found then
    raise exception 'ai_porta: funzione sconosciuta' using errcode = '22023';
  end if;
  v_soggetto := private.ai_soggetto(p_user);
  -- un solo ingresso alla volta: la concorrenza globale è un conteggio, non una speranza
  perform pg_advisory_xact_lock(hashtextextended('private.ai_porta', 0));
  delete from private.ai_porte p where p.aperta_il < clock_timestamp() - interval '48 hours';
  delete from private.ai_segnalazioni s where s.registrata_il < clock_timestamp() - interval '48 hours';

  select u.created_at into v_creato from auth.users u where u.id = p_user;
  if brain.is_suspended('ai', p_scope) then
    v_esito := 'sospesa';
  elsif (select count(*) from private.ai_segnalazioni s
          where s.soggetto = v_soggetto and s.registrata_il > clock_timestamp() - interval '24 hours') >= f.soglia_anomalie then
    v_esito := 'blocco_abusi';
  elsif exists (select 1 from private.ai_porte p
          where p.soggetto = v_soggetto and p.scope = p_scope and p.impronta = p_impronta
            and ((p.chiusa_il is null and p.scade_il > clock_timestamp())
                 or p.aperta_il > clock_timestamp() - make_interval(secs => f.finestra_replay_secondi))) then
    v_esito := 'richiesta_ripetuta';
  elsif (select count(*) from private.ai_porte p
          where p.soggetto = v_soggetto and p.chiusa_il is null and p.scade_il > clock_timestamp()) >= f.concorrenza_utente then
    v_esito := 'concorrenza_utente';
  elsif (select count(*) from private.ai_porte p
          where p.scope = p_scope and p.chiusa_il is null and p.scade_il > clock_timestamp()) >= f.concorrenza_globale then
    v_esito := 'concorrenza_globale';
  elsif v_creato is not null and v_creato > clock_timestamp() - make_interval(days => f.eta_account_nuovo_giorni)
        and (select count(*) from private.ai_porte p
              where p.soggetto = v_soggetto and p.scope = p_scope and p.aperta_il > clock_timestamp() - interval '1 hour')
            >= f.quota_account_nuovo then
    v_esito := 'quota_account_nuovo';
  else
    v_esito := 'consentito';
  end if;

  if v_esito <> 'consentito' then
    if v_esito = 'richiesta_ripetuta' then
      insert into private.ai_segnalazioni (scope, soggetto, tipo) values (p_scope, v_soggetto, 'richiesta_ripetuta');
    end if;
    return jsonb_build_object('esito', v_esito);
  end if;
  -- la scadenza libera il posto anche se la function muore prima di chiuderlo
  insert into private.ai_porte (scope, soggetto, impronta, scade_il)
  values (p_scope, v_soggetto, p_impronta, clock_timestamp() + interval '3 minutes')
  returning id into v_id;
  return jsonb_build_object('esito', 'consentito', 'porta_id', v_id, 'max_tentativi', f.max_tentativi,
    'modello_riserva', f.modello_riserva, 'max_input_caratteri', f.max_input_caratteri);
end;
$$;

create or replace function public.ai_porta_chiudi(p_porta uuid, p_riuscita boolean default true)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
begin
  -- se non è riuscita, l'impronta si annulla: ripetere dopo un errore non è un replay
  update private.ai_porte p
     set chiusa_il = clock_timestamp(),
         impronta = case when coalesce(p_riuscita, true) then p.impronta else 'fallita:' || p.id::text end
   where p.id = p_porta and p.chiusa_il is null;
  return found;
end;
$$;

-- Segnale di sicurezza senza contenuto: solo il tipo. Il testo della richiesta non viene mai conservato.
create or replace function public.ai_segnala(p_user uuid, p_scope text, p_tipo text)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  if p_user is null then
    raise exception 'ai_porta: parametri non validi' using errcode = '22023';
  end if;
  insert into private.ai_segnalazioni (scope, soggetto, tipo) values (p_scope, private.ai_soggetto(p_user), p_tipo);
end;
$$;

revoke all on function private.ai_soggetto(uuid), public.ai_porta_apri(uuid, text, text), public.ai_porta_chiudi(uuid, boolean),
  public.ai_segnala(uuid, text, text) from public, anon, authenticated, service_role;
grant execute on function public.ai_porta_apri(uuid, text, text), public.ai_porta_chiudi(uuid, boolean),
  public.ai_segnala(uuid, text, text) to service_role;

-- =============================================================================================
-- 2. Prenotazione: la sospensione precede ogni consumo; l'errore dell'applicazione è un esito a sé
-- =============================================================================================
alter table private.ai_chiamate drop constraint ai_chiamate_esito_check;
alter table private.ai_chiamate add constraint ai_chiamate_esito_check check (esito in
  ('ok', 'guasto_fornitore', 'errore_richiesta', 'interrotta_client', 'formato_non_valido', 'errore_applicativo'));

create or replace function public.ai_budget_prenota(p_scope text, p_provider text, p_modello text,
  p_token_input integer, p_token_output_max integer)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  s private.ai_budget_settings%rowtype;
  t private.ai_tariffe%rowtype;
  v_cost numeric(14, 6);
  v_day timestamptz := date_trunc('day', clock_timestamp() at time zone 'utc') at time zone 'utc';
  v_month timestamptz := date_trunc('month', clock_timestamp() at time zone 'utc') at time zone 'utc';
  v_refusal text;
  v_outcome text;
  v_id uuid;
begin
  if p_provider is null or p_modello is null or p_token_input is null or p_token_input < 0
     or p_token_output_max is null or p_token_output_max < 0 or p_token_input > 2000000 or p_token_output_max > 200000 then
    raise exception 'ai_budget: parametri non validi' using errcode = '22023';
  end if;
  select * into strict s from private.ai_budget_settings where singleton for update;
  if brain.is_suspended('ai', p_scope) then
    return jsonb_build_object('esito', 'sospesa');
  end if;
  select * into t from private.ai_tariffe x
   where x.provider = p_provider and x.modello = p_modello and x.valida_dal <= clock_timestamp()
   order by x.valida_dal desc, x.id desc limit 1;
  if t.id is not null then
    v_cost := ceil((p_token_input * t.input_per_milione + p_token_output_max * t.output_per_milione)) / 1000000;
  end if;
  if s.richieste_giorno is not null and s.richieste_mese is not null
     and (s.spesa_giorno_usd is not null or s.spesa_mese_usd is not null) then
    if t.id is null then
      v_refusal := 'tariffa_mancante';
    elsif s.spesa_giorno_usd is not null and v_cost + (select coalesce(sum(coalesce(k.costo_effettivo, k.costo_stimato, k.costo_riservato)), 0)
            from private.ai_chiamate k where k.richiesta_il >= v_day) > s.spesa_giorno_usd then
      v_refusal := 'spesa_giorno_esaurita';
    elsif s.spesa_mese_usd is not null and v_cost + (select coalesce(sum(coalesce(k.costo_effettivo, k.costo_stimato, k.costo_riservato)), 0)
            from private.ai_chiamate k where k.richiesta_il >= v_month) > s.spesa_mese_usd then
      v_refusal := 'spesa_mese_esaurita';
    end if;
  end if;
  if v_refusal is not null then
    insert into private.ai_consumo_giornaliero as c (giorno, scope, rifiutate_budget)
    values ((clock_timestamp() at time zone 'utc')::date, p_scope, 1)
    on conflict (giorno, scope) do update set rifiutate_budget = c.rifiutate_budget + 1;
    return jsonb_build_object('esito', v_refusal);
  end if;
  v_outcome := public.ai_budget_consuma(p_scope);
  if v_outcome <> 'consentito' then
    return jsonb_build_object('esito', v_outcome);
  end if;
  insert into private.ai_chiamate (scope, provider, modello, token_input_stimati, token_output_massimi, tariffa_id, costo_riservato)
  values (p_scope, p_provider, p_modello, p_token_input, p_token_output_max, t.id, v_cost)
  returning id into v_id;
  return jsonb_build_object('esito', 'consentito', 'richiesta_id', v_id);
end;
$$;

create or replace function public.ai_budget_consuntivo(p_richiesta uuid, p_esito text, p_token_input integer default null,
  p_token_output integer default null)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
begin
  if p_richiesta is null or p_esito is null
     or p_esito not in ('ok', 'guasto_fornitore', 'errore_richiesta', 'interrotta_client', 'formato_non_valido',
                        'errore_applicativo')
     or p_token_input < 0 or p_token_output < 0 then
    raise exception 'ai_budget: parametri non validi' using errcode = '22023';
  end if;
  update private.ai_chiamate k
     set conclusa_il = clock_timestamp(), esito = p_esito, token_input = p_token_input, token_output = p_token_output,
         costo_stimato = case when p_token_input is not null and p_token_output is not null and k.tariffa_id is not null then
           (select ceil((p_token_input * t.input_per_milione + p_token_output * t.output_per_milione)) / 1000000
              from private.ai_tariffe t where t.id = k.tariffa_id) end
   where k.id = p_richiesta and k.conclusa_il is null;
  return found;
end;
$$;

-- =============================================================================================
-- 3. Quarantena delle proposte sospette
-- =============================================================================================
alter table catalog.contributions
  add column quarantine_reason text check (quarantine_reason is null or quarantine_reason ~ '^[a-z_]{3,40}$'),
  add column quarantined_at timestamptz,
  add column quarantine_released_by text check (quarantine_released_by is null or length(quarantine_released_by) <= 200),
  add constraint contributions_quarantine_shape check ((quarantine_reason is null) = (quarantined_at is null));
create index contributions_quarantine_idx on catalog.contributions (quarantined_at desc, id desc)
  where quarantine_reason is not null;

alter table catalog.intake_settings
  add column burst_hourly_limit integer not null default 8 check (burst_hourly_limit between 2 and 200),
  add column rejected_threshold integer not null default 3 check (rejected_threshold between 1 and 100);

-- Segnali di contenuto, deterministici. Non rifiutano: mandano a una persona.
create or replace function catalog.suspicion_reason(p_identity jsonb)
returns text language sql immutable set search_path = '' as $$
  with t as (
    select lower(coalesce(p_identity ->> 'produttore', '') || ' ' || coalesce(p_identity ->> 'nome', '') || ' '
                 || coalesce(p_identity ->> 'regione', '') || ' ' || coalesce(p_identity ->> 'denominazione', '')) as x,
           coalesce(p_identity ->> 'produttore', '') || coalesce(p_identity ->> 'nome', '') as n)
  select case
    when t.x ~ '([0-9][ .\-/]?){8,}' or t.x ~ '\+[0-9]{2}[ .\-]?[0-9]' then 'possibile_recapito'
    when t.x ~ '(whats\s?app|telegram|t\.me|instagram|bitcoin|crypto|casino|viagra|onlyfans)' then 'contenuto_promozionale'
    when t.x ~ '(ignora le istruzioni|ignore (all |the )?(previous|prior) instructions|system prompt|<\|)' then 'istruzioni_sospette'
    when t.n ~ '(.)\1{5,}' then 'caratteri_ripetuti'
    when length(t.n) >= 8 and length(regexp_replace(t.n, '[^[:alpha:]]', '', 'g')) < length(t.n) / 3 then 'testo_non_plausibile'
  end
  from t;
$$;

create or replace function catalog.contributions_quarantine_insert()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.quarantine_reason := catalog.suspicion_reason(new.identity);
  new.quarantined_at := case when new.quarantine_reason is not null then clock_timestamp() end;
  return new;
end;
$$;
create trigger contributions_quarantine_insert before insert on catalog.contributions
  for each row execute function catalog.contributions_quarantine_insert();

-- Invariante che vale anche per chi scrive con privilegi: una proposta in quarantena non diventa identità canonica.
create or replace function catalog.contributions_quarantine_guard()
returns trigger language plpgsql set search_path = '' as $$
begin
  if old.quarantine_reason is not null and new.quarantine_reason is not null and new.status is distinct from old.status then
    if new.status in ('collegata', 'creata') then
      raise exception 'catalog: proposta in quarantena, va rilasciata prima di deciderla' using errcode = '55000';
    elsif new.status = 'gia_collegata' then
      -- la chiusura automatica non scavalca la quarantena
      new.status := old.status;
      new.resolved_wine_id := old.resolved_wine_id;
      new.resolved_vintage_id := old.resolved_vintage_id;
    end if;
  end if;
  return new;
end;
$$;
create trigger contributions_quarantine_guard before update on catalog.contributions
  for each row execute function catalog.contributions_quarantine_guard();

-- Segnali di comportamento: ritmo anomalo o molte proposte già respinte. Non tocca proposte condivise con altri utenti.
create or replace function catalog.submissions_behaviour_check()
returns trigger language plpgsql set search_path = '' as $$
declare
  s catalog.intake_settings%rowtype;
  v_reason text;
begin
  if new.user_id is null then
    return null;
  end if;
  select * into s from catalog.intake_settings;
  if (select count(distinct x.contribution_id) from catalog.contribution_submissions x
       where x.user_id = new.user_id and x.created_at > now() - interval '1 hour') > s.burst_hourly_limit then
    v_reason := 'ritmo_anomalo';
  elsif (select count(*) from catalog.contribution_submissions x join catalog.contributions c on c.id = x.contribution_id
          where x.user_id = new.user_id and c.status = 'rifiutata' and c.reviewed_at > now() - interval '30 days')
        >= s.rejected_threshold then
    v_reason := 'proposte_respinte';
  end if;
  if v_reason is not null then
    update catalog.contributions c
       set quarantine_reason = v_reason, quarantined_at = clock_timestamp()
     where c.id = new.contribution_id and c.status = 'aperta' and c.quarantine_reason is null
       and c.quarantine_released_by is null
       and not exists (select 1 from catalog.contribution_submissions o
                        where o.contribution_id = c.id and o.user_id is distinct from new.user_id);
  end if;
  return null;
end;
$$;
create trigger submissions_behaviour_check after insert on catalog.contribution_submissions
  for each row execute function catalog.submissions_behaviour_check();

create or replace function public.catalogo_admin_quarantena(p_pagina integer default 1)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_page record;
begin
  perform private.catalog_admin_richiedi();
  select * into v_page from private.catalog_admin_pagina(p_pagina, 20);
  return coalesce((select jsonb_agg(to_jsonb(r)) from (
    select c.id, c.identity as dati, c.quarantine_reason as motivo, c.quarantined_at as dal, c.status as stato,
           c.first_origin as origine, c.submissions_count as invii
      from catalog.contributions c
     where c.quarantine_reason is not null and c.status = 'aperta'
     order by c.quarantined_at desc, c.id desc limit v_page.righe offset v_page.salto) r), '[]'::jsonb);
end;
$$;

create or replace function public.catalogo_admin_quarantena_decidi(p_id bigint, p_azione text, p_nota text)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare
  v_actor text := private.catalog_admin_richiedi();
  v_note text := nullif(btrim(coalesce(p_nota, '')), '');
begin
  if v_note is null or length(v_note) > 1000 then
    raise exception 'Il motivo è obbligatorio.' using errcode = '22023';
  end if;
  if p_azione = 'rilascia' then
    update catalog.contributions c
       set quarantine_reason = null, quarantined_at = null, quarantine_released_by = v_actor
     where c.id = p_id and c.status = 'aperta' and c.quarantine_reason is not null;
  elsif p_azione = 'quarantena' then
    update catalog.contributions c
       set quarantine_reason = 'decisione_curatore', quarantined_at = clock_timestamp(), quarantine_released_by = null
     where c.id = p_id and c.status = 'aperta' and c.quarantine_reason is null;
  else
    raise exception 'Azione non valida.' using errcode = '22023';
  end if;
  if not found then
    raise exception 'La proposta non è in uno stato adatto.' using errcode = 'P0002';
  end if;
  perform catalog.record_canonical_event('contribution_quarantine', 'contribution', p_id::text, v_actor,
    jsonb_build_object('azione', p_azione, 'motivo', v_note));
  return p_azione;
end;
$$;

revoke all on function catalog.suspicion_reason(jsonb), catalog.contributions_quarantine_insert(),
  catalog.contributions_quarantine_guard(), catalog.submissions_behaviour_check()
  from public, anon, authenticated, service_role, catalog_curator, catalog_loader;
revoke all on function public.catalogo_admin_quarantena(integer), public.catalogo_admin_quarantena_decidi(bigint, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.catalogo_admin_quarantena(integer),
  public.catalogo_admin_quarantena_decidi(bigint, text, text) to authenticated;

do $verifica$
begin
  if catalog.promotion_logic_fingerprint('lwin-conservative-v1') is null then
    raise exception 'WI-016B: una dipendenza dell''impronta non esiste più';
  end if;
end $verifica$;

notify pgrst, 'reload schema';
