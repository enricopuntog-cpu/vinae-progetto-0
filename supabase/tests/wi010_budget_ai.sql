-- WI-010 (griglia wi010): budget globale AI chiuso per difetto, tetti giornaliero e mensile, interruttore sui guasti,
-- consuntivo senza dati utente e superficie riservata a service_role. SOLO stack locale/effimero; tutto in ROLLBACK.
-- La concorrenza (due richieste sull'ultimo posto) è garantita dal lock della riga singleton: qui se ne verifica la presenza.

begin;
\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email is null or email not like '%.test') then
    raise exception 'Guard wi010: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_wi010 (id text primary key, descrizione text not null, passed boolean not null, detail text not null) on commit drop;
create function pg_temp.rec(p_id text, p_desc text, p_ok boolean, p_detail text default '')
returns void language sql as $f$ insert into esiti_wi010 values (p_id, p_desc, coalesce(p_ok, false), coalesce(p_detail, '')) $f$;

-- Stato di partenza della sola transazione (lo stack può avere un budget impostato da altre prove).
delete from private.ai_consumo_giornaliero;
update private.ai_budget_settings set richieste_giorno = null, richieste_mese = null, guasti_per_apertura = 3,
  pausa_secondi = 600, guasti_consecutivi = 0, aperto_fino_a = null;

do $$
declare
  v text;
  s jsonb;
  oggi date := (now() at time zone 'utc')::date;
begin
  v := public.ai_budget_consuma('ai:chat');
  perform pg_temp.rec('A01', 'senza budget configurato non si consuma nulla', v = 'non_configurato', v);
  update private.ai_budget_settings set richieste_giorno = 100;
  v := public.ai_budget_consuma('ai:chat');
  perform pg_temp.rec('A02', 'il solo tetto giornaliero non basta: serve anche il mensile', v = 'non_configurato', v);

  update private.ai_budget_settings set richieste_giorno = 3, richieste_mese = 100;
  v := public.ai_budget_consuma('ai:chat') || ',' || public.ai_budget_consuma('ai:pairing') || ',' || public.ai_budget_consuma('ai:catalogo');
  perform pg_temp.rec('B01', 'tre funzioni diverse consumano lo stesso tetto', v = 'consentito,consentito,consentito', v);
  v := public.ai_budget_consuma('ai:chat');
  perform pg_temp.rec('B02', 'la quarta richiesta del giorno è rifiutata', v = 'giorno_esaurito', v);

  update private.ai_budget_settings set richieste_giorno = 100, richieste_mese = 5;
  insert into private.ai_consumo_giornaliero (giorno, scope, consentite)
    values (date_trunc('month', oggi)::date - 1, 'ai:chat', 1000);
  v := public.ai_budget_consuma('ai:chat');
  perform pg_temp.rec('B03', 'il consumo del mese precedente non conta', v = 'consentito', v);
  v := public.ai_budget_consuma('ai:chat') || ',' || public.ai_budget_consuma('ai:chat');
  perform pg_temp.rec('B04', 'al quinto consumo del mese il tetto mensile ferma', v = 'consentito,mese_esaurito', v);
  update private.ai_budget_settings set richieste_mese = 0;
  v := public.ai_budget_consuma('ai:chat');
  perform pg_temp.rec('B05', 'tetto a zero = spento', v in ('mese_esaurito', 'giorno_esaurito'), v);

  update private.ai_budget_settings set richieste_giorno = 1000, richieste_mese = 1000;
  perform public.ai_budget_esito('ai:chat', false);
  perform public.ai_budget_esito('ai:chat', false);
  v := public.ai_budget_consuma('ai:chat');
  perform pg_temp.rec('C01', 'due guasti su tre: ancora aperto al traffico', v = 'consentito', v);
  perform public.ai_budget_esito('ai:pairing', false);
  v := public.ai_budget_consuma('ai:catalogo');
  perform pg_temp.rec('C02', 'al terzo guasto consecutivo l''interruttore ferma tutte le funzioni', v = 'interruttore_aperto', v);
  update private.ai_budget_settings set aperto_fino_a = clock_timestamp() - interval '1 second';
  v := public.ai_budget_consuma('ai:chat');
  perform pg_temp.rec('C03', 'scaduta la pausa si riprova', v = 'consentito', v);
  perform public.ai_budget_esito('ai:chat', false);
  v := public.ai_budget_consuma('ai:chat');
  perform pg_temp.rec('C04', 'dopo la pausa un solo guasto riapre', v = 'interruttore_aperto', v);
  update private.ai_budget_settings set aperto_fino_a = clock_timestamp() - interval '1 second';
  perform public.ai_budget_esito('ai:chat', true);
  perform public.ai_budget_esito('ai:chat', false);
  v := public.ai_budget_consuma('ai:chat');
  perform pg_temp.rec('C05', 'un successo azzera: un guasto isolato non ferma', v = 'consentito', v);

  s := public.ai_budget_stato();
  perform pg_temp.rec('D01', 'il consuntivo riporta consumi, rifiuti e guasti di oggi',
    (s ->> 'configurato')::boolean and (s #>> '{oggi,consentite}')::int > 0 and (s #>> '{oggi,rifiutate_budget}')::int >= 4
    and (s #>> '{oggi,rifiutate_interruttore}')::int = 2 and (s #>> '{oggi,guasti_fornitore}')::int = 5, s::text);
  perform pg_temp.rec('D02', 'il consuntivo non ha colonne capaci di contenere dati di un utente',
    not exists (select 1 from information_schema.columns where table_schema = 'private' and table_name = 'ai_consumo_giornaliero'
                 and column_name not in ('giorno', 'scope', 'consentite', 'rifiutate_budget', 'rifiutate_interruttore', 'guasti_fornitore')));

  begin perform public.ai_budget_consuma('ai:altro'); v := 'accettata'; exception when others then v := sqlstate; end;
  perform pg_temp.rec('E01', 'funzione sconosciuta rifiutata', v = '22023', v);
  perform pg_temp.rec('E02', 'le tre porte: solo service_role',
    (select bool_and(not has_function_privilege('anon', f, 'EXECUTE') and not has_function_privilege('authenticated', f, 'EXECUTE')
                     and has_function_privilege('service_role', f, 'EXECUTE'))
       from unnest(array['public.ai_budget_consuma(text)', 'public.ai_budget_esito(text,boolean)', 'public.ai_budget_stato()']) f));
  perform pg_temp.rec('E03', 'nessun ruolo API legge o scrive le tabelle, nemmeno service_role',
    (select bool_and(not has_table_privilege(r, t, 'SELECT,INSERT,UPDATE,DELETE'))
       from unnest(array['anon', 'authenticated', 'service_role']) r,
            unnest(array['private.ai_budget_settings', 'private.ai_consumo_giornaliero']) t));
  perform pg_temp.rec('E04', 'definer con search_path vuoto e nessun EXECUTE a PUBLIC',
    (select count(*) from pg_proc p where p.proname in ('ai_budget_consuma', 'ai_budget_esito', 'ai_budget_stato')
       and p.prosecdef and exists (select 1 from unnest(p.proconfig) c where c ~ '^search_path=("")?$')
       and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 3);
  perform pg_temp.rec('E05', 'il consumo blocca la riga singleton prima di contare (concorrenza)',
    (select prosrc ~ 'from private\.ai_budget_settings where singleton for update' from pg_proc
      where oid = 'public.ai_budget_consuma(text)'::regprocedure));
end $$;

select id, descrizione, passed, detail from esiti_wi010 order by id;
do $$
begin
  if exists (select 1 from esiti_wi010 where not passed) then
    raise exception 'wi010: casi rossi: %', (select string_agg(id || ' ' || left(detail, 200), ' | ' order by id) from esiti_wi010 where not passed);
  end if;
end $$;
rollback;
