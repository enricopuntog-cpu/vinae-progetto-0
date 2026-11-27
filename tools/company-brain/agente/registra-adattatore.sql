-- WI-016 — registrazione di UN adattatore di ricerca con la propria credenziale, legato a UNA fonte già autorizzata.
-- Nasce SPENTO. Solo il proprietario del database.
-- psql … -X -v ON_ERROR_STOP=1 -v adattatore=consorzio_x -v ruolo=vinea_research_consorzio_x -v fonte=CODICE-FONTE \
--        -f tools/company-brain/agente/registra-adattatore.sql
-- Poi, MAI in un file o in chat:  \password vinea_research_consorzio_x
-- Accensione (dopo il gate):      update catalog.research_adapters set enabled = true where adapter_key = 'consorzio_x';
-- Arresto immediato:              select brain.suspend('globale', 'tutto', '<motivo>', '<chi>');
--                            oppure update catalog.research_adapters set enabled = false where adapter_key = 'consorzio_x';
begin;
set local lock_timeout = '10s';
create role :"ruolo" login inherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls connection limit 2;
alter role :"ruolo" set statement_timeout = '30s';
alter role :"ruolo" set lock_timeout = '5s';
alter role :"ruolo" set idle_in_transaction_session_timeout = '30s';
grant research_ingest to :"ruolo";
-- fallisce (nessuna riga, quindi errore sotto) se la fonte non è autorizzata e verificata
insert into catalog.research_adapters (adapter_key, db_role, source_id)
select :'adattatore', :'ruolo', s.id from catalog.sources s
 where s.code = :'fonte' and s.authorization_status = 'authorized' and s.verified_at is not null;
select 1 / (select count(*) from catalog.research_adapters where adapter_key = :'adattatore')::integer as fonte_autorizzata;
commit;
select adapter_key, db_role, enabled from catalog.research_adapters where adapter_key = :'adattatore';
