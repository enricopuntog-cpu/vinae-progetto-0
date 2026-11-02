-- VPM-015C: Accessori NUOVI dei Vinea Partner (margine 15%).
--
-- INTEGRA, non riscrive. Un accessorio commerciale e una riga di
-- `private.cantina_accessori` (stessa tabella, stesse foto, stessa categoria,
-- stesso annuncio, stesso checkout B5A, stessi pagamenti B5B, stesso
-- post-vendita B5C) con due colonne in piu: `inventario` ('personale' |
-- 'commerciale') e `partner_id`. Come `bottle_units` (VP-C) distingue le
-- scorte dal patrimonio personale, ma `bottle_units` NON si usa: sono bottiglie.
--
-- Che cosa NON cambia: aliquote del vino, formula economica
-- (`private.preventivo_dominio`, riga 1500 bps gia in
-- `marketplace_margini_dominio`), tariffe logistiche, ledger del saldo,
-- interruttori (`vendita_partner`, `checkout_attivo`, pubblicazione, ...: tutti
-- restano spenti, nessuno si accende qui).
--
-- Perimetro: la classe del venditore diventa PER ARTICOLO. La funzione a un
-- argomento resta quella dei privati (un Partner attivo/sospeso non vende
-- accessori personali). Un overload a due argomenti decide per l'articolo:
-- commerciale + Partner attivo del titolare -> classe `partner`; vendibile
-- solo con `vendita_partner` acceso (gate gia esistente, spento).

-- ---------------------------------------------------------------------------
-- [1] Inventario commerciale nella Cantina Accessori
-- ---------------------------------------------------------------------------

alter table private.cantina_accessori
  add column inventario text not null default 'personale',
  add column partner_id uuid references private.partners (id) on delete restrict;

alter table private.cantina_accessori
  add constraint cantina_accessori_inventario_ammesso
    check (inventario in ('personale', 'commerciale')),
  add constraint cantina_accessori_partner_coerente
    check ((inventario = 'commerciale') = (partner_id is not null)),
  -- Un articolo commerciale e NUOVO e mai esposto nella Cantina pubblica
  -- personale: la vetrina Partner e un'altra superficie.
  add constraint cantina_accessori_commerciale_nuovo
    check (inventario = 'personale' or (condizione = 'nuovo' and visibilita = 'privata'));

create index cantina_accessori_partner_idx
  on private.cantina_accessori (partner_id, archiviato_at, created_at desc)
  where partner_id is not null;

comment on column private.cantina_accessori.inventario is
  'VPM-015C: personale (Cantina del collezionista) o commerciale (scorta di un Vinea Partner). Immutabile.';
comment on column private.cantina_accessori.partner_id is
  'VPM-015C: Partner proprietario della scorta commerciale; null per il patrimonio personale. Immutabile.';

create function private.cantina_accessori_inventario_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_partner uuid;
begin
  if tg_op = 'INSERT' then
    if coalesce(current_setting('vinae.accessori_partner_porta', true), '')
         = 'crea:' || new.owner_id::text || ':' || new.id::text then
      -- Creazione dalla porta Partner: il Partner e quello ATTIVO del titolare,
      -- mai un valore del chiamante.
      select p.id into v_partner
      from private.partners p
      where p.titolare_id = new.owner_id and p.stato = 'attivo'::public.partner_stato;
      if v_partner is null then
        raise exception 'Serve un Partner attivo.' using errcode = '42501', hint = 'partner_non_attivo';
      end if;
      new.inventario := 'commerciale';
      new.partner_id := v_partner;
    elsif new.inventario <> 'personale' or new.partner_id is not null then
      raise exception 'Un articolo commerciale nasce solo dalla porta Partner.'
        using errcode = '42501', hint = 'inventario_non_autorizzato';
    end if;
    return new;
  end if;

  if new.inventario is distinct from old.inventario or new.partner_id is distinct from old.partner_id then
    raise exception 'La natura dell''articolo non cambia.' using errcode = '42501', hint = 'inventario_immutabile';
  end if;
  -- Una scorta commerciale non si aumenta se il Partner non e attivo (un Partner
  -- sospeso o revocato conserva cio che ha, non ne aggiunge).
  if old.inventario = 'commerciale' and new.quantita > old.quantita
     and not exists (select 1 from private.partners p
                     where p.id = old.partner_id and p.stato = 'attivo'::public.partner_stato) then
    raise exception 'Le scorte si aumentano solo con un Partner attivo.'
      using errcode = '42501', hint = 'partner_non_attivo';
  end if;
  return new;
end;
$$;

revoke execute on function private.cantina_accessori_inventario_guard() from public, anon, authenticated;

create trigger cantina_accessori_inventario_guard
  before insert or update on private.cantina_accessori
  for each row execute function private.cantina_accessori_inventario_guard();

-- ---------------------------------------------------------------------------
-- [2] Storico delle movimentazioni (append-only)
-- ---------------------------------------------------------------------------

create table private.accessori_partner_movimenti (
  id bigint generated always as identity primary key,
  partner_id uuid not null,
  cantina_accessorio_id uuid not null,
  causale text not null,
  delta integer not null,
  quantita_dopo integer not null,
  created_at timestamptz not null default now(),
  constraint accessori_partner_movimenti_causale
    check (causale in ('carico', 'rettifica', 'vendita', 'rimozione')),
  constraint accessori_partner_movimenti_delta check (delta <> 0)
);
-- Nessuna chiave esterna: lo storico sopravvive all'articolo.
create index accessori_partner_movimenti_articolo_idx
  on private.accessori_partner_movimenti (cantina_accessorio_id, id desc);

alter table private.accessori_partner_movimenti enable row level security;
revoke all on table private.accessori_partner_movimenti from public, anon, authenticated, service_role;

create function private.accessori_partner_movimenti_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Lo storico delle movimentazioni e append-only.' using errcode = '42501';
end;
$$;
revoke execute on function private.accessori_partner_movimenti_append_only() from public, anon, authenticated;

create trigger accessori_partner_movimenti_append_only
  before update or delete on private.accessori_partner_movimenti
  for each row execute function private.accessori_partner_movimenti_append_only();
create trigger accessori_partner_movimenti_no_truncate
  before truncate on private.accessori_partner_movimenti
  for each statement execute function private.accessori_partner_movimenti_append_only();

-- Ogni variazione di quantita di una scorta commerciale, da qualunque scrittore.
-- La vendita (B5A) avviene sotto il marcatore `vinae.accessori_vendita` o dal
-- nucleo di vendita: in quel caso la causale e `vendita`.
create function private.cantina_accessori_movimenti_log()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_delta integer;
  v_causale text;
begin
  if tg_op = 'INSERT' then
    if new.inventario = 'commerciale' and new.quantita > 0 then
      insert into private.accessori_partner_movimenti (partner_id, cantina_accessorio_id, causale, delta, quantita_dopo)
      values (new.partner_id, new.id, 'carico', new.quantita, new.quantita);
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    if old.inventario = 'commerciale' and old.quantita > 0 then
      insert into private.accessori_partner_movimenti (partner_id, cantina_accessorio_id, causale, delta, quantita_dopo)
      values (old.partner_id, old.id, 'rimozione', -old.quantita, 0);
    end if;
    return old;
  end if;

  if new.inventario = 'commerciale' and new.quantita is distinct from old.quantita then
    v_delta := new.quantita - old.quantita;
    v_causale := case
      when v_delta > 0 then 'carico'
      when coalesce(current_setting('vinae.accessori_vendita_scorta', true), '') = 'on'
        then 'vendita'
      else 'rettifica' end;
    insert into private.accessori_partner_movimenti (partner_id, cantina_accessorio_id, causale, delta, quantita_dopo)
    values (new.partner_id, new.id, v_causale, v_delta, new.quantita);
  end if;
  return new;
end;
$$;
revoke execute on function private.cantina_accessori_movimenti_log() from public, anon, authenticated;

create trigger cantina_accessori_movimenti_log
  after insert or update or delete on private.cantina_accessori
  for each row execute function private.cantina_accessori_movimenti_log();

-- ---------------------------------------------------------------------------
-- [3] Classe e ammissione del venditore PER ARTICOLO
-- ---------------------------------------------------------------------------
--
-- Overload a due argomenti. Articolo personale, sconosciuto o di altri: stessa
-- decisione della funzione a un argomento (nessun Partner vende accessori
-- personali, un revocato e bloccato). Articolo commerciale: solo il Partner
-- proprietario dell'articolo, ATTIVO, con account attivo. `vendibile` aggiunge
-- l'interruttore `vendita_partner` (spento): senza, l'annuncio si prepara e non
-- si vede ne si compra.

create function private.annuncio_accessorio_venditore(
  p_seller_id uuid,
  p_cantina uuid,
  out classe public.classe_venditore,
  out ammesso boolean,
  out motivo text,
  out vendibile boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  c private.cantina_accessori%rowtype;
  p private.partners%rowtype;
begin
  if p_cantina is not null then
    select * into c from private.cantina_accessori where id = p_cantina;
  end if;

  if c.id is null or c.inventario = 'personale' or c.owner_id is distinct from p_seller_id then
    select v.classe, v.ammesso, v.motivo into classe, ammesso, motivo
    from private.annuncio_accessorio_venditore(p_seller_id) v;
    vendibile := ammesso;
    return;
  end if;

  classe := 'partner'; ammesso := false; vendibile := false;
  select * into p from private.partners where id = c.partner_id;
  if p.id is null or p.titolare_id <> p_seller_id then
    motivo := 'partner_non_valido';
  elsif p.stato = 'revocato'::public.partner_stato then
    motivo := 'partner_revocato';
  elsif p.stato = 'sospeso'::public.partner_stato then
    motivo := 'partner_sospeso';
  elsif p.stato <> 'attivo'::public.partner_stato then
    motivo := 'partner_non_attivo';
  elsif private.utente_stato_di(p_seller_id) <> 'attivo'::public.utente_stato then
    motivo := 'account_non_attivo';
  else
    ammesso := true;
    vendibile := private.inventario_flag('vendita_partner');
    motivo := case when vendibile then null else 'vendita_partner_chiusa' end;
  end if;
end;
$$;

comment on function private.annuncio_accessorio_venditore(uuid, uuid) is
  'VPM-015C: classe e ammissione del venditore per un ARTICOLO (personale: come la '
  'versione a un argomento; commerciale: Partner proprietario attivo). Decide il database.';
revoke execute on function private.annuncio_accessorio_venditore(uuid, uuid) from public, anon, authenticated;

-- Patch mirate dei sei punti che decidono la classe, con asserzione: ogni
-- sostituzione deve avvenire UNA volta, altrimenti la migrazione si ferma.
create function pg_temp.patch_015c(p_sig regprocedure, p_old text, p_new text)
returns void
language plpgsql
as $$
declare
  v_def text := pg_get_functiondef(p_sig);
  v_n integer := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
begin
  if v_n <> 1 then
    raise exception 'patch_015c: % occorrenze di % in %', v_n, p_old, p_sig;
  end if;
  execute replace(v_def, p_old, p_new);
end;
$$;

select pg_temp.patch_015c('private.annunci_accessori_guard()'::regprocedure,
  'select * into v_v from private.annuncio_accessorio_venditore(new.seller_id)',
  'if exists (select 1 from private.cantina_accessori c
              where c.id = new.cantina_accessorio_id and c.inventario = ''commerciale'')
     and new.condizione <> ''nuovo'' then
    raise exception ''Un articolo commerciale si vende solo come nuovo.''
      using errcode = ''22023'', hint = ''condizione_non_nuova'';
  end if;
  select * into v_v from private.annuncio_accessorio_venditore(new.seller_id, new.cantina_accessorio_id)');

select pg_temp.patch_015c('private.annuncio_accessorio_visibile(uuid)'::regprocedure,
  '(select v.ammesso from private.annuncio_accessorio_venditore(a.seller_id) v)',
  '(select v.vendibile from private.annuncio_accessorio_venditore(a.seller_id, a.cantina_accessorio_id) v)');

select pg_temp.patch_015c('public.annunci_accessori_salva(uuid,jsonb)'::regprocedure,
  'private.annuncio_accessorio_venditore(v_uid)',
  'private.annuncio_accessorio_venditore(v_uid, v_item.id)');

select pg_temp.patch_015c('public.annunci_accessori_preventivo(integer,integer,uuid)'::regprocedure,
  'private.annuncio_accessorio_venditore(v_uid)',
  'private.annuncio_accessorio_venditore(v_uid, p_cantina_id)');

select pg_temp.patch_015c('private.accessori_logistica_preventivo(uuid,integer,text,boolean,timestamp with time zone)'::regprocedure,
  'private.annuncio_accessorio_venditore(a.seller_id)',
  'private.annuncio_accessorio_venditore(a.seller_id, a.cantina_accessorio_id)');
select pg_temp.patch_015c('private.accessori_logistica_preventivo(uuid,integer,text,boolean,timestamp with time zone)'::regprocedure,
  'if v_v.ammesso is not true or v_spedizione',
  'if v_v.vendibile is not true or v_spedizione');

select pg_temp.patch_015c('public.accessori_checkout_crea(uuid,text)'::regprocedure,
  'private.annuncio_accessorio_venditore(a.seller_id);
  if v_v.ammesso is not true then',
  'private.annuncio_accessorio_venditore(a.seller_id, a.cantina_accessorio_id);
  if v_v.vendibile is not true then');

-- La vendita applicata dal nucleo B5B marca la riduzione della scorta: nello
-- storico e `vendita`, non una rettifica.
select pg_temp.patch_015c('private.accessori_ordine_vendita_applica(uuid,text,boolean)'::regprocedure,
  'update private.cantina_accessori
  set quantita = quantita - o.quantita,',
  'perform set_config(''vinae.accessori_vendita_scorta'', ''on'', true);
  update private.cantina_accessori
  set quantita = quantita - o.quantita,');
select pg_temp.patch_015c('private.accessori_ordine_vendita_applica(uuid,text,boolean)'::regprocedure,
  'where id = c.id;

  if p_modo = ''provider'' then',
  'where id = c.id;
  perform set_config(''vinae.accessori_vendita_scorta'', '''', true);

  if p_modo = ''provider'' then');

-- Il patrimonio personale non mostra le scorte commerciali.
select pg_temp.patch_015c('public.cantina_accessori_elenca(boolean)'::regprocedure,
  'where a.owner_id = v_uid
        and ((a.archiviato_at',
  'where a.owner_id = v_uid
        and a.inventario = ''personale''
        and ((a.archiviato_at');

-- ---------------------------------------------------------------------------
-- [4] Porte Partner (sottili: riusano le porte della Cantina e degli annunci)
-- ---------------------------------------------------------------------------

create function public.accessori_partner_stato()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.cantina_accessori_utente();
  v_p private.partners%rowtype;
begin
  select * into v_p from private.partners
  where titolare_id = v_uid order by (stato <> 'revocato'::public.partner_stato) desc, created_at desc limit 1;
  return jsonb_build_object(
    'partner_stato', v_p.stato,
    'scorte_abilitate', private.cantina_accessori_consentita(),
    'preparazione_annunci', private.annunci_accessori_consentita(),
    'pubblicazione_aperta', private.annunci_accessori_pubblicazione_aperta(),
    'vendita_partner', private.inventario_flag('vendita_partner'),
    'checkout_attivo', private.accessori_checkout_aperto()
  );
end;
$$;

create function public.accessori_partner_scorte_elenca(p_archiviati boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.cantina_accessori_utente();
begin
  if not private.cantina_accessori_consentita() then
    return '[]'::jsonb;
  end if;
  return coalesce((
    select jsonb_agg(
      private.cantina_accessorio_json(s.id) || jsonb_build_object(
        'inventario', 'commerciale',
        'impegnati', private.annuncio_accessorio_impegnati(s.id),
        'disponibili', greatest(s.quantita - private.annuncio_accessorio_impegnati(s.id), 0))
      order by s.created_at desc, s.id)
    from (
      select a.id, a.created_at, a.quantita
      from private.cantina_accessori a
      where a.owner_id = v_uid and a.inventario = 'commerciale'
        and ((a.archiviato_at is not null) = coalesce(p_archiviati, false))
      order by a.created_at desc, a.id
      limit 300
    ) s
  ), '[]'::jsonb);
end;
$$;

create function public.accessori_partner_scorta_salva(p_id uuid, p_dati jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.cantina_accessori_utente();
  v_p private.partners%rowtype;
  v_inv text;
  v_partner uuid;
  v_res jsonb;
begin
  if p_id is null or p_dati is null or jsonb_typeof(p_dati) <> 'object' then
    raise exception 'Dati non validi.' using errcode = '22023', hint = 'dati_non_validi';
  end if;
  if private.utente_stato_di(v_uid) <> 'attivo'::public.utente_stato then
    raise exception 'Account non abilitato.' using errcode = '42501', hint = 'utente_non_attivo';
  end if;
  -- Lock condiviso come `scorte_partner_aggiungi`: una sospensione concorrente
  -- attende, e un'aggiunta concorrente a una sospensione vede lo stato nuovo.
  select * into v_p from private.partners
  where titolare_id = v_uid and stato = 'attivo'::public.partner_stato for share;
  if v_p.id is null then
    raise exception 'Serve un Partner attivo.' using errcode = '42501', hint = 'partner_non_attivo';
  end if;

  select a.inventario, a.partner_id into v_inv, v_partner
  from private.cantina_accessori a where a.id = p_id and a.owner_id = v_uid;
  if v_inv is not null and (v_inv <> 'commerciale' or v_partner <> v_p.id) then
    raise exception 'Articolo non trovato.' using errcode = 'P0001', hint = 'non_trovato';
  end if;
  if v_inv is null then
    perform set_config('vinae.accessori_partner_porta', 'crea:' || v_uid::text || ':' || p_id::text, true);
  end if;

  v_res := public.cantina_accessori_salva(
    p_id, p_dati || jsonb_build_object('condizione', 'nuovo'));
  perform set_config('vinae.accessori_partner_porta', '', true);
  return v_res || jsonb_build_object('inventario', 'commerciale');
end;
$$;

create function public.accessori_partner_scorta_archivia(p_id uuid, p_archivia boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.cantina_accessori_utente();
begin
  if p_id is null or p_archivia is null then
    raise exception 'Dati non validi.' using errcode = '22023', hint = 'dati_non_validi';
  end if;
  if not exists (select 1 from private.cantina_accessori a
                 where a.id = p_id and a.owner_id = v_uid and a.inventario = 'commerciale') then
    raise exception 'Articolo non trovato.' using errcode = 'P0001', hint = 'non_trovato';
  end if;
  return public.cantina_accessori_archivia(p_id, p_archivia);
end;
$$;

create function public.accessori_partner_movimenti_elenca(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.cantina_accessori_utente();
begin
  if p_id is null then
    raise exception 'Dati non validi.' using errcode = '22023', hint = 'dati_non_validi';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'causale', m.causale, 'delta', m.delta, 'quantita_dopo', m.quantita_dopo, 'created_at', m.created_at)
      order by m.id desc)
    from (
      select x.* from private.accessori_partner_movimenti x
      join private.partners p on p.id = x.partner_id
      where x.cantina_accessorio_id = p_id and p.titolare_id = v_uid
      order by x.id desc limit 100
    ) m
  ), '[]'::jsonb);
end;
$$;

-- Chi vende un annuncio visibile, per distinguere un articolo nuovo di un
-- Partner da un articolo personale. Mai l'identita di un privato.
create function public.accessori_venditore_pubblico(p_annuncio uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  c private.cantina_accessori%rowtype;
  a private.annunci_accessori%rowtype;
begin
  if p_annuncio is null or not private.annuncio_accessorio_visibile(p_annuncio) then
    return null;
  end if;
  select * into a from private.annunci_accessori where id = p_annuncio;
  select * into c from private.cantina_accessori where id = a.cantina_accessorio_id;
  if c.inventario = 'commerciale' then
    return jsonb_build_object('classe', 'partner', 'nuovo', true, 'titolare_id', c.owner_id);
  end if;
  return jsonb_build_object('classe', 'privato', 'nuovo', false);
end;
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.accessori_partner_stato()',
    'public.accessori_partner_scorte_elenca(boolean)',
    'public.accessori_partner_scorta_salva(uuid, jsonb)',
    'public.accessori_partner_scorta_archivia(uuid, boolean)',
    'public.accessori_partner_movimenti_elenca(uuid)',
    'public.accessori_venditore_pubblico(uuid)'
  ] loop
    execute format('revoke all on function %s from public, anon, service_role', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  grant execute on function public.accessori_venditore_pubblico(uuid) to anon;
end;
$$;

comment on function public.accessori_partner_scorta_salva(uuid, jsonb) is
  'VPM-015C: crea o aggiorna una scorta commerciale del Partner ATTIVO del chiamante riusando cantina_accessori_salva (categoria, catalogo, foto, quantita). Condizione sempre nuovo.';
comment on function public.accessori_venditore_pubblico(uuid) is
  'VPM-015C: classe del venditore di un annuncio visibile (partner/privato). Nessuna identita di un privato.';
