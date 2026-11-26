-- WI-015 — registrazione di UN agente con la propria credenziale. Nasce SPENTO: si accende a parte, dopo il suo gate.
-- psql … -X -v ON_ERROR_STOP=1 -v agente=catalog_manager -v ruolo=vinea_agent_catalog_manager \
--        -v tipi=catalogo.proposta -f tools/company-brain/agente/registra.sql
-- Poi, MAI in un file o in chat:  \password vinea_agent_catalog_manager
-- Accensione (dopo il gate):      update brain.agents set enabled = true where agent_key = 'catalog_manager';
-- Tipi previsti: catalog_manager → catalogo.proposta; data_quality → qualita.scansione;
--                technical_monitor → tecnico.segnale
begin;
set local lock_timeout = '10s';
create role :"ruolo" login inherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls connection limit 2;
alter role :"ruolo" set statement_timeout = '30s';
alter role :"ruolo" set lock_timeout = '5s';
alter role :"ruolo" set idle_in_transaction_session_timeout = '30s';
grant brain_worker to :"ruolo";
insert into brain.agents (agent_key, descrizione, db_role, enabled, task_types)
values (:'agente', 'Agente ' || :'agente', :'ruolo', false, string_to_array(:'tipi', ','));
commit;
select agent_key, db_role, enabled, task_types from brain.agents where agent_key = :'agente';
