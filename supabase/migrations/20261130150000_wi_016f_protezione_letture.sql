-- WI-016 F — protezione delle ricerche dalle letture automatiche (raffiche, raccolta sistematica, abuso di più account).
--
-- Perché serve: `public.vini_cerca` era STABLE, quindi PostgREST la eseguiva in sola lettura e `vinea_check_request`
-- usciva senza contare; l'hook inoltre identificava gli anonimi con il PRIMO valore di `x-forwarded-for`, che il
-- client scrive come vuole.
--
-- Che cosa fa, senza servizi nuovi:
--   * identità = utente del token; per gli anonimi un'impronta dell'indirizzo attestato dalla rete davanti a Supabase
--     (`cf-connecting-ip`; IPv6 ridotto alla /64). Mai `x-forwarded-for`. Se l'indirizzo non c'è, nessuna identità
--     inventata: restano concorrenza e tetto globale degli anonimi;
--   * limiti per identità (raffica, minuto, ora), posti di concorrenza per identità e globali (saturazione = rifiuto
--     immediato, senza code), tetto globale al minuto; anonimi e utenti hanno posti e tetti SEPARATI;
--   * `vini_cerca` diventa un involucro VOLATILE attorno al motore di WI-006B, spostato in `private` senza riscriverlo;
--   * la ricerca canonica, già limitata per utente, riceve i limiti comuni dall'hook solo a proiezione accesa.
--
-- Ciò che NON fa: le letture GET di tabelle e viste pubbliche restano senza contatore (il database le esegue in sola
-- lettura). Lì valgono `max_rows`, `statement_timeout` del ruolo e la protezione di rete del fornitore.
--
-- Nulla viene acceso: è una protezione, nasce attiva con soglie ampie. Il proprietario le cambia con un UPDATE.

create table private.protezione_letture (
  superficie text primary key check (superficie in ('ricerca_vini', 'ricerca_canonica')),
  attiva boolean not null default true,
  concorrenza_identita integer not null check (concorrenza_identita between 1 and 20),
  concorrenza_anonimi integer not null check (concorrenza_anonimi between 1 and 100),
  concorrenza_utenti integer not null check (concorrenza_utenti between 1 and 100),
  anonimo_raffica integer not null check (anonimo_raffica between 1 and 10000),
  anonimo_minuto integer not null check (anonimo_minuto between 1 and 10000),
  utente_raffica integer not null check (utente_raffica between 1 and 10000),
  utente_minuto integer not null check (utente_minuto between 1 and 10000),
  utente_ora integer not null check (utente_ora between 1 and 10000),
  anonimi_globale_minuto integer not null check (anonimi_globale_minuto between 1 and 10000),
  utenti_globale_minuto integer not null check (utenti_globale_minuto between 1 and 10000)
);
alter table private.protezione_letture enable row level security;
revoke all on private.protezione_letture from public, anon, authenticated, service_role;

-- raffica = richieste in 10 secondi. La ricerca del wizard parte da un pulsante, non a ogni tasto.
insert into private.protezione_letture (superficie, concorrenza_identita, concorrenza_anonimi, concorrenza_utenti,
  anonimo_raffica, anonimo_minuto, utente_raffica, utente_minuto, utente_ora, anonimi_globale_minuto, utenti_globale_minuto)
values
  ('ricerca_vini', 3, 6, 12, 15, 60, 20, 90, 900, 600, 3000),
  ('ricerca_canonica', 2, 2, 8, 10, 20, 15, 40, 600, 120, 1200);

-- L'indirizzo attestato dalla rete davanti a Supabase, come impronta. `null` = non attestato.
create or replace function private.origine_richiesta()
returns text language plpgsql stable set search_path = '' as $$
declare v_ip inet;
begin
  begin
    v_ip := (nullif(current_setting('request.headers', true), '')::jsonb ->> 'cf-connecting-ip')::inet;
  exception when others then
    return null;
  end;
  if v_ip is null then
    return null;
  end if;
  -- IPv6: un solo abbonato dispone di un'intera /64, quindi l'identità è la rete
  return encode(sha256(convert_to(
    case when family(v_ip) = 6 then host(network(set_masklen(v_ip, 64))) else host(v_ip) end, 'UTF8')), 'hex');
end;
$$;

-- La sola porta di protezione delle letture. Un rifiuto annulla la transazione, quindi non consuma nessun contatore:
-- chi è bloccato non brucia il tetto degli altri. I rifiuti si vedono nel registro di PostgreSQL.
create or replace function private.lettura_consenti(p_superficie text)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare
  c private.protezione_letture%rowtype;
  v_method text := nullif(current_setting('request.method', true), '');
  v_uid uuid := auth.uid();
  v_origin text;
  v_identity text;
  v_pool text;
  v_slots integer;
  v_global integer;
  v_start integer;
  v_slot integer;
  v_i integer;
  v_got boolean := false;
  v_reason text;
  v_status integer;
  v_code text;
  v_message text;
begin
  -- solo le richieste API di anon e authenticated: SQL del proprietario e percorso di servizio non si contano
  if v_method is null or coalesce(auth.jwt() ->> 'role', '') = 'service_role' then
    return;
  end if;
  select * into c from private.protezione_letture p where p.superficie = p_superficie;
  if not found then
    v_reason := 'configurazione'; v_status := 503; v_code := 'ricerca_non_disponibile';
    v_message := 'Ricerca non disponibile.';
  elsif not c.attiva then
    return;
  elsif current_setting('transaction_read_only', true) = 'on' then
    -- un GET gira in sola lettura: se non si può contare non si serve
    v_reason := 'metodo'; v_status := 405; v_code := 'metodo_non_consentito';
    v_message := 'Questa ricerca si chiama con POST.';
  else
    v_pool := case when v_uid is null then 'anonimi' else 'utenti' end;
    if v_uid is not null then
      v_identity := 'user:' || v_uid::text;
    else
      v_origin := private.origine_richiesta();
      v_identity := case when v_origin is not null then 'origine:' || v_origin end;
    end if;

    -- posti per identità: `try`, mai un'attesa
    if v_identity is not null then
      for v_i in 1..c.concorrenza_identita loop
        if pg_try_advisory_xact_lock(hashtextextended('lettura:' || p_superficie || ':' || v_identity || ':' || v_i, 0)) then
          v_got := true;
          exit;
        end if;
      end loop;
      if not v_got then
        v_reason := 'concorrenza_identita'; v_status := 429; v_code := 'troppe_ricerche_in_corso';
        v_message := 'Hai già ricerche in corso: attendi che finiscano.';
      end if;
    end if;

    if v_reason is null then
      v_slots := case v_pool when 'anonimi' then c.concorrenza_anonimi else c.concorrenza_utenti end;
      v_global := case v_pool when 'anonimi' then c.anonimi_globale_minuto else c.utenti_globale_minuto end;
      v_got := false;
      v_start := floor(random() * v_slots)::integer;
      for v_i in 0..v_slots - 1 loop
        v_slot := (v_start + v_i) % v_slots;
        if pg_try_advisory_xact_lock(hashtextextended('lettura:' || p_superficie || ':' || v_pool || ':posto:' || v_slot, 0)) then
          v_got := true;
          exit;
        end if;
      end loop;
      if not v_got then
        v_reason := 'saturazione'; v_status := 503; v_code := 'ricerca_satura';
        v_message := 'La ricerca è molto richiesta: riprova fra un momento.';
      end if;
    end if;
  end if;

  if v_reason is not null then
    raise log 'protezione_letture: rifiuto superficie=% motivo=% pool=%', p_superficie, v_reason, coalesce(v_pool, '-');
    raise sqlstate 'PGRST' using
      message = json_build_object('code', v_code, 'message', v_message)::text,
      detail = json_build_object('status', v_status,
        'headers', case when v_status = 405 then json_build_object('Allow', 'POST') else json_build_object('Retry-After', '2') end)::text;
  end if;

  begin
    if v_uid is not null then
      perform private.rate_limit_consume(p_superficie || ':raffica', v_identity, c.utente_raffica, 10);
      perform private.rate_limit_consume(p_superficie || ':minuto', v_identity, c.utente_minuto, 60);
      perform private.rate_limit_consume(p_superficie || ':ora', v_identity, c.utente_ora, 3600);
    elsif v_identity is not null then
      perform private.rate_limit_consume(p_superficie || ':raffica', v_identity, c.anonimo_raffica, 10);
      perform private.rate_limit_consume(p_superficie || ':minuto', v_identity, c.anonimo_minuto, 60);
    end if;
    -- tetto globale diviso fra i posti: la riga appartiene a chi tiene il posto, quindi nessuno aspetta un altro
    perform private.rate_limit_consume(p_superficie || ':globale', v_pool || ':' || v_slot,
      greatest(1, v_global / v_slots), 60);
  exception when sqlstate 'PGRST' then
    raise log 'protezione_letture: rifiuto superficie=% motivo=limite pool=%', p_superficie, v_pool;
    raise;
  end;
end;
$$;

revoke all on function private.origine_richiesta(), private.lettura_consenti(text)
  from public, anon, authenticated, service_role;

-- =============================================================================================
-- Ricerca dei vini: il motore di WI-006B si SPOSTA (corpo invariato), davanti resta la stessa firma
-- =============================================================================================
alter function public.vini_cerca(text, text, integer, text, integer, text) set schema private;
alter function private.vini_cerca(text, text, integer, text, integer, text) rename to vini_cerca_motore;
revoke all on function private.vini_cerca_motore(text, text, integer, text, integer, text)
  from public, anon, authenticated, service_role;

create function public.vini_cerca(
  p_produttore text default '',
  p_nome text default '',
  p_annata integer default null,
  p_formato text default null,
  p_limite integer default 15,
  p_codice text default null
)
returns table (
  fonte text,
  vino_id uuid,
  slug text,
  produttore text,
  nome text,
  annata integer,
  formato text,
  regione text,
  denominazione text,
  tipo text,
  annunci integer,
  punteggio integer,
  livello text
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform private.lettura_consenti('ricerca_vini');
  return query
    select * from private.vini_cerca_motore(p_produttore, p_nome, p_annata, p_formato, p_limite, p_codice);
end;
$$;

comment on function public.vini_cerca(text, text, integer, text, integer, text) is
  'WI-006B: ricerca dei vini ordinata per pertinenza, con la visibilità delle policy di wines e degli annunci pubblici. '
  'WI-016: porta protetta da private.lettura_consenti (per questo è VOLATILE); il motore è private.vini_cerca_motore.';

revoke all on function public.vini_cerca(text, text, integer, text, integer, text) from public;
grant execute on function public.vini_cerca(text, text, integer, text, integer, text)
  to anon, authenticated, service_role;

-- =============================================================================================
-- Hook: identica a VPM-022A salvo l'origine anonima attestata, `vini_cerca` (protetta dentro la funzione) e i limiti
-- comuni della ricerca canonica a proiezione accesa.
-- =============================================================================================
create or replace function private.vinea_check_request()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_method text := current_setting('request.method', true);
  v_path text := current_setting('request.path', true);
  v_uid uuid := auth.uid();
  v_subject text;
  v_limit integer;
begin
  if v_method is null or v_method in ('GET', 'HEAD', 'OPTIONS') then
    return;
  end if;

  -- Una RPC `stable`/`immutable` chiamata in POST gira in transazione di sola
  -- lettura: e' una lettura per costruzione, e le letture non si contano. Senza
  -- questa uscita la insert qui sotto solleva 25006 e PostgREST risponde 405.
  if current_setting('transaction_read_only', true) = 'on' then
    return;
  end if;

  -- WI-016: `vini_cerca` ha la protezione dentro la funzione (vale anche se chiamata da un'altra porta API).
  if v_path = '/rpc/vini_cerca' then
    return;
  end if;
  -- WI-016: a proiezione spenta la ricerca canonica non espone nulla e non consuma nulla.
  if v_path = '/rpc/vini_canonici_cerca'
     and coalesce((select s.enabled from catalog.public_projection_settings s), false) then
    perform private.lettura_consenti('ricerca_canonica');
  end if;

  -- WI-016: l'anonimo è l'indirizzo attestato dalla rete, mai `x-forwarded-for` (scritto dal client).
  v_subject := case
    when v_uid is not null then 'user:' || v_uid::text
    else 'ip:' || coalesce(private.origine_richiesta(), 'unknown')
  end;
  v_limit := case when coalesce(v_path, '') like '/rpc/%' then 60 else 120 end;

  perform private.rate_limit_consume(
    'postgrest:' || coalesce(v_path, 'unknown'),
    v_subject,
    v_limit,
    60
  );
end;
$$;

do $verifica$
begin
  if catalog.promotion_logic_fingerprint('lwin-conservative-v1') is null then
    raise exception 'WI-016F: una dipendenza dell''impronta non esiste più';
  end if;
end $verifica$;

notify pgrst, 'reload schema';
