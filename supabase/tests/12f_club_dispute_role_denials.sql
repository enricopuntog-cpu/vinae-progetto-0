-- Verifiche comportamentali negative. Nessuna fixture e nessuna scrittura persistente.
begin;

set local role authenticated;
select set_config('request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000001', true);

do $$
declare v_denied boolean;
begin
  v_denied := false;
  begin
    perform public.moderazione_contestazione_decidi(
      '00000000-0000-4000-8000-000000000002', 'respinta', 'Motivo di prova', null);
  exception when insufficient_privilege then v_denied := true;
  end;
  if not v_denied then raise exception 'Utente normale ha deciso una contestazione'; end if;

  v_denied := false;
  begin
    perform public.club_moderatore_imposta('club-inesistente',
      '00000000-0000-4000-8000-000000000002', true);
  exception when insufficient_privilege then v_denied := true;
  end;
  if not v_denied then raise exception 'Utente normale ha nominato un moderatore'; end if;

  v_denied := false;
  begin
    execute 'select count(*) from public.dispute_admin_notes';
  exception when insufficient_privilege then v_denied := true;
  end;
  if not v_denied then raise exception 'Utente normale ha letto note private'; end if;
end $$;

reset role;
set local role anon;

do $$
declare v_denied boolean := false;
begin
  begin
    perform public.moderazione_contestazione_decidi(
      '00000000-0000-4000-8000-000000000002', 'respinta', 'Motivo di prova', null);
  exception when insufficient_privilege then v_denied := true;
  end;
  if not v_denied then raise exception 'Anon ha eseguito la decisione'; end if;
end $$;

reset role;
select pg_get_constraintdef(oid) like '%2000%' as note_limit_aligned
from pg_constraint
where conrelid = 'public.disputes'::regclass
  and conname = 'disputes_esito_nota_check';

rollback;
