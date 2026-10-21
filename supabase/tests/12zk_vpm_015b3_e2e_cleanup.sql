-- Pulizia della prova REST/Storage 12zk. Il registro di audit e append-only
-- anche per il proprietario: solo qui, su stack locale e per le righe della
-- fixture, i trigger sono sospesi con session_replication_role. Riporta anche
-- gli interruttori al valore di partenza (spento). Ultima riga: residui
-- `utenti annunci snapshot categorie file segnalazioni audit registro notifiche`
-- (attesi tutti 0) e lo stato degli interruttori (atteso `f f f`).

begin;

do $$
begin
  if exists (select 1 from auth.users where email not like '%@e2e-12zk.test') then
    raise exception 'Guard 12zk E2E: il database contiene altri utenti, pulizia rifiutata.';
  end if;
end $$;

set local session_replication_role = replica;

delete from public.audit_log
 where attore_id::text like '12ab2000-%' or target_id in (select id from private.annunci_accessori where seller_id::text like '12ab2000-%');
delete from public.reports where reporter_id::text like '12ab2000-%';
delete from private.annunci_accessori_snapshot
 where annuncio_id in (select id from private.annunci_accessori where seller_id::text like '12ab2000-%');
delete from private.annunci_accessori where seller_id::text like '12ab2000-%';
delete from private.cantina_accessori where owner_id::text like '12ab2000-%';
delete from storage.objects where bucket_id = 'cantina-accessori-foto' and name like '12ab2000-%';
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
