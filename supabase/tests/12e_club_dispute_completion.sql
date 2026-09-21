-- Verifica read-only del completamento Club e contestazioni.
-- Restituisce una riga per invariante; tutte devono avere passed = true.

with checks(id, descrizione, passed, detail) as (
  values
    (1, 'RLS attiva sui quattro registri privati',
      (select count(*) = 4 from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname in (
         'club_management_events', 'dispute_admin_notes',
         'dispute_decisions', 'dispute_case_events'
       ) and c.relrowsecurity),
      'attese 4 tabelle con RLS'),
    (2, 'anon non legge le viste di gestione',
      not has_table_privilege('anon', 'public.club_management_clubs', 'select')
      and not has_table_privilege('anon', 'public.club_management_members', 'select')
      and not has_table_privilege('anon', 'public.moderation_dispute_admin_notes', 'select'),
      'atteso SELECT anon=false'),
    (3, 'authenticated legge soltanto le viste filtrate',
      has_table_privilege('authenticated', 'public.club_management_clubs', 'select')
      and has_table_privilege('authenticated', 'public.moderation_dispute_admin_notes', 'select')
      and not has_table_privilege('authenticated', 'public.dispute_admin_notes', 'select'),
      'viste=true, tabella note=false'),
    (4, 'la nomina moderatore e raggiungibile solo da authenticated',
      has_function_privilege('authenticated', 'public.club_moderatore_imposta(text,uuid,boolean)', 'execute')
      and not has_function_privilege('anon', 'public.club_moderatore_imposta(text,uuid,boolean)', 'execute')
      and not has_function_privilege('service_role', 'public.club_moderatore_imposta(text,uuid,boolean)', 'execute'),
      'authenticated=true; anon e service_role=false'),
    (5, 'la decisione disputa e raggiungibile solo da authenticated',
      has_function_privilege('authenticated', 'public.moderazione_contestazione_decidi(uuid,text,text,text)', 'execute')
      and not has_function_privilege('anon', 'public.moderazione_contestazione_decidi(uuid,text,text,text)', 'execute')
      and not has_function_privilege('service_role', 'public.moderazione_contestazione_decidi(uuid,text,text,text)', 'execute'),
      'authenticated=true; anon e service_role=false'),
    (6, 'owner e Club approvato sono controllati nella porta moderatori',
      (select pg_get_functiondef('public.club_moderatore_imposta(text,uuid,boolean)'::regprocedure)
        like '%m.role = ''proprietario'' and c.approval_status = ''approvato''%'),
      'controllo server-side sullo stesso club'),
    (7, 'la decisione richiede admin assegnato e lock di riga',
      (select pg_get_functiondef('public.moderazione_contestazione_decidi(uuid,text,text,text)'::regprocedure)
        like '%public.has_role(v_uid, ''admin'')%for update%assigned_to is distinct from v_uid%'),
      'admin + FOR UPDATE + assignee'),
    (8, 'la decisione non scrive tabelle economiche',
      (select pg_get_functiondef('public.moderazione_contestazione_decidi(uuid,text,text,text)'::regprocedure)
        !~* 'update[[:space:]]+public\.(orders|payouts|payments)'),
      'nessun update economico'),
    (9, 'i registri nuovi sono append-only',
      (select count(*) = 12 from pg_trigger
       where not tgisinternal and tgname in (
         'club_management_events_no_update', 'club_management_events_no_delete', 'club_management_events_no_truncate',
         'dispute_admin_notes_no_update', 'dispute_admin_notes_no_delete', 'dispute_admin_notes_no_truncate',
         'dispute_decisions_no_update', 'dispute_decisions_no_delete', 'dispute_decisions_no_truncate',
         'dispute_case_events_no_update', 'dispute_case_events_no_delete', 'dispute_case_events_no_truncate'
       )),
      'attesi 12 trigger'),
    (10, 'le parti vedono timeline ma non note private',
      has_table_privilege('authenticated', 'public.dispute_case_timeline', 'select')
      and not has_table_privilege('authenticated', 'public.dispute_admin_notes', 'select'),
      'timeline=true, note private=false')
)
select id, descrizione, passed, detail
from checks
order by id;
