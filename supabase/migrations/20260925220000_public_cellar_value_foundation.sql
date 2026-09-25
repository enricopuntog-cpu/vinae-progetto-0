-- Cantina pubblica — valore di riferimento opzionale, fondazione DB.
--
-- Questa superficie espone un VALORE DI RIFERIMENTO della sola collezione che
-- il proprietario mostra adesso, non il suo patrimonio e non la sua contabilita.
-- La sorgente economica resta esclusivamente `wine_reference_snapshots`: mediana
-- Vinea valida, almeno tre comparabili, NULL quando il riferimento non esiste.
-- Non vengono letti costi d'acquisto, prezzi degli annunci, ordini, pagamenti,
-- payout o saldi.
--
-- LO STORICO HA UNA SEMANTICA DELIBERATAMENTE LIMITATA. Non esiste uno storico
-- delle transizioni `privata <-> cantina_pubblica`, quindi non si finge di
-- ricostruire «la Cantina che era pubblica quel giorno». Si prende la collezione
-- attualmente esposta da `private.cantina_pubblica`; per quelle sole unita si
-- aggregano gli snapshot reali gia esistenti, senza mostrare una posizione prima
-- del suo `acquired_at` e senza usare uno snapshot futuro. La data di acquisizione
-- e un confine interno del calcolo e non attraversa la porta pubblica.

create schema if not exists private;

-- ---------------------------------------------------------------------------
-- [1] Preferenza privata — assenza riga = OFF
-- ---------------------------------------------------------------------------

create table private.cellar_public_settings (
  owner_id uuid primary key
    references public.profiles (id) on delete cascade,
  mostra_valore boolean not null,
  updated_at timestamptz not null default now()
);

comment on table private.cellar_public_settings is
  'Preferenza owner-only per il valore di riferimento della Cantina pubblica. '
  'Assenza riga equivale a OFF; nessun backfill. Non e una superficie PostgREST '
  'e non ha privilegi client diretti: si legge e scrive soltanto con le RPC dedicate.';
comment on column private.cellar_public_settings.mostra_valore is
  'Se true, la porta per singolo profilo puo esporre aggregati D3 della sola '
  'collezione attualmente pubblica. Non abilita costi, capitale o performance.';

alter table private.cellar_public_settings enable row level security;

-- Nessuna policy: anche un GRANT client aggiunto per errore resterebbe chiuso.
-- Le RPC SECURITY DEFINER appartengono al proprietario della tabella e sono le
-- sole porte previste.
revoke all on private.cellar_public_settings from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [2] Porte del proprietario
-- ---------------------------------------------------------------------------

create function public.cantina_pubblica_valore_impostazione()
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  return coalesce(
    (select s.mostra_valore
     from private.cellar_public_settings s
     where s.owner_id = v_uid),
    false
  );
end;
$$;

comment on function public.cantina_pubblica_valore_impostazione() is
  'Legge la preferenza del solo auth.uid(); false quando la riga non esiste. '
  'Owner-only, nessun parametro che possa nominare un altro profilo.';

revoke all on function public.cantina_pubblica_valore_impostazione() from public, anon;
grant execute on function public.cantina_pubblica_valore_impostazione() to authenticated;

create function public.cantina_pubblica_valore_imposta(p_visibile boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  if p_visibile is null then
    raise exception 'La preferenza deve essere true oppure false.' using errcode = '22004';
  end if;
  if not exists (
    select 1
    from public.profiles p
    where p.id = v_uid
      and p.stato_utente <> 'rimosso'::public.utente_stato
  ) then
    -- Stessa risposta per profilo assente e rimosso: nessun dettaglio interno.
    raise exception 'Profilo non disponibile.' using errcode = '42501';
  end if;

  insert into private.cellar_public_settings (owner_id, mostra_valore, updated_at)
  values (v_uid, p_visibile, now())
  on conflict (owner_id) do update
    set mostra_valore = excluded.mostra_valore,
        updated_at = case
          when private.cellar_public_settings.mostra_valore is distinct from excluded.mostra_valore
            then excluded.updated_at
          else private.cellar_public_settings.updated_at
        end;

  return p_visibile;
end;
$$;

comment on function public.cantina_pubblica_valore_imposta(boolean) is
  'Imposta idempotentemente la preferenza del solo auth.uid(). Non accetta un '
  'owner_id e rifiuta profili assenti o rimossi. Nessun accesso diretto alla tabella privata.';

revoke all on function public.cantina_pubblica_valore_imposta(boolean) from public, anon;
grant execute on function public.cantina_pubblica_valore_imposta(boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- [3] Porta pubblica aggregata — un profilo noto per volta
-- ---------------------------------------------------------------------------
--
-- Forma OFF deterministica: una riga con `visibile=false`, campi aggregati NULL
-- e serie `[]`. Vale anche per uuid nullo/sconosciuto, proprietario non pubblico
-- o chiamante rimosso, cosi il comportamento non apre un nuovo oracolo sugli
-- stati di moderazione. ON esiste solo se il profilo passa dalla stessa sorgente
-- canonica della Cantina e la preferenza privata e true.

create function public.cantina_pubblica_valore(p_user_id uuid)
returns table (
  visibile boolean,
  generato_at timestamptz,
  valore_riferimento_cents bigint,
  bottiglie_pubbliche integer,
  bottiglie_con_riferimento integer,
  copertura text,
  serie jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_generato timestamptz := statement_timestamp();
  v_abilitato boolean := false;
begin
  select exists (
    select 1
    from private.profili_pubblici pp
    join private.cellar_public_settings s
      on s.owner_id = pp.user_id
     and s.mostra_valore
    where pp.user_id = p_user_id
  ) into v_abilitato;

  if not v_abilitato then
    return query
      select false, null::timestamptz, null::bigint, null::integer,
             null::integer, null::text, '[]'::jsonb;
    return;
  end if;

  return query
  with collezione as materialized (
    -- `private.cantina_pubblica` decide l'appartenenza. Il join alla tabella base
    -- recupera soltanto acquired_at, confine storico interno; non ricostruisce
    -- alcun predicato di pubblicabilita e non legge il costo di acquisizione.
    select c.bottle_unit_id, c.wine_id, c.formato, bu.acquired_at
    from private.cantina_pubblica c
    join public.bottle_units bu on bu.id = c.bottle_unit_id
    where c.user_id = p_user_id
  ),
  riferimento_corrente as (
    select distinct on (s.wine_id, s.formato)
      s.wine_id, s.formato, s.mediana_cents
    from public.wine_reference_snapshots s
    join (select distinct c.wine_id, c.formato from collezione c) k
      on k.wine_id = s.wine_id and k.formato = s.formato
    order by s.wine_id, s.formato, s.observed_at desc, s.created_at desc, s.id desc
  ),
  corrente as (
    select
      count(*)::integer as totale,
      count(r.mediana_cents)::integer as coperte,
      sum(r.mediana_cents)::bigint as valore
    from collezione c
    left join riferimento_corrente r
      on r.wine_id = c.wine_id and r.formato = c.formato
  ),
  istanti as (
    -- Punti soltanto a timestamp di snapshot reali pertinenti alla collezione.
    select distinct s.observed_at as at
    from public.wine_reference_snapshots s
    join (select distinct c.wine_id, c.formato from collezione c) k
      on k.wine_id = s.wine_id and k.formato = s.formato
  ),
  storico as (
    select
      i.at,
      count(c.bottle_unit_id) filter (where r.mediana_cents is not null)::integer as coperte,
      count(c.bottle_unit_id) filter (where r.mediana_cents is null)::integer as scoperte,
      sum(r.mediana_cents)::bigint as valore
    from istanti i
    left join collezione c on c.acquired_at <= i.at
    left join lateral (
      -- As-of: l'ultimo snapshot noto a quell'istante, mai uno successivo.
      select s.mediana_cents
      from public.wine_reference_snapshots s
      where s.wine_id = c.wine_id
        and s.formato = c.formato
        and s.observed_at <= i.at
      order by s.observed_at desc, s.created_at desc, s.id desc
      limit 1
    ) r on true
    group by i.at
  ),
  serie_aggregata as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'at', h.at,
          'valoreCents', h.valore,
          'coperte', h.coperte,
          'scoperte', h.scoperte
        ) order by h.at
      ),
      '[]'::jsonb
    ) as punti
    from storico h
  )
  select
    true,
    v_generato,
    c.valore,
    c.totale,
    c.coperte,
    case
      when c.totale = 0 or c.coperte = 0 then 'non_disponibile'
      when c.coperte = c.totale then 'completa'
      else 'parziale'
    end,
    s.punti
  from corrente c
  cross join serie_aggregata s;
end;
$$;

comment on function public.cantina_pubblica_valore(uuid) is
  'Valore di riferimento aggregato della collezione attualmente esposta da UN '
  'profilo gia noto, solo se opt-in. Usa le mediane D3 reali e non la contabilita '
  'del proprietario. Lo storico segue gli snapshot reali as-of e acquired_at, ma '
  'non ricostruisce la vecchia visibilita e non restituisce identificativi o date '
  'delle singole bottiglie. OFF/non pubblico/sconosciuto restituiscono la stessa '
  'riga visibile=false con serie vuota.';

revoke all on function public.cantina_pubblica_valore(uuid) from public;
grant execute on function public.cantina_pubblica_valore(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- [4] Guardie fail-closed della superficie
-- ---------------------------------------------------------------------------

do $$
declare
  v_src text;
  v_args text;
  v_out text;
begin
  select lower(p.prosrc), pg_get_function_arguments(p.oid),
         pg_get_function_result(p.oid)
  into v_src, v_args, v_out
  from pg_proc p
  where p.oid = 'public.cantina_pubblica_valore(uuid)'::regprocedure;

  if v_src ~ '(public\.)?(orders|payments|payouts|balance_accounts|balance_movimenti|balance_movements)'
     or v_src ~ 'acquisition_cost_cents' then
    raise exception
      'Invariante: il valore pubblico non deve dipendere dalla contabilita o dal costo di acquisto.';
  end if;

  if v_args !~ '^p_user_id uuid$' then
    raise exception
      'Invariante: la porta pubblica deve accettare soltanto un profilo noto.';
  end if;

  if lower(v_out) ~ '(bottle_unit_id|wine_id|order_id|payment|payout|acquired_at|acquisition|costo|prezzo)'
     or lower(v_out) !~ 'visibile boolean.*generato_at timestamp with time zone.*valore_riferimento_cents bigint.*bottiglie_pubbliche integer.*bottiglie_con_riferimento integer.*copertura text.*serie jsonb' then
    raise exception
      'Invariante: la firma pubblica deve restare aggregata e con allowlist chiusa.';
  end if;

  if has_table_privilege(
       'anon', 'private.cellar_public_settings',
       'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'
     )
     or has_table_privilege(
       'authenticated', 'private.cellar_public_settings',
       'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'
     ) then
    raise exception
      'Invariante: i ruoli client non devono avere accesso diretto ai setting privati.';
  end if;
end;
$$;

notify pgrst, 'reload schema';
