-- ===========================================================================
-- Profilo pubblico: spunta e qualifiche professionali approvate (D1)
-- ===========================================================================
--
-- La 20260825180000 ha creato `public.profilo_pubblico(uuid)` senza alcun
-- segnale di fiducia, e ha scritto perche': «la spunta che il profilo mostrera'
-- un giorno dipendera' da qualifiche professionali approvate, che sono un
-- dominio non ancora aperto. Finche' quel dominio non esiste, un campo
-- `verificato` sarebbe una promessa senza contenuto». La 20260827160000 ha
-- aperto quel dominio. Questo file mantiene la promessa.
--
-- ---------------------------------------------------------------------------
-- PERCHE' QUI E NON IN UNA FUNZIONE NUOVA
-- ---------------------------------------------------------------------------
--
-- L'alternativa era una RPC pubblica di badge, magari accettante un elenco di
-- uuid per servire delle schede. E' stata scartata per due ragioni distinte,
-- ed entrambe da sole basterebbero.
--
--   1. Una funzione del genere sarebbe una SONDA: concessa ad `anon`,
--      risponderebbe su qualunque uuid, e chi ne avesse un elenco potrebbe
--      compilare la mappa di chi e' verificato senza aprire un profilo. La
--      20260825120000 aveva gia rifiutato esattamente questa forma.
--   2. Sul profilo pubblico il problema N+1 non esiste per costruzione: una
--      pagina, un uuid, una chiamata. Il costo aggiuntivo e' un `exists` e un
--      `jsonb_agg` sull'indice parziale delle sole approvate, dentro una query
--      che gia si fa.
--
-- Nessuna scheda annuncio, nessun messaggio, nessuna community riceve la
-- spunta in questo file. Il profilo pubblico e' la superficie canonica, ed e'
-- l'unica. Estendere la spunta a una lista significherebbe una lettura per
-- riga, e non si fa qui.
--
-- ---------------------------------------------------------------------------
-- DROP E RICREA, NON `CREATE OR REPLACE`
-- ---------------------------------------------------------------------------
--
-- `create or replace function` non puo cambiare il tipo di ritorno di una
-- funzione che restituisce `table (...)`: aggiungere due colonne e' un cambio
-- di firma. Il DROP e' quindi obbligato, e con lui i GRANT vanno riscritti -
-- un privilegio non sopravvive alla funzione che lo portava. Le sette colonne
-- gia in contratto restano identiche, nello stesso ordine, con gli stessi tipi:
-- le due nuove si aggiungono in coda, cosi nessun chiamante esistente cambia
-- comportamento.
--
-- ---------------------------------------------------------------------------
-- CHE COSA DIVENTA PUBBLICO, E CHE COSA NO
-- ---------------------------------------------------------------------------
--
-- Di una qualifica approvata e non scaduta escono SOLO: titolo, ente
-- emittente, paese, data di emissione, data di scadenza.
--
-- Restano dentro, e nessuna evoluzione di questo file deve farli uscire:
-- `credential_reference` (un identificativo personale), qualunque cosa
-- riguardi i documenti (id, percorso, bucket, tipo, dimensione, numero), e
-- tutto cio che riguarda la verifica (fornitore, modello, confidenza, risposta
-- grezza, ragionamento). La colonna che li conterrebbe non esiste nella firma:
-- non c'e' un filtro da ricordarsi di applicare.
--
-- L'elenco e' chiuso alla sorgente: `private.qualifiche_professionali_valide`
-- non contiene `credential_reference`, quindi non c'e' modo di farlo trapelare
-- da qui nemmeno per distrazione.

drop function if exists public.profilo_pubblico(uuid);

create function public.profilo_pubblico(p_user_id uuid)
returns table (
  user_id uuid,
  username text,
  bio text,
  citta text,
  provincia text,
  esperienza text,
  avatar_url text,
  professionista_verificato boolean,
  qualifiche_professionali jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    v.user_id,
    v.username,
    v.bio,
    v.citta,
    v.provincia,
    v.esperienza,
    v.avatar_url,
    -- La spunta non e' calcolata qui: e' la presenza di almeno una riga nella
    -- vista che la definisce. Regola scritta in un posto solo, letta qui.
    exists (
      select 1
      from private.qualifiche_professionali_valide q
      where q.user_id = v.user_id
    ) as professionista_verificato,
    -- Array vuoto e non NULL: chi legge distingue «nessuna qualifica» da un
    -- guasto senza dover trattare due assenze diverse.
    coalesce(
      (
        select jsonb_agg(
                 jsonb_build_object(
                   'titolo', q.titolo,
                   'ente_emittente', q.ente_emittente,
                   'paese', q.paese,
                   'issued_on', q.issued_on,
                   'expires_on', q.expires_on
                 )
                 order by q.issued_on desc nulls last, q.titolo
               )
        from private.qualifiche_professionali_valide q
        where q.user_id = v.user_id
      ),
      '[]'::jsonb
    ) as qualifiche_professionali
  from private.profili_pubblici v
  where v.user_id = p_user_id;
$$;

comment on function public.profilo_pubblico(uuid) is
  'Profilo pubblico di una persona. Le sette colonne del contratto originale '
  'restano invariate; in coda arrivano la spunta di professionista verificato '
  'e le sole qualifiche approvate e non scadute, con titolo, ente, paese e '
  'date. Non espone credential_reference, ne alcun dato dei documenti o della '
  'verifica. Una riga per uuid: nessun N+1 e nessuna sonda su terzi.';

revoke all on function public.profilo_pubblico(uuid) from public;
grant execute on function public.profilo_pubblico(uuid) to anon, authenticated;

notify pgrst, 'reload schema';
