-- Uno username identifica un solo profilo anche quando cambia soltanto la
-- combinazione di maiuscole e minuscole. Gli username esistenti restano
-- invariati: eventuali collisioni richiedono una decisione esplicita sui dati.

do $$
begin
  if exists (
    select lower(username)
    from public.profiles
    group by lower(username)
    having count(*) > 1
  ) then
    raise exception using
      errcode = '23505',
      message = 'Cannot enforce case-insensitive username uniqueness: public.profiles contains usernames that differ only by letter case; resolve those data collisions manually.';
  end if;
end;
$$;

create unique index profiles_username_lower_key
  on public.profiles (lower(username));

-- Mantiene il candidato originale e i suffissi _1, _2, ... del trigger
-- esistente, ma considera occupato anche lo stesso nome scritto con un case
-- diverso.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  base_username text;
  candidato text;
  tentativo int := 0;
begin
  base_username := coalesce(
    nullif(new.raw_user_meta_data ->> 'username', ''),
    nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
    'utente'
  );

  candidato := base_username;
  while exists (
    select 1
    from public.profiles
    where lower(username) = lower(candidato)
  ) loop
    tentativo := tentativo + 1;
    candidato := base_username || '_' || tentativo::text;
  end loop;

  insert into public.profiles (id, username, dob)
  values (
    new.id,
    candidato,
    -- NULL per gli accessi OAuth: la data verrà dichiarata da
    -- /completa-profilo prima di poter usare il resto del sito.
    nullif(new.raw_user_meta_data ->> 'dob', '')::date
  );
  return new;
end;
$$;
