-- Pulizia dei domini critici della suite browser (VPM-018-E2E-CRIT-01): vino in
-- Cantina, annunci, proposte, ordini, conversazioni e messaggi degli utenti della
-- fixture, più le righe di Auth che la pulizia 12zk non tocca (sessioni, token,
-- l'utente registrato dal browser con un id fuori dal prefisso `12ab2000-`).
--
-- Si esegue SOLO attraverso `eseguiSql` (marcatore e token di corsa verificati
-- nella stessa sessione psql) e PRIMA della pulizia 12zk, che resta invariata:
-- qui si tolgono le righe che legano i profili con vincoli `restrict`
-- (ordini, conversazioni, messaggi) e che quella pulizia non conosce.
-- Come in 12zk, i trigger append-only sono sospesi con session_replication_role
-- solo in questa transazione e solo per righe discendenti da utenti della
-- fixture; le figlie si scoprono dai vincoli di chiave esterna e si eliminano
-- dalle foglie verso la radice (in modalità replica nessun ON DELETE agisce).

begin;

do $$
begin
  if exists (select 1 from auth.users where coalesce(email, '') not like '%@e2e-12zk.test') then
    raise exception 'Pulizia domini critici: il database contiene altri utenti, pulizia rifiutata.';
  end if;
end $$;

set local session_replication_role = replica;

create temporary table e2e_utenti on commit drop as
  select id from auth.users where email like '%@e2e-12zk.test';

create function pg_temp.e2e_elimina_figli(p_tabella regclass, p_colonna text, p_valori text[], p_profondita integer default 0, p_percorso text[] default '{}')
returns void language plpgsql as $f$
declare
  f record;
  g record;
  v_sotto text[];
begin
  if coalesce(array_length(p_valori, 1), 0) = 0 then return; end if;
  if (p_tabella::text || '.' || p_colonna) = any(p_percorso) then return; end if;
  if p_profondita > 8 then
    raise exception 'Pulizia domini critici: catena di chiavi esterne oltre il limite (%).', p_tabella;
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

-- Una radice: prima le discendenti, poi le righe stesse.
create function pg_temp.e2e_elimina_radice(p_tabella regclass, p_valori text[])
returns void language plpgsql as $f$
begin
  perform pg_temp.e2e_elimina_figli(p_tabella, 'id', p_valori);
  execute format('delete from %s where id::text = any($1)', p_tabella) using p_valori;
end;
$f$;

select pg_temp.e2e_elimina_radice('public.orders', coalesce(array(
  select id::text from public.orders
   where buyer_id in (select id from e2e_utenti) or seller_id in (select id from e2e_utenti)), '{}'));
select pg_temp.e2e_elimina_radice('public.proposals', coalesce(array(
  select id::text from public.proposals
   where buyer_id in (select id from e2e_utenti) or seller_id in (select id from e2e_utenti)), '{}'));
select pg_temp.e2e_elimina_radice('public.conversations', coalesce(array(
  select id::text from public.conversations
   where participant_low in (select id from e2e_utenti) or participant_high in (select id from e2e_utenti)), '{}'));
select pg_temp.e2e_elimina_radice('public.listings', coalesce(array(
  select id::text from public.listings where seller_id in (select id from e2e_utenti)), '{}'));
select pg_temp.e2e_elimina_radice('public.bottle_units', coalesce(array(
  select id::text from public.bottle_units where owner_id in (select id from e2e_utenti)), '{}'));
select pg_temp.e2e_elimina_radice('private.cellar_lotti', coalesce(array(
  select id::text from private.cellar_lotti where owner_id in (select id from e2e_utenti)), '{}'));
select pg_temp.e2e_elimina_radice('public.cellar_environments', coalesce(array(
  select id::text from public.cellar_environments where owner_id in (select id from e2e_utenti)), '{}'));
-- Vini del catalogo creati dalla fixture (i vini di partenza hanno un altro autore).
select pg_temp.e2e_elimina_radice('public.wines', coalesce(array(
  select id::text from public.wines where creato_da in (select id from e2e_utenti)), '{}'));

delete from public.notifications
 where recipient_id in (select id from e2e_utenti) or destination_profile_id in (select id from e2e_utenti);
delete from private.checkout_consegne where buyer_id in (select id from e2e_utenti);
delete from private.indirizzi where user_id in (select id from e2e_utenti);
delete from private.cellar_public_settings where owner_id in (select id from e2e_utenti);
delete from private.cellar_follows
 where owner_id in (select id from e2e_utenti) or follower_id in (select id from e2e_utenti);
delete from private.logistics_quotes where user_id in (select id from e2e_utenti);
delete from private.utenti_paese where user_id in (select id from e2e_utenti);
delete from public.balance_movimenti where owner_id in (select id from e2e_utenti);
delete from public.balance_reservations where owner_id in (select id from e2e_utenti);
delete from public.balance_withdrawals where owner_id in (select id from e2e_utenti);
delete from public.balance_accounts where owner_id in (select id from e2e_utenti);
delete from public.audit_log where attore_id in (select id from e2e_utenti);
delete from private.rate_limit_buckets where subject in (select 'user:' || id::text from e2e_utenti);
-- Oggetti di Storage caricati dagli utenti della fixture (foto di annunci e Cantina).
delete from storage.objects where owner in (select id from e2e_utenti) or owner_id in (select id::text from e2e_utenti);

-- Utenti registrati dal browser: id casuale, quindi fuori dal prefisso che la pulizia 12zk conosce.
delete from public.user_roles
 where user_id in (select id from e2e_utenti) and user_id::text not like '12ab2000-%';
delete from public.profiles
 where id in (select id from e2e_utenti) and id::text not like '12ab2000-%';
-- Righe di Auth che in modalità replica non seguirebbero l'utente (nessun ON DELETE CASCADE).
delete from auth.refresh_tokens where user_id in (select id::text from e2e_utenti);
delete from auth.mfa_amr_claims
 where session_id in (select id from auth.sessions where user_id in (select id from e2e_utenti));
delete from auth.sessions where user_id in (select id from e2e_utenti);
delete from auth.one_time_tokens where user_id in (select id from e2e_utenti);
delete from auth.mfa_factors where user_id in (select id from e2e_utenti);
delete from auth.identities where user_id in (select id from e2e_utenti);

set local session_replication_role = origin;

commit;
