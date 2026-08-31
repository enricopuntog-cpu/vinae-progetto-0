-- ===========================================================================
-- D1 — Qualification & Trust Closure
--
-- Due sole cose, entrambe additive. Le migrazioni
-- 20260827160000_d1_professional_qualifications.sql e
-- 20260827160500_d1_public_profile_qualifiche.sql restano intatte: gli enum,
-- gli stati, le policy Storage, la regola della spunta e la porta
-- `review_apply` del solo `service_role` non vengono toccati da qui.
--
--   [1] Una porta stretta per eliminare una BOZZA e soltanto una bozza.
--   [2] La proiezione del titolare smette di mostrare le pratiche `ritirata`.
--
-- Cosa NON c'e' qui, e non deve arrivarci: nessuna approvazione, nessun
-- verdetto, nessun ruolo, nessun `p_user_id`, nessuna nuova porta per `anon`.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- [1] L'eliminazione di una bozza
-- ---------------------------------------------------------------------------
--
-- Il ritiro (`professional_qualification_withdraw`) e' una rinuncia che lascia
-- traccia: si usa per una pratica GIA INVIATA, perche' cancellare una richiesta
-- che qualcuno ha gia potuto leggere sarebbe riscrivere lo storico.
--
-- Questa porta e' l'altra meta', e vale solo prima dell'invio. Una bozza non e'
-- ancora una richiesta: nessuno l'ha vista, non ha `submitted_at`, non ha un
-- esito. Chi l'ha scritta puo' toglierla del tutto, invece di trovarsi in
-- elenco una riga «ritirata» di una pratica che non ha mai inviato.
--
-- Il confine e' lo stato, e lo stato viene riletto qui dentro con `for update`:
-- non arriva dal client, non e' un parametro, e non e' deducibile da come la
-- chiamata e' costruita. `inviata`, `approvata`, `rifiutata` e `ritirata` non
-- sono eliminabili — le prime tre perche' esiste una richiesta o un esito,
-- l'ultima perche' e' proprio il record storico che il ritiro ha prodotto.
--
-- Il titolare e' risolto server-side da `auth.uid()`. Non esiste un
-- `p_user_id`: se ci fosse, sarebbe il client a dire di chi e' la riga.
--
-- I metadati dei documenti spariscono per il `on delete cascade` gia dichiarato
-- sulla loro chiave esterna. Gli OGGETTI nel bucket privato NON sono toccati
-- qui: `storage.objects` non si scrive da SQL applicativo. Il servizio li
-- rimuove prima, con la policy Storage che li consente solo in bozza, e chiama
-- questa funzione soltanto dopo. Se la rimozione fallisse, la riga resta, e con
-- essa il riferimento per riprovare.

create or replace function public.professional_qualification_delete(p_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_stato public.qualifica_professionale_stato;
begin
  if v_uid is null then
    raise exception 'Serve una sessione.' using errcode = '42501';
  end if;

  select q.stato into v_stato
  from public.professional_qualifications q
  where q.id = p_id and q.user_id = v_uid
  for update;

  -- Riga inesistente e riga di un'altra persona danno la stessa risposta: un
  -- messaggio diverso direbbe a chi prova che quell'identificativo esiste.
  if v_stato is null then
    raise exception 'Qualifica non trovata.' using errcode = 'P0001';
  end if;

  if v_stato <> 'bozza'::public.qualifica_professionale_stato then
    raise exception 'Si elimina solo una qualifica in bozza. Una richiesta gia inviata si ritira.'
      using errcode = '42501';
  end if;

  delete from public.professional_qualifications q
  where q.id = p_id and q.user_id = v_uid;
end;
$$;

comment on function public.professional_qualification_delete(uuid) is
  'Elimina una qualifica propria e solo in stato bozza. Titolare da auth.uid(): '
  'nessun p_user_id. I metadati dei documenti seguono per cascade; gli oggetti '
  'Storage li rimuove il chiamante prima di questa chiamata.';

revoke all on function public.professional_qualification_delete(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.professional_qualification_delete(uuid)
  to authenticated;


-- ---------------------------------------------------------------------------
-- [2] La proiezione del titolare, senza le pratiche ritirate
-- ---------------------------------------------------------------------------
--
-- Identica alla versione precedente in tutto: stesse colonne, stesso ordine,
-- stesso `security definer` filtrato su `auth.uid()`, stessa `valida` letta da
-- `private.qualifiche_professionali_valide` e non ricalcolata.
--
-- Cambia una riga sola: `stato <> 'ritirata'`. Una pratica ritirata e' una
-- rinuncia gia avvenuta, e tenerla in cima all'elenco dell'account come una
-- card da guardare non serve a chi la legge. La RIGA RESTA NEL DATABASE: e'
-- storico, e nessuna porta client la cancella. Questa e' una scelta di
-- proiezione, non una cancellazione mascherata.

create or replace function public.professional_qualifications_me()
returns table (
  id uuid,
  titolo text,
  ente_emittente text,
  paese text,
  credential_reference text,
  issued_on date,
  expires_on date,
  stato public.qualifica_professionale_stato,
  submitted_at timestamptz,
  reviewed_at timestamptz,
  created_at timestamptz,
  documenti integer,
  valida boolean,
  documenti_elenco jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    q.id,
    q.titolo,
    q.ente_emittente,
    q.paese,
    q.credential_reference,
    q.issued_on,
    q.expires_on,
    q.stato,
    q.submitted_at,
    q.reviewed_at,
    q.created_at,
    (
      select count(*)
      from public.professional_qualification_documents d
      where d.qualification_id = q.id
    )::integer as documenti,
    exists (
      select 1
      from private.qualifiche_professionali_valide v
      where v.id = q.id
    ) as valida,
    coalesce(
      (
        select jsonb_agg(
                 jsonb_build_object(
                   'id', d.id,
                   'storage_path', d.storage_path,
                   'mime_type', d.mime_type,
                   'size_bytes', d.size_bytes,
                   'created_at', d.created_at
                 )
                 order by d.created_at
               )
        from public.professional_qualification_documents d
        where d.qualification_id = q.id
      ),
      '[]'::jsonb
    ) as documenti_elenco
  from public.professional_qualifications q
  where q.user_id = (select auth.uid())
    and q.stato <> 'ritirata'::public.qualifica_professionale_stato
  order by q.created_at desc;
$$;

comment on function public.professional_qualifications_me() is
  'Le qualifiche della sola persona collegata, escluse le ritirate — che '
  'restano nel database come storico. Zero righe per un chiamante anonimo. Non '
  'espone nulla della verifica: ne fornitore, ne modello, ne confidenza, ne '
  'ragionamento.';

revoke all on function public.professional_qualifications_me() from public, anon;
grant execute on function public.professional_qualifications_me() to authenticated;
