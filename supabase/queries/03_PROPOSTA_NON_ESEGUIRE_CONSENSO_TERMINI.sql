-- ===========================================================================
-- PROPOSTA DI MIGRAZIONE - NON ESEGUIRE SENZA AUTORIZZAZIONE ESPLICITA
-- Registrazione dell'accettazione di Termini e Privacy su public.profiles
-- ===========================================================================
--
-- QUESTO FILE NON E STATO ESEGUITO DA NESSUNA PARTE e non deve esserlo finche
-- non arriva un'autorizzazione esplicita in sessione. Non e nemmeno una
-- migrazione ancora: e una proposta scritta per intero, cosi che la si possa
-- valutare sul testo esatto invece che su una descrizione.
--
-- DOVE STA, E PERCHE NON IN supabase/migrations/.
-- Perche li il merge e il gate di deploy (decisione 7.10): la PR la
-- applicherebbe da sola al progetto reale nell'istante dello squash, che e
-- esattamente cio che l'autorizzazione separata deve poter fermare. Stessa
-- ragione, e stessa cartella, della proposta di fixture della 12a.
--
-- ---------------------------------------------------------------------------
-- PERCHE NON E' GIA' DENTRO LA PR
-- ---------------------------------------------------------------------------
--
-- 1. OGGI IL CONSENSO NON E' REGISTRATO DA NESSUNA PARTE, NEMMENO PER EMAIL.
--    Nel form di registrazione (`registrati/page-client.tsx`) la casella
--    "Accetto i Termini e la Privacy di Vinea" e' un requisito di validita'
--    del pulsante e nient'altro: non viene inviata a `registra()` e non
--    raggiunge nessuna colonna. La schermata /completa-profilo ora la chiede
--    allo stesso modo, quindi i due percorsi sono PARI. Introdurre la colonna
--    per il solo percorso social avrebbe prodotto un'asimmetria peggiore del
--    buco che chiude: utenti Google con una prova di consenso e utenti email
--    senza, sulla stessa piattaforma e per lo stesso testo.
--
-- 2. IL CONTENUTO DI QUESTA COLONNA E' UNA DECISIONE LEGALE, NON TECNICA.
--    Cosa vada conservato - se basti l'istante, o servano anche la versione
--    del testo accettato e la prova di quale testo fosse in vigore quel
--    giorno - e' precisamente quello che la revisione legale ancora aperta
--    (§9 di docs/PHASE_11_AI_EXTENSIONS_SPEC.md) deve dire. Scegliere adesso
--    significherebbe fissare in uno schema una risposta che nessuno ha dato,
--    e doverla migrare di nuovo dopo. Le cinque domande della §9.4 sono
--    ancora tutte e cinque senza risposta.
--
-- Se la revisione risponde "basta l'istante", la proposta e' questa e si
-- applica cosi'. Se risponde "serve anche la versione del testo", la forma
-- giusta e' un'altra - verosimilmente una tabella collegata con una riga per
-- accettazione, perche' un utente puo' accettare piu' versioni nel tempo e
-- una colonna sola le sovrascriverebbe. Le due varianti sono in fondo.
--
-- ---------------------------------------------------------------------------
-- VARIANTE A - una colonna, se basta l'istante dell'accettazione
-- ---------------------------------------------------------------------------
-- Additiva e annullabile: le righe esistenti restano valide con NULL, che si
-- legge "consenso non registrato" e non "consenso negato". Nessun backfill,
-- perche' inventare una data di accettazione per chi si e' registrato prima
-- che la colonna esistesse sarebbe fabbricare la prova che la colonna serve a
-- conservare.

alter table public.profiles
  add column terms_accepted_at timestamptz;

comment on column public.profiles.terms_accepted_at is
  'Istante in cui l''utente ha accettato Termini e Privacy. NULL significa '
  '"non registrato" - anche per i profili creati prima dell''introduzione '
  'della colonna - e mai "rifiutato". Non e'' una prova di quale testo fosse '
  'in vigore in quel momento: se serve anche quella, la forma corretta e'' la '
  'variante B.';

-- La colonna ha una regola di dominio dietro - si scrive una volta, al
-- consenso, e non si riscrive - quindi per la TERZA REGOLA DI ESPOSIZIONE non
-- entra nel GRANT del client. Il GRANT UPDATE per colonna della 9b va
-- ridichiarato per intero, perche' e' un elenco e non un insieme a cui si
-- aggiunge: l'elenco sotto e' quello della 9b, INVARIATO, e la colonna nuova
-- NON vi compare.
revoke update on public.profiles from authenticated;
grant update (
  username, bio, citta, provincia, esperienza, avatar_url, dob, obiettivi
) on public.profiles to authenticated;

-- Unica porta di scrittura, sul modello di `listings.stato` (6a) e delle
-- quattro colonne di moderazione (9b). `auth.uid()` e non un parametro: chi
-- chiama puo' registrare il consenso solo per se stesso.
create or replace function public.consenso_termini_registra()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Nessuna sessione attiva.' using errcode = '42501';
  end if;

  -- Idempotente: la prima accettazione e' quella che conta e non viene
  -- sovrascritta da un secondo passaggio sulla stessa schermata.
  update public.profiles
     set terms_accepted_at = coalesce(terms_accepted_at, now())
   where id = auth.uid();
end;
$$;

revoke execute on function public.consenso_termini_registra() from public, anon;
grant execute on function public.consenso_termini_registra() to authenticated;

-- ---------------------------------------------------------------------------
-- VARIANTE B - tabella collegata, se serve anche QUALE testo e' stato accettato
-- ---------------------------------------------------------------------------
-- NON eseguire insieme alla A: sono alternative, non passaggi successivi.
-- Scritta qui perche' la differenza fra le due non e' di gusto: la A non puo'
-- rispondere a "quale versione dei termini aveva accettato questo utente nel
-- marzo 2026", che e' la domanda a cui di solito serve rispondere.
--
-- create table public.consensi_termini (
--   id           bigint generated always as identity primary key,
--   user_id      uuid not null references auth.users (id) on delete cascade,
--   versione     text not null,
--   accettato_at timestamptz not null default now(),
--   unique (user_id, versione)
-- );
--
-- La versione in vigore va decisa e conservata da qualche parte: una costante
-- nel codice e' sufficiente solo finche' nessuno deve dimostrare che quel
-- giorno il testo era quello. Questa e' di nuovo la domanda della revisione
-- legale, non una scelta di schema.
