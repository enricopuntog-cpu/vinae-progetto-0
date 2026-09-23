-- Verifica read-only delle correzioni 20260923160000 (audit E2E 12g).
-- Restituisce una riga per invariante; tutte devono avere passed = true.
-- Le prove comportamentali stanno in 12g_club_dispute_e2e.mjs.

with checks(id, descrizione, passed) as (
  values
    (1, 'policy eventi: ramo admin fuori dalla sottoquery sulle tabelle RLS',
      (select qual ~ '^\(has_role\(' from pg_policies
       where schemaname = 'public' and tablename = 'dispute_events'
         and policyname = 'disputes_events_participants_or_admin_select')),
    (2, 'policy prove: ramo admin fuori dalla sottoquery sugli ordini',
      (select qual ~ 'dispute-evidence.*AND \(has_role\(' from pg_policies
       where schemaname = 'storage' and tablename = 'objects'
         and policyname = 'dispute_evidence_participants_select')),
    (3, 'DELETE delle prove escluso per i percorsi depositati',
      (select qual like '%prova_contestazione_depositata(name)%' from pg_policies
       where schemaname = 'storage' and tablename = 'objects'
         and policyname = 'dispute_evidence_owner_delete')),
    (4, 'helper prove SECURITY DEFINER, eseguibile solo da authenticated',
      (select p.prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'private' and p.proname = 'prova_contestazione_depositata')
      and has_function_privilege('authenticated', 'private.prova_contestazione_depositata(text)', 'execute')
      and not has_function_privilege('anon', 'private.prova_contestazione_depositata(text)', 'execute')),
    (5, 'la risposta del venditore avanza solo da attesa_venditore',
      (select pg_get_functiondef('public.contestazione_venditore_rispondi(uuid,text,text,text[])'::regprocedure)
        like '%when lifecycle_status = ''attesa_venditore''::public.dispute_lifecycle_status%else lifecycle_status%')),
    (6, 'etichetta diversa su link approvato torna in attesa',
      (select pg_get_functiondef('public.club_link_proponi(text,text,text,text)'::regprocedure)
        like '%label is not distinct from excluded.label%returning id, status into v_id, v_status%')),
    (7, 'porte ridefinite ancora chiuse ad anon',
      not has_function_privilege('anon', 'public.contestazione_venditore_rispondi(uuid,text,text,text[])', 'execute')
      and not has_function_privilege('anon', 'public.club_link_proponi(text,text,text,text)', 'execute')
      and has_function_privilege('authenticated', 'public.club_link_proponi(text,text,text,text)', 'execute'))
)
select id, descrizione, passed from checks order by id;
