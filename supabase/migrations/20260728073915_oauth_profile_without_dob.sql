-- Fase 5b — Google/Facebook OAuth: rendere creabile un profilo senza data di
-- nascita, e senza collisioni di username.
--
-- PERCHÉ SERVE (verificato, non ipotizzato). Il trigger handle_new_user() di
-- Fase 5a inserisce in public.profiles leggendo `dob` da
-- auth.users.raw_user_meta_data. Un signup OAuth non contiene nessun `dob`:
-- Google e Facebook non lo forniscono e l'utente non compila il form email.
-- Con `dob date not null` l'INSERT del trigger viola il vincolo, il trigger
-- solleva errore e l'intera creazione dell'utente va in rollback: il primo
-- login social fallirebbe con "Database error saving new user".
-- Riprodotto chiamando /auth/v1/signup senza `dob` nei metadati:
--   23502 — null value in column "dob" of relation "profiles"
--           violates not-null constraint            (HTTP 500)
--
-- COSA NON CAMBIA. Il CHECK 18+ resta identico e resta la barriera
-- autoritativa lato server: in PostgreSQL un CHECK è violato solo quando
-- valuta FALSE, mentre con dob NULL valuta NULL e quindi passa. Perciò
-- togliere il NOT NULL non indebolisce affatto il controllo sull'età per le
-- date effettivamente dichiarate — le respinge esattamente come prima.
--
-- COME SI RICHIUDE IL BUCO. Un profilo senza `dob` non è uno stato accettabile
-- a regime: è uno stato transitorio fra il primo login social e la
-- dichiarazione dell'età. A chiuderlo pensa l'applicazione, che rimanda a
-- /completa-profilo chiunque abbia una sessione e `dob` vuoto prima di dare
-- accesso al resto del sito (src/components/vinea/AgeGate.tsx).
-- Resta una dichiarazione AUTO-RIFERITA, non una verifica documentale, e
-- richiede validazione legale prima del lancio pubblico reale — vedi
-- "Cosa NON è ancora deciso" in docs/ROADMAP_V1.md.

alter table public.profiles
  alter column dob drop not null;

comment on column public.profiles.dob is
  'Dichiarazione auto-riferita di data di nascita. Il CHECK garantisce >= 18 '
  'anni lato server ma non costituisce verifica d''identità. Può essere NULL '
  'solo nella finestra fra il primo accesso OAuth e la dichiarazione dell''età '
  'raccolta da /completa-profilo.';

-- ---------------------------------------------------------------------------
-- handle_new_user(): username univoco anche senza metadati
-- ---------------------------------------------------------------------------
-- Secondo problema dello stesso flusso: profiles.username è UNIQUE e per un
-- utente OAuth il trigger ricade su split_part(email, '@', 1). Due utenti
-- social con la stessa parte locale (mario@gmail.com e mario@outlook.com)
-- generano lo stesso username e il secondo login fallisce con una violazione
-- di unicità — di nuovo un "Database error saving new user", stavolta per un
-- utente che non ha fatto nulla di sbagliato.
--
-- Qui si aggiunge un suffisso numerico progressivo al primo username libero.
-- Il nome resta modificabile dall'utente: è un valore di partenza, non
-- un'identità definitiva.

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
  while exists (select 1 from public.profiles where username = candidato) loop
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
