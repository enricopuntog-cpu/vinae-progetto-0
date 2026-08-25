-- ===========================================================================
-- Profilo pubblico utente - fondazione dati, sola lettura
-- ===========================================================================
--
-- CHE COSA APRE, E CHE COSA DELIBERATAMENTE NON APRE. Oggi username e avatar
-- di una persona compaiono gia in quattro superfici pubbliche - annunci
-- (`public_listings.seller_*`), post del Club, risposte del Club e, in
-- prospettiva, i messaggi. Nessuna di quelle superfici ha pero una
-- destinazione: il nome e la faccia si vedono e non portano da nessuna parte.
-- Questo file crea il dato che quella destinazione leggera, e nient'altro:
-- nessuna pagina, nessun collegamento dalle superfici sorgente, nessun elenco.
--
-- IL PROFILO PUBBLICO E' DELL'UTENTE, NON DEL VENDITORE. Un iscritto che non
-- ha mai pubblicato un annuncio ha comunque un profilo pubblico: scrive nel
-- Club, commenta, e quel nome deve poter essere cliccabile domani. Per questa
-- ragione la proiezione parte da `public.profiles` e non da `public.listings`,
-- e non esiste in nessun punto di questo file una condizione sulla presenza di
-- annunci, sul ruolo o sulla capacita di vendere. Gli annunci attivi sono una
-- sezione eventuale della futura pagina, non il criterio di esistenza del
-- profilo: si leggono da `public_listings`, che li ha gia e che questo file
-- non tocca.
--
-- ---------------------------------------------------------------------------
-- PERCHE' UNA FUNZIONE E NON UNA VISTA CONCESSA AD ANON
-- ---------------------------------------------------------------------------
--
-- La forma ovvia sarebbe una vista `security_invoker = off` con GRANT SELECT ad
-- `anon`, come `public_listings` e `public_club_posts`. Qui sarebbe sbagliata,
-- e per una ragione precisa: quelle due sono cataloghi, e un catalogo si sfoglia
-- per definizione. Un profilo no. Una vista concessa ad `anon` e' raggiungibile
-- da PostgREST come `GET /rest/v1/<vista>` senza filtri, cioe' l'elenco
-- completo degli iscritti - nome, citta, provincia, presentazione - scaricabile
-- da chiunque in una richiesta. Sarebbe una rubrica di persone, che questo
-- lavoro non deve creare.
--
-- La porta e' quindi una funzione che prende UN identificativo e restituisce al
-- massimo UNA riga. Non esiste una chiamata che le faccia elencare qualcosa:
-- non ha un parametro di ricerca, non ha un limite, non ha un offset, e non
-- accetta un predicato. Chi vuole leggere un profilo deve gia sapere di chi.
--
-- E lo sa sempre, perche' `p_user_id` e' esattamente l'identificativo che le
-- superfici sorgente pubblicano gia: `public_listings.seller_id`,
-- `public_club_posts.autore_id`, `public_club_post_risposte.autore_id`. La
-- chiave e' quella, e non lo username, per una ragione misurabile e non
-- estetica: lo username e' scrivibile dall'interessato attraverso
-- `profiles_update_own`, quindi cambia, mentre l'id no. Una destinazione
-- costruita su un dato mutevole si rompe il giorno in cui qualcuno si rinomina.
--
-- Un uuid v4 non si indovina e non si enumera per tentativi. Il modello di
-- rischio che resta e' "chi ha gia l'id legge il profilo", ed e' esattamente
-- cio che si vuole: quell'id arriva da una superficie che di quella persona
-- pubblica gia nome e avatar.
--
-- ---------------------------------------------------------------------------
-- L'ALLOWLIST, E PERCHE' NON E' SCRITTA CON UN ASTERISCO
-- ---------------------------------------------------------------------------
--
-- Sette colonne nominate a mano: id, username, presentazione, citta, provincia,
-- esperienza, riferimento avatar. Un `select *` avrebbe pubblicato oggi anche
-- `dob` e le quattro colonne di moderazione della 9b, e avrebbe pubblicato
-- domani qualunque colonna aggiunta a `profiles` da una migrazione futura,
-- senza che nessuno debba deciderlo. E' la stessa regola gia applicata da
-- `my_certifications` e da `COLONNE_PROFILO` in `profile-service.ts`.
--
-- Restano fuori, e vale la pena scriverlo invece di lasciarlo dedurre:
--   * `dob` - dichiarazione di eta, dato personale, mai pubblico;
--   * l'email - non e' nemmeno in questa tabella, sta in `auth.users`;
--   * i ruoli - vivono in `user_roles`, separati apposta dalla 5a per
--     anti-escalation, e questo file non li sfiora;
--   * `stato_utente`, `stato_utente_at`, `stato_utente_motivo`,
--     `provvedimenti` - stato interno di moderazione. La proiezione li LEGGE
--     per decidere se mostrare la riga, e non li RESTITUISCE: il visitatore
--     vede un profilo o non lo vede, e non sa perche';
--   * `obiettivi` - preferenze di onboarding, mai state pubbliche;
--   * tutto cio che riguarda `profile_certifications`, che resta senza alcun
--     privilegio per i ruoli client.
--
-- ---------------------------------------------------------------------------
-- `seller_verificato` NON E' QUI, ED E' UNA SCELTA
-- ---------------------------------------------------------------------------
--
-- `public_listings.seller_verificato` esiste dalla 20260825120000 e resta dov'e'
-- - questo file non lo tocca, non lo rinomina e non ne cambia il significato per
-- il catalogo. Non viene pero' portato sul profilo pubblico: la spunta che il
-- profilo mostrera' un giorno dipendera' da qualifiche professionali approvate,
-- che sono un dominio non ancora aperto. Aggiungere qui il booleano di oggi
-- significherebbe promettere sul profilo una cosa diversa da quella che il
-- profilo intende dire. Il campo non c'e', quindi nessuna interfaccia puo'
-- leggerlo per sbaglio.
--
-- ---------------------------------------------------------------------------
-- LA VISIBILITA' NON E' UNA REGOLA NUOVA
-- ---------------------------------------------------------------------------
--
-- Non viene inventato nessun criterio di privacy. Si riusa la decisione 7.6b,
-- che questo repository applica gia in entrambe le direzioni, e si riusa nella
-- stessa forma testuale che `public_listings` (9b) e `public_club_posts` (12b)
-- hanno gia:
--
--   uscente  - `stato_utente = 'rimosso'`: la persona non ha profilo pubblico,
--              esattamente come i suoi annunci escono dal catalogo;
--   entrante - un chiamante `rimosso` non legge la superficie pubblica. Per
--              `anon` `auth.uid()` e' nullo, il `not exists` e' vero e il
--              comportamento del visitatore anonimo non cambia.
--
-- `sospeso` resta visibile, e non e' una dimenticanza. La 9c dichiara che il
-- primo provvedimento blocca la sola scrittura sociale e lascia la persona nel
-- catalogo: `public_listings` mostra ancora i suoi annunci. Nascondere qui il
-- profilo di un sospeso contraddirebbe una decisione presa, e lascerebbe per
-- giunta annunci nel catalogo con una destinazione che risponde "non trovato".
--
-- ---------------------------------------------------------------------------
-- CHE COSA QUESTO FILE NON FA
-- ---------------------------------------------------------------------------
--
-- Non allarga nessun GRANT e nessuna policy su `public.profiles`, che resta
-- leggibile dal solo interessato (`profiles_select_own`) e mai da `anon`. Non
-- crea tabelle, non crea colonne, non scrive dati, non tocca `public_listings`,
-- non tocca `profile_certifications`, non tocca i ruoli, non crea nessun elenco
-- e non introduce nessuna scrittura.

-- Lo schema esiste dalla 6d-2a; la riga sta qui per la stessa ragione per cui
-- sta nella 7 e nella 20260825120000, cioe' perche' questo file non dipenda
-- dall'ordine di lettura.
create schema if not exists private;

-- ---------------------------------------------------------------------------
-- [1] La proiezione - un posto solo per l'allowlist e per la visibilita'
-- ---------------------------------------------------------------------------
--
-- Sta in `private` e non in `public` proprio perche' NON deve essere
-- raggiungibile da PostgREST: qui vive l'insieme delle righe pubblicabili,
-- che e' l'elenco che non va concesso a nessuno. La funzione [2] e' l'unica
-- porta, e serve una riga per volta.
--
-- E' una vista e non un pezzo di SQL copiato dentro la funzione per la stessa
-- ragione per cui `private.certificazioni_valide` e' una vista: la definizione
-- di "profilo pubblicamente visibile" deve esistere in un punto solo. Se domani
-- la visibilita' cambia - una scelta esplicita dell'utente, un nuovo stato di
-- moderazione - si corregge qui e vale ovunque, invece di valere in tutti i
-- posti in cui qualcuno si e' ricordato di aggiornarla.

create view private.profili_pubblici
with (security_invoker = off, security_barrier = true)
as
select
  p.id          as user_id,
  p.username,
  p.bio,
  p.citta,
  p.provincia,
  p.esperienza,
  -- Riferimento, non URL: la colonna conserva `<uid>/<uuid>.webp` oppure il
  -- percorso di un preset del catalogo, mai l'indirizzo del progetto Supabase.
  -- Ricomporlo e' compito del client, che ha gia la fondazione avatar chiusa
  -- (`risolviAvatarPersona`), e che nel farlo verifica che la cartella
  -- coincida con `user_id` - quindi un valore manomesso non produce una
  -- richiesta di rete verso la cartella di un'altra persona.
  p.avatar_url
from public.profiles p
-- 7.6b, direzione uscente: chi e' stato rimosso non ha profilo pubblico.
where p.stato_utente <> 'rimosso'::public.utente_stato
  -- 7.6b, direzione entrante: un chiamante rimosso non legge la superficie
  -- pubblica. Stessa forma di public_listings e public_club_posts.
  and not exists (
    select 1 from public.profiles me
    where me.id = (select auth.uid())
      and me.stato_utente = 'rimosso'::public.utente_stato
  );

comment on view private.profili_pubblici is
  'Insieme dei profili pubblicamente visibili, con l''elenco chiuso delle sette '
  'colonne ammesse. Sta in `private` perche non deve essere raggiungibile da '
  'PostgREST: sarebbe la rubrica completa degli iscritti. Unico luogo in cui '
  'sono definite allowlist e visibilita (7.6b, entrambe le direzioni). Si legge '
  'solo attraverso public.profilo_pubblico(uuid), una riga per volta.';

-- Nessun privilegio per i ruoli client, che pure hanno USAGE sullo schema
-- `private`. Stessa posizione di `private.certificazioni_valide`.
revoke all on private.profili_pubblici from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [2] La porta - una riga, mai un elenco
-- ---------------------------------------------------------------------------
--
-- `security definer` perche' la vista [1] legge `public.profiles`, su cui
-- `anon` non ha e non deve avere alcun privilegio: la sostituzione avviene qui
-- e non allargando la tabella base.
--
-- `stable` e non `volatile`: non scrive nulla. Vale la nota di CLAUDE.md sul
-- PostgREST - una funzione `stable` invocata in POST gira comunque in
-- transazione read-only - e qui e' semplicemente corretto, perche' non c'e'
-- nessuna scrittura da proteggere.
--
-- `search_path = ''` e ogni riferimento qualificato per intero: e' la forma
-- richiesta dalle invarianti di sicurezza per ogni SECURITY DEFINER del
-- repository.
--
-- Nessun parametro oltre all'identificativo. Aggiungere qui un `p_cerca`, un
-- `p_limite` o un `p_offset` trasformerebbe questa porta nella rubrica che [1]
-- esiste per impedire.

create or replace function public.profilo_pubblico(p_user_id uuid)
returns table (
  user_id uuid,
  username text,
  bio text,
  citta text,
  provincia text,
  esperienza text,
  avatar_url text
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
    v.avatar_url
  from private.profili_pubblici v
  where v.user_id = p_user_id;
$$;

comment on function public.profilo_pubblico(uuid) is
  'Profilo pubblico di UNA persona, per identificativo. Restituisce zero righe '
  'se la persona non esiste, e stata rimossa (7.6b uscente) o il chiamante e '
  'rimosso (7.6b entrante): il chiamante non distingue i tre casi. Espone sette '
  'colonne dichiarate una per una - mai email, dob, ruoli, stato di moderazione '
  'o certificazioni. Non elenca: nessun parametro di ricerca, limite o offset.';

-- PostgreSQL concede EXECUTE a PUBLIC per default su ogni funzione nuova. La
-- revoca esplicita prima dei GRANT e' quindi necessaria e non ornamentale:
-- senza, il privilegio arriverebbe anche a ruoli che nessuno ha nominato.
revoke all on function public.profilo_pubblico(uuid) from public;

-- Un profilo pubblico e' pubblico: `anon` deve poterlo leggere, altrimenti la
-- pagina non esisterebbe per chi non e' iscritto. La concessione e' stretta -
-- una funzione che restituisce una riga di sole colonne pubbliche - e non
-- somiglia alla "funzione che sonda lo stato di qualunque uuid" che la
-- 20260825120000 rifiuta di concedere ad anon: quella avrebbe rivelato un fatto
-- di fiducia, questa restituisce cio che l'interessato ha scritto per essere
-- visto.
grant execute on function public.profilo_pubblico(uuid) to anon, authenticated;

notify pgrst, 'reload schema';
