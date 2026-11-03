-- Pulizia della prova REST/Storage 12zk. Il registro di audit e append-only
-- anche per il proprietario: solo qui, su stack locale e per le righe della
-- fixture, i trigger sono sospesi con session_replication_role. Riporta anche
-- gli interruttori al valore di partenza (spento). Ultima riga: residui
-- `utenti annunci snapshot categorie file segnalazioni audit registro notifiche`
-- (attesi tutti 0) e lo stato degli interruttori (atteso `f f f`).

begin;

do $$
begin
  if exists (select 1 from auth.users where coalesce(email, '') not like '%@e2e-12zk.test') then
    raise exception 'Guard 12zk E2E: il database contiene altri utenti, pulizia rifiutata.';
  end if;
end $$;

set local session_replication_role = replica;

delete from public.audit_log
 where attore_id::text like '12ab2000-%' or target_id in (select id from private.annunci_accessori where seller_id::text like '12ab2000-%');
delete from public.reports where reporter_id::text like '12ab2000-%';
delete from private.annunci_accessori_snapshot
 where annuncio_id in (select id from private.annunci_accessori where seller_id::text like '12ab2000-%');
-- VPM-015B5A / B4: ordini, preventivi congelati, dichiarazioni di logistica e il
-- servizio/tariffa di PROVA (provider `e2e_b5a` e `e2e_b5d`) creati dalla prova browser.
-- VPM-015QA-FINAL-B2-COMPLETION: le tabelle figlie degli ordini (pagamenti, contestazioni, resi, rimborsi,
-- eventi append-only, movimenti Partner) si scoprono dai vincoli di chiave esterna e si svuotano per le sole
-- righe discendenti da ordini/Partner della fixture, dalle foglie verso la radice. Vale solo qui: la guardia in
-- testa rifiuta qualunque database con utenti estranei alla fixture e i trigger append-only restano intatti sul
-- database di prodotto (sospesi solo in questa transazione).
create function pg_temp.e2e_elimina_figli(p_tabella regclass, p_colonna text, p_valori text[], p_profondita integer default 0, p_percorso text[] default '{}')
returns void language plpgsql as $f$
declare
  f record;
  g record;
  v_sotto text[];
begin
  if coalesce(array_length(p_valori, 1), 0) = 0 then return; end if;
  -- Cicli fra tabelle (es. Partner <-> inviti): una coppia tabella.colonna già nel percorso non si riscende.
  if (p_tabella::text || '.' || p_colonna) = any(p_percorso) then return; end if;
  if p_profondita > 8 then
    raise exception 'Pulizia E2E: catena di chiavi esterne oltre il limite (%): righe orfane non ammesse.', p_tabella;
  end if;
  for f in
    select c.conrelid::regclass as figlia, a.attname as col_figlia
      from pg_constraint c
      join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
      join pg_attribute r on r.attrelid = c.confrelid and r.attnum = c.confkey[1]
     where c.contype = 'f' and c.confrelid = p_tabella and c.conrelid <> c.confrelid
       and array_length(c.conkey, 1) = 1 and r.attname = p_colonna
       and (select n.nspname from pg_class k join pg_namespace n on n.oid = k.relnamespace where k.oid = c.conrelid)
           not in ('auth', 'storage')
       and c.conrelid <> 'public.profiles'::regclass
  loop
    for g in
      select distinct r2.attname as col_rif
        from pg_constraint c2
        join pg_attribute r2 on r2.attrelid = c2.confrelid and r2.attnum = c2.confkey[1]
       where c2.contype = 'f' and c2.confrelid = f.figlia and c2.conrelid <> c2.confrelid and array_length(c2.conkey, 1) = 1
    loop
      execute format('select coalesce(array_agg(%I::text), ''{}''::text[]) from %s where %I::text = any($1)',
                     g.col_rif, f.figlia, f.col_figlia) into v_sotto using p_valori;
      perform pg_temp.e2e_elimina_figli(f.figlia, g.col_rif, v_sotto, p_profondita + 1,
                                        p_percorso || (p_tabella::text || '.' || p_colonna));
    end loop;
    execute format('delete from %s where %I::text = any($1)', f.figlia, f.col_figlia) using p_valori;
  end loop;
end;
$f$;

-- Eventi del fornitore SIMULATI dalle prove (deduplica del webhook): identificativi `evt_e2e_*`, mai reali.
delete from public.payment_provider_events where event_id like 'evt_e2e\_%';
select pg_temp.e2e_elimina_figli('private.accessori_ordini'::regclass, 'id',
  coalesce(array(select id::text from private.accessori_ordini
                  where buyer_id::text like '12ab2000-%' or seller_id::text like '12ab2000-%'), '{}'::text[]));
-- Prove delle contestazioni (bucket privato, percorso `<ordine>/<utente>/<file>`).
delete from storage.objects where bucket_id = 'dispute-evidence' and name like '%/12ab2000-%';
delete from private.accessori_ordini where buyer_id::text like '12ab2000-%' or seller_id::text like '12ab2000-%';
delete from private.accessori_logistica_preventivi where buyer_id::text like '12ab2000-%';
delete from private.annunci_accessori_logistica
 where annuncio_id in (select id from private.annunci_accessori where seller_id::text like '12ab2000-%');
delete from private.accessori_logistica_tariffe where provider_code in ('e2e_b5a', 'e2e_b5d');
delete from private.logistics_service_pudo_networks
 where service_definition_id in (select id from private.logistics_service_definitions where provider_code in ('e2e_b5a', 'e2e_b5d'));
delete from private.logistics_service_capabilities
 where service_definition_id in (select id from private.logistics_service_definitions where provider_code in ('e2e_b5a', 'e2e_b5d'));
delete from private.logistics_service_definitions where provider_code in ('e2e_b5a', 'e2e_b5d');
delete from private.logistics_pudo_networks where provider_code in ('e2e_b5a', 'e2e_b5d');
delete from private.annunci_accessori where seller_id::text like '12ab2000-%';
delete from private.cantina_accessori where owner_id::text like '12ab2000-%';
delete from storage.objects where bucket_id = 'cantina-accessori-foto' and name like '12ab2000-%';
-- Schede di catalogo create dalla prova Partner (collegamento facoltativo della scorta).
select pg_temp.e2e_elimina_figli('private.accessori'::regclass, 'id',
  coalesce(array(select id::text from private.accessori where creato_da::text like '12ab2000-%'), '{}'::text[]));
delete from private.accessori where creato_da::text like '12ab2000-%';
-- Partner della fixture: prima le righe che li referenziano (inviti, movimenti, audit), poi il Partner.
delete from private.accessori_partner_movimenti
 where partner_id in (select id from private.partners where titolare_id::text like '12ab2000-%');
select pg_temp.e2e_elimina_figli('private.partners'::regclass, 'id',
  coalesce(array(select id::text from private.partners where titolare_id::text like '12ab2000-%'), '{}'::text[]));
delete from private.partners where titolare_id::text like '12ab2000-%';
select pg_temp.e2e_elimina_figli('private.partner_inviti'::regclass, 'id',
  coalesce(array(select id::text from private.partner_inviti where creato_da::text like '12ab2000-%'), '{}'::text[]));
delete from private.partner_eventi where attore_id::text like '12ab2000-%';
delete from private.partner_inviti where creato_da::text like '12ab2000-%';
delete from private.annunci_accessori_categorie_pubblicabili where approvata_da::text like '12ab2000-%';
delete from private.accessori_registro where admin_id::text like '12ab2000-%';
delete from public.notifications where recipient_id::text like '12ab2000-%';
delete from private.rate_limit_buckets where subject like 'user:12ab2000-%';
delete from public.user_roles where user_id::text like '12ab2000-%';
delete from public.profiles where id::text like '12ab2000-%';
delete from auth.identities where user_id::text like '12ab2000-%';
delete from auth.users where email like '%@e2e-12zk.test';

update private.annunci_accessori_impostazioni
   set preparazione_attiva = false, pubblicazione_attiva = false, aggiornato_da = null;
update private.cantina_accessori_impostazioni
   set funzione_attiva = false, aggiornato_da = null;
update private.accessori_logistica_impostazioni
   set logistica_attiva = false, aggiornato_da = null;
update private.accessori_checkout_impostazioni
   set checkout_attivo = false, aggiornato_da = null;
-- VPM-015QA-FINAL-B2-COMPLETION: lo spec Partner accende `vendita_partner` (solo qui, a mano, come la griglia 12zr).
update private.inventario_impostazioni set vendita_partner = false;
update private.accessori_impostazioni set visibilita_pubblica = false, aggiornato_da = null;

set local session_replication_role = origin;

commit;

select
  (select count(*) from auth.users where email like '%@e2e-12zk.test'),
  (select count(*) from private.annunci_accessori where seller_id::text like '12ab2000-%'),
  (select count(*) from private.annunci_accessori_snapshot s where not exists (select 1 from private.annunci_accessori a where a.id = s.annuncio_id)),
  (select count(*) from private.annunci_accessori_categorie_pubblicabili),
  (select count(*) from storage.objects where bucket_id = 'cantina-accessori-foto' and name like '12ab2000-%'),
  (select count(*) from public.reports where reporter_id::text like '12ab2000-%'),
  (select count(*) from public.audit_log where attore_id::text like '12ab2000-%'),
  (select count(*) from private.accessori_registro where admin_id::text like '12ab2000-%'),
  (select count(*) from public.notifications where recipient_id::text like '12ab2000-%'),
  (select preparazione_attiva::text from private.annunci_accessori_impostazioni)
    || ' ' || (select pubblicazione_attiva::text from private.annunci_accessori_impostazioni)
    || ' ' || (select funzione_attiva::text from private.cantina_accessori_impostazioni);
