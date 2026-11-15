-- VPM-FIN-001, parte 2 di 2: un Transfer dall'esito incerto non libera mai i fondi (G-12).
--
-- DIFETTO. `prelievo_registra_esito` traduceva ogni trasferimento non riuscito in `fallito`, anche
-- un timeout o una risposta 5xx dopo cui Stripe puo avere gia eseguito il Transfer. `fallito` era
-- annullabile dal titolare (`balance_prelievo_annulla`): l'annullamento scioglieva la prenotazione,
-- i centesimi tornavano spendibili e una nuova richiesta, con una chiave diversa e quindi un
-- Transfer diverso, poteva farli uscire una seconda volta. Una seconda via portava allo stesso
-- punto: due esecutori concorrenti sullo stesso prelievo (`prelievo_prepara` accettava `in_corso`),
-- un 409 di Stripe registrato come `fallito`, e il successo dell'altro rifiutato perche lo stato non
-- era piu `in_corso`. Un esecutore morto fra Transfer e registrazione lasciava invece il prelievo
-- `in_corso` per sempre: ne annullabile ne ritentabile, senza procedura di uscita.
--
-- MODELLO. Si distinguono due fatti che prima avevano un solo nome:
--   * `fallito`        = il fornitore ha RIFIUTATO (o la chiamata non e mai partita): provato che
--                        nessun Transfer esiste per questo tentativo. Annullabile e ritentabile.
--   * `esito_incerto`  = il Transfer puo esistere. Non annullabile, mai liberato in automatico.
-- L'incertezza si chiude soltanto con una PROVA: o il ritentativo con la STESSA chiave di
-- idempotenza entro la finestra in cui Stripe la ricorda (la risposta salvata dice la verita), o
-- una riconciliazione verificata (`prelievo_riconcilia`, solo service_role). Fuori finestra il
-- ritentativo e vietato: con la chiave scaduta Stripe esegue un Transfer NUOVO.
-- Un'incertezza aperta NON si chiude con un rifiuto, nemmeno entro la finestra: un 401/403, una
-- chiave segreta assente o un errore di validazione non passano dalla chiave di idempotenza e non
-- dicono nulla sul tentativo originale. Si chiude con un successo o con la riconciliazione.
--
-- NUMERI. Stripe puo eliminare le chiavi di idempotenza dopo ALMENO 24 ore (letto su
-- https://docs.stripe.com/api/idempotent_requests il 15 novembre 2026) e ripete la risposta salvata
-- anche per gli errori 500. Il ritentativo e quindi ammesso entro 20 ore dall'inizio del primo
-- tentativo incerto; la verifica negativa solo dopo 24 ore (a quel punto un Transfer esiste o non
-- esiste, e lo si legge dal fornitore senza dipendere dalla chiave).
--
-- COMPATIBILITA. La Edge Function gia distribuita chiama `prelievo_registra_esito` con 4 argomenti:
-- il quinto ha un default prudente (`p_rifiutato = false`), quindi quella chiamata produce
-- `esito_incerto`. Nessun fallimento senza prova puo piu essere registrato come `fallito`.
--
-- Additiva: colonne nullable, un vincolo, funzioni sostituite con lo stesso owner e le stesse
-- porte, due porte nuove solo service_role. Nessuna tabella nuova, nessuna modifica al ledger.


-- ---------------------------------------------------------------------------
-- 1. Colonne
-- ---------------------------------------------------------------------------

alter table public.balance_withdrawals
  add column if not exists ultimo_tentativo_at timestamptz,
  add column if not exists esito_incerto_dal timestamptz,
  add column if not exists riconciliato_at timestamptz,
  add column if not exists riconciliazione_nota text;

comment on column public.balance_withdrawals.ultimo_tentativo_at is
  'Quando l''esecutore ha preso in carico il tentativo corrente (stato in_corso).';
comment on column public.balance_withdrawals.esito_incerto_dal is
  'Inizio del PRIMO tentativo di cui non si conosce l''esito nell''incertezza in corso: ancora '
  'della finestra di idempotenza. NULL quando nessuna incertezza e aperta.';
comment on column public.balance_withdrawals.riconciliato_at is
  'Quando un operatore ha chiuso l''incertezza con una prova verificata presso il fornitore.';
comment on column public.balance_withdrawals.riconciliazione_nota is
  'Dove e come e stato verificato l''esito (senza dati personali).';


-- ---------------------------------------------------------------------------
-- 2. Le finestre, in un solo posto
-- ---------------------------------------------------------------------------

create or replace function private.prelievo_finestra_replay()
returns interval
language sql
immutable
set search_path = ''
as $$ select interval '20 hours' $$;

create or replace function private.prelievo_attesa_negativa()
returns interval
language sql
immutable
set search_path = ''
as $$ select interval '24 hours' $$;

revoke all on function private.prelievo_finestra_replay() from public, anon, authenticated;
revoke all on function private.prelievo_attesa_negativa() from public, anon, authenticated;

comment on function private.prelievo_finestra_replay() is
  'Entro questo tempo dall''inizio di un''incertezza il ritentativo con la stessa chiave e sicuro: '
  'Stripe garantisce le chiavi per almeno 24 ore, qui con 4 ore di margine.';
comment on function private.prelievo_attesa_negativa() is
  'Prima di questo tempo non si puo dichiarare non eseguito un trasferimento incerto: la chiave puo '
  'ancora esistere e il ritentativo e lo strumento giusto.';


-- ---------------------------------------------------------------------------
-- 3. Backfill: nessun prelievo vecchio resta annullabile se potrebbe essere partito
-- ---------------------------------------------------------------------------
--
-- Prima di questa migrazione ogni tentativo non riuscito era `fallito`, quindi un `fallito` con
-- almeno un tentativo non prova che il Transfer non sia partito. Si riclassificano tutti come
-- incerti: e la scelta prudente, e la verifica negativa (dopo 24 ore) li riporta a `fallito` solo
-- con una prova. I `fallito` senza tentativi (insolvenza prima di ogni chiamata) restano tali.

update public.balance_withdrawals
set stato = 'esito_incerto',
    -- `created_at` e il momento piu antico in cui la chiave puo essere stata usata: `updated_at` e
    -- l'ultimo fallimento, e la chiave puo risalire a giorni prima.
    esito_incerto_dal = created_at,
    ultimo_errore = coalesce(ultimo_errore, 'Esito sconosciuto.'),
    updated_at = now()
where stato = 'fallito' and tentativi > 0;


-- ---------------------------------------------------------------------------
-- 4. Vincoli
-- ---------------------------------------------------------------------------

-- Un Transfer chiude al piu un prelievo: l'unicita e del database, non di un controllo applicativo
-- che due riconciliazioni concorrenti potrebbero superare entrambe.
create unique index if not exists balance_withdrawals_provider_transfer_uq
  on public.balance_withdrawals (provider, provider_transfer_id)
  where provider_transfer_id is not null;

alter table public.balance_withdrawals
  add constraint balance_withdrawals_incerto_origine_check
    check (stato <> 'esito_incerto' or esito_incerto_dal is not null),
  add constraint balance_withdrawals_nota_lunghezza_check
    check (riconciliazione_nota is null or length(riconciliazione_nota) between 1 and 500);


-- ---------------------------------------------------------------------------
-- 5. Preparazione: un solo esecutore, stessa chiave, mai fuori finestra
-- ---------------------------------------------------------------------------

create or replace function public.prelievo_prepara(p_withdrawal_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_wd public.balance_withdrawals%rowtype;
  v_account public.seller_payout_accounts%rowtype;
  v_balance public.balance_accounts%rowtype;
  v_replay boolean := false;
begin
  select * into v_wd from public.balance_withdrawals where id = p_withdrawal_id for update;
  if not found then raise exception 'Prelievo non trovato.' using errcode = 'P0001'; end if;

  if v_wd.stato = 'trasferito' then
    return jsonb_build_object('esito', 'gia_trasferito', 'withdrawal_id', v_wd.id);
  end if;

  -- `in_corso` e il possesso del prelievo da parte di un esecutore. Un secondo esecutore (una
  -- seconda invocazione dello scheduler) non riceve un secondo Transfer da inviare. Se
  -- l'esecutore e morto, la marcatura degli orfani lo porta a `esito_incerto`.
  if v_wd.stato = 'in_corso' then
    return jsonb_build_object('esito', 'non_dovuto', 'motivo', 'in_corso');
  end if;
  if v_wd.stato not in ('richiesto', 'fallito', 'esito_incerto') then
    return jsonb_build_object('esito', 'non_dovuto', 'motivo', v_wd.stato::text);
  end if;

  -- Verificato non eseguito da un operatore: il titolare lo annulla e, se vuole, ne chiede uno
  -- nuovo con una chiave nuova. Nessun ritentativo automatico con la chiave vecchia.
  if v_wd.stato = 'fallito' and v_wd.riconciliato_at is not null then
    return jsonb_build_object('esito', 'non_dovuto', 'motivo', 'riconciliato_non_eseguito');
  end if;

  if v_wd.stato = 'esito_incerto' then
    -- Fuori finestra la chiave puo non esistere piu: ritentare creerebbe un Transfer NUOVO.
    if now() >= v_wd.esito_incerto_dal + private.prelievo_finestra_replay() then
      return jsonb_build_object('esito', 'bloccato', 'motivo', 'finestra_idempotenza_scaduta');
    end if;
    v_replay := true;
  end if;

  -- Insolvenza. Una rettifica di rimborso puo avere portato il disponibile sotto l'importo gia
  -- prenotato: il denaro promesso non c'e piu e il trasferimento non parte. La prenotazione resta,
  -- il debito resta visibile. Un prelievo incerto NON scivola in `fallito` (annullabile): il suo
  -- Transfer puo essere gia partito.
  v_balance := private.balance_account_lock(v_wd.owner_id, v_wd.currency);
  if v_balance.available_cents < v_wd.amount_cents then
    if not v_replay then
      update public.balance_withdrawals set
        stato = 'fallito', ultimo_errore = 'Saldo non più capiente.', updated_at = now()
      where id = v_wd.id;
    end if;
    return jsonb_build_object('esito', 'bloccato', 'motivo', 'saldo_insufficiente');
  end if;

  if v_replay then
    -- Stessi parametri del primo tentativo: con parametri diversi Stripe rifiuta la chiave e il
    -- rifiuto non proverebbe nulla sul tentativo originale.
    if v_wd.provider is null or v_wd.destination_account_id is null then
      return jsonb_build_object('esito', 'bloccato', 'motivo', 'destinazione_originale_mancante');
    end if;
  else
    select * into v_account from public.seller_payout_accounts
    where seller_id = v_wd.owner_id and charges_enabled and payouts_enabled
    order by provider
    limit 1;
    if not found then
      return jsonb_build_object('esito', 'bloccato', 'motivo', 'destinatario_non_abilitato');
    end if;
  end if;

  update public.balance_withdrawals set
    stato = 'in_corso',
    tentativi = tentativi + 1,
    ultimo_tentativo_at = now(),
    provider = case when v_replay then provider else v_account.provider end,
    destination_account_id = case when v_replay then destination_account_id
                                  else v_account.provider_account_id end,
    updated_at = now()
  where id = v_wd.id returning * into v_wd;

  return jsonb_build_object(
    'esito', 'da_trasferire',
    'withdrawal_id', v_wd.id,
    'provider', v_wd.provider,
    'destination_account_id', v_wd.destination_account_id,
    'amount_cents', v_wd.amount_cents,
    'currency', v_wd.currency,
    'idempotency_key', v_wd.idempotency_key,
    'tentativi', v_wd.tentativi,
    'replay', v_replay
  );
end;
$$;

revoke execute on function public.prelievo_prepara(uuid) from public, anon, authenticated;
grant execute on function public.prelievo_prepara(uuid) to service_role;


-- ---------------------------------------------------------------------------
-- 6. Esito: un fallimento senza prova e un'incertezza
-- ---------------------------------------------------------------------------

drop function if exists public.prelievo_registra_esito(uuid, boolean, text, text);

create or replace function public.prelievo_registra_esito(
  p_withdrawal_id uuid,
  p_ok boolean,
  p_provider_transfer_id text,
  p_errore text,
  p_rifiutato boolean default false
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_wd public.balance_withdrawals%rowtype;
  v_definitivo boolean;
begin
  select * into v_wd from public.balance_withdrawals where id = p_withdrawal_id for update;
  if not found then raise exception 'Prelievo non trovato.' using errcode = 'P0001'; end if;

  -- Replay dell'esito positivo: lo stato e gia quello e la prenotazione e gia consumata.
  if v_wd.stato = 'trasferito' then return 'duplicate'; end if;
  if v_wd.stato = 'annullato' then return 'non_dovuto'; end if;

  if coalesce(p_ok, false) then
    if length(coalesce(trim(p_provider_transfer_id), '')) = 0 then
      raise exception 'Un trasferimento riuscito deve portare l''identificativo del fornitore.'
        using errcode = '22023';
    end if;
    -- Un successo e la prova piu forte che esista: vale anche se nel frattempo la marcatura degli
    -- orfani aveva portato il prelievo a `esito_incerto`.
    if v_wd.stato not in ('in_corso', 'esito_incerto') then
      raise exception 'Questo prelievo non era in trasferimento.' using errcode = 'P0001';
    end if;

    perform private.balance_reservation_consuma(v_wd.reservation_id);
    update public.balance_withdrawals set
      stato = 'trasferito',
      provider_transfer_id = trim(p_provider_transfer_id),
      transferred_at = now(),
      esito_incerto_dal = null,
      ultimo_errore = null,
      updated_at = now()
    where id = v_wd.id;
    return 'transferred';
  end if;

  -- Un fallimento si registra solo su un tentativo in volo o gia incerto.
  if v_wd.stato not in ('in_corso', 'esito_incerto') then return 'non_dovuto'; end if;

  -- Un rifiuto prova la non esecuzione del tentativo CHE LO HA RICEVUTO, e basta. Se esiste gia
  -- un'incertezza aperta (`esito_incerto_dal` valorizzato) un rifiuto non dice nulla sul tentativo
  -- precedente, che puo essere partito: un 401/403 o una chiave segreta assente arrivano PRIMA che il
  -- fornitore guardi la chiave di idempotenza, e un rifiuto fuori finestra riguarda un tentativo
  -- nuovo. Un'incertezza aperta si chiude solo con un SUCCESSO o con `prelievo_riconcilia`.
  v_definitivo := coalesce(p_rifiutato, false) and v_wd.esito_incerto_dal is null;

  -- Nessun caso rende i centesimi di nuovo spendibili da qui: solo l'annullamento esplicito del
  -- titolare, e solo da `richiesto` o `fallito`.
  if v_definitivo then
    update public.balance_withdrawals set
      stato = 'fallito',
      esito_incerto_dal = null,
      ultimo_errore = left(coalesce(p_errore, 'Trasferimento rifiutato.'), 500),
      updated_at = now()
    where id = v_wd.id;
    return 'failed';
  end if;

  update public.balance_withdrawals set
    stato = 'esito_incerto',
    esito_incerto_dal = coalesce(esito_incerto_dal, ultimo_tentativo_at, now()),
    ultimo_errore = left(coalesce(p_errore, 'Esito del trasferimento sconosciuto.'), 500),
    updated_at = now()
  where id = v_wd.id;
  return 'uncertain';
end;
$$;

revoke execute on function public.prelievo_registra_esito(uuid, boolean, text, text, boolean)
  from public, anon, authenticated;
grant execute on function public.prelievo_registra_esito(uuid, boolean, text, text, boolean)
  to service_role;

comment on function public.prelievo_registra_esito(uuid, boolean, text, text, boolean) is
  'Registra l''esito di un tentativo di Transfer. p_rifiutato = true SOLO se il fornitore ha '
  'risposto con un rifiuto che prova la non esecuzione; ogni altro fallimento (timeout, 5xx, '
  'risposta illeggibile) e esito_incerto e non libera mai la prenotazione.';


-- ---------------------------------------------------------------------------
-- 7. Coda: gli incerti rientrano solo finche il ritentativo e sicuro
-- ---------------------------------------------------------------------------

create or replace function public.prelievo_coda(p_limit integer default 50)
returns setof uuid
language sql
security definer
set search_path = ''
stable
as $$
  select w.id
  from public.balance_withdrawals w
  where w.tentativi < 5
    and (
      w.stato = 'richiesto'
      or (w.stato = 'fallito' and w.riconciliato_at is null)
      or (w.stato = 'esito_incerto'
          and now() < w.esito_incerto_dal + private.prelievo_finestra_replay())
    )
  order by w.created_at
  limit least(greatest(coalesce(p_limit, 50), 1), 500);
$$;

revoke execute on function public.prelievo_coda(integer) from public, anon, authenticated;
grant execute on function public.prelievo_coda(integer) to service_role;


-- ---------------------------------------------------------------------------
-- 8. Annullamento: mai su un prelievo il cui Transfer puo essere partito
-- ---------------------------------------------------------------------------

create or replace function public.balance_prelievo_annulla(p_withdrawal_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_wd public.balance_withdrawals%rowtype;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  select * into v_wd from public.balance_withdrawals
  where id = p_withdrawal_id for update;
  if not found or v_wd.owner_id <> v_uid then
    raise exception 'Richiesta di prelievo non trovata.' using errcode = '42501';
  end if;
  if v_wd.stato = 'annullato' then
    return jsonb_build_object('id', v_wd.id, 'stato', v_wd.stato::text);
  end if;
  if v_wd.stato = 'in_corso' then
    raise exception
      'Questo prelievo è già in trasferimento e non può essere annullato.'
      using errcode = 'P0001';
  end if;
  if v_wd.stato = 'esito_incerto' then
    raise exception
      'L''esito di questo trasferimento è in verifica e il prelievo non può essere annullato.'
      using errcode = 'P0001';
  end if;
  if v_wd.stato not in ('richiesto', 'fallito') then
    raise exception 'Questo prelievo non è più annullabile.' using errcode = 'P0001';
  end if;

  -- Il rilascio è idempotente per costruzione: guarda lo stato della prenotazione, quindi un
  -- secondo annullamento non restituisce due volte.
  perform private.balance_reservation_rilascia(v_wd.reservation_id);
  update public.balance_withdrawals
  set stato = 'annullato', updated_at = now()
  where id = v_wd.id returning * into v_wd;

  return jsonb_build_object('id', v_wd.id, 'stato', v_wd.stato::text);
end;
$$;

revoke execute on function public.balance_prelievo_annulla(uuid) from public, anon;
grant execute on function public.balance_prelievo_annulla(uuid) to authenticated;


-- ---------------------------------------------------------------------------
-- 9. Orfani: un esecutore morto dopo il Transfer lascia un'incertezza, non un buco
-- ---------------------------------------------------------------------------
--
-- Un prelievo `in_corso` non era ne annullabile ne ritentabile ne in coda: restava li per sempre.
-- Dopo la soglia (la Edge Function vive al massimo pochi minuti) il suo tentativo e per definizione
-- un'incertezza: entra nel normale percorso di ritentativo/riconciliazione.

create or replace function public.prelievo_in_corso_scaduti_marca(p_minuti integer default 15)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_n integer;
begin
  if p_minuti is null or p_minuti < 0 then
    raise exception 'Soglia non valida.' using errcode = '22023';
  end if;

  with marcati as (
    update public.balance_withdrawals w set
      stato = 'esito_incerto',
      esito_incerto_dal = coalesce(w.esito_incerto_dal, w.ultimo_tentativo_at, w.updated_at),
      ultimo_errore = 'Esito sconosciuto: l''esecutore non ha registrato la risposta.',
      updated_at = now()
    where w.stato = 'in_corso'
      and coalesce(w.ultimo_tentativo_at, w.updated_at) <= now() - make_interval(mins => p_minuti)
    returning 1
  )
  select count(*) into v_n from marcati;
  return v_n;
end;
$$;

revoke execute on function public.prelievo_in_corso_scaduti_marca(integer)
  from public, anon, authenticated;
grant execute on function public.prelievo_in_corso_scaduti_marca(integer) to service_role;


-- ---------------------------------------------------------------------------
-- 10. Riconciliazione: l'unica uscita dall'incertezza oltre al ritentativo
-- ---------------------------------------------------------------------------
--
-- Solo service_role, mai un cliente. Registra una PROVA letta dall'operatore presso il fornitore:
--   'trasferito'   il Transfer esiste. Servono identificativo, importo e destinazione, e devono
--                  combaciare con il prelievo: la prenotazione si consuma una volta e il ledger
--                  resta coerente.
--   'non_eseguito' nessun Transfer esiste. Ammesso solo dopo 24 ore dall'inizio dell'incertezza
--                  (la chiave puo ancora esistere prima). Il prelievo diventa `fallito`
--                  riconciliato: fuori dalla coda automatica, annullabile dal titolare.
-- Entrambe richiedono una nota che dica dove e stato verificato. Il database non inventa esiti:
-- non chiama il fornitore e non si fida di valori che non combaciano.

create or replace function public.prelievo_riconcilia(
  p_withdrawal_id uuid,
  p_esito text,
  p_provider_transfer_id text default null,
  p_importo_cents integer default null,
  p_destinazione text default null,
  p_nota text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_wd public.balance_withdrawals%rowtype;
  v_nota text := nullif(trim(coalesce(p_nota, '')), '');
  v_transfer text := nullif(trim(coalesce(p_provider_transfer_id, '')), '');
begin
  if v_nota is null or length(v_nota) > 500 then
    raise exception
      'Serve una nota di prova (1-500 caratteri) che dica dove è stato verificato l''esito.'
      using errcode = '22023';
  end if;
  if p_esito is null or p_esito not in ('trasferito', 'non_eseguito') then
    raise exception 'Esito di riconciliazione non valido.' using errcode = '22023';
  end if;

  select * into v_wd from public.balance_withdrawals where id = p_withdrawal_id for update;
  if not found then raise exception 'Prelievo non trovato.' using errcode = 'P0001'; end if;

  if p_esito = 'trasferito' then
    if v_transfer is null then
      raise exception 'Serve l''identificativo del Transfer.' using errcode = '22023';
    end if;

    if v_wd.stato = 'trasferito' then
      if v_wd.provider_transfer_id = v_transfer then return 'duplicate'; end if;
      raise exception 'Questo prelievo risulta già trasferito con un altro identificativo.'
        using errcode = 'P0001';
    end if;
    if v_wd.stato = 'annullato' then
      raise exception
        'Prelievo annullato con un Transfer esistente: anomalia da trattare a mano, non registrabile qui.'
        using errcode = 'P0001';
    end if;
    if v_wd.stato = 'richiesto' or v_wd.destination_account_id is null then
      raise exception 'Nessun tentativo di trasferimento da riconciliare.' using errcode = 'P0001';
    end if;

    if v_wd.provider = 'stripe' and left(v_transfer, 3) <> 'tr_' then
      raise exception 'L''identificativo non è quello di un Transfer Stripe.' using errcode = 'P0001';
    end if;
    if p_importo_cents is distinct from v_wd.amount_cents then
      raise exception 'L''importo del Transfer non coincide con quello del prelievo.'
        using errcode = 'P0001';
    end if;
    if p_destinazione is distinct from v_wd.destination_account_id then
      raise exception 'La destinazione del Transfer non coincide con quella del prelievo.'
        using errcode = 'P0001';
    end if;
    if exists (
      select 1 from public.balance_withdrawals o
      where o.provider_transfer_id = v_transfer and o.id <> v_wd.id
    ) or exists (
      -- Un Transfer di rilascio di un ordine non e un prelievo.
      select 1 from public.payouts y where y.provider_transfer_id = v_transfer
    ) then
      raise exception 'Questo Transfer è già associato a un altro prelievo.'
        using errcode = 'P0001';
    end if;

    if not private.balance_reservation_consuma(v_wd.reservation_id) then
      raise exception 'La prenotazione di questo prelievo non è più attiva.'
        using errcode = 'P0001';
    end if;
    update public.balance_withdrawals set
      stato = 'trasferito',
      provider_transfer_id = v_transfer,
      transferred_at = now(),
      esito_incerto_dal = null,
      ultimo_errore = null,
      riconciliato_at = now(),
      riconciliazione_nota = v_nota,
      updated_at = now()
    where id = v_wd.id;
    return 'transferred';
  end if;

  -- non_eseguito
  if v_wd.stato = 'trasferito' then
    raise exception 'Questo prelievo risulta trasferito.' using errcode = 'P0001';
  end if;
  if v_wd.stato = 'in_corso' then
    raise exception 'Questo prelievo è ancora in corso: attendi la marcatura degli orfani.'
      using errcode = 'P0001';
  end if;
  if v_wd.stato <> 'esito_incerto' then return 'non_dovuto'; end if;

  if now() < v_wd.esito_incerto_dal + private.prelievo_attesa_negativa() then
    raise exception
      'Troppo presto: la verifica negativa è ammessa dopo 24 ore dall''inizio dell''incertezza; '
      'prima il ritentativo con la stessa chiave è lo strumento giusto.'
      using errcode = 'P0001';
  end if;

  update public.balance_withdrawals set
    stato = 'fallito',
    esito_incerto_dal = null,
    ultimo_errore = 'Riconciliato: nessun Transfer presso il fornitore.',
    riconciliato_at = now(),
    riconciliazione_nota = v_nota,
    updated_at = now()
  where id = v_wd.id;
  return 'not_executed';
end;
$$;

revoke execute on function public.prelievo_riconcilia(uuid, text, text, integer, text, text)
  from public, anon, authenticated;
grant execute on function public.prelievo_riconcilia(uuid, text, text, integer, text, text)
  to service_role;

comment on function public.prelievo_riconcilia(uuid, text, text, integer, text, text) is
  'Chiude un''incertezza con una prova letta presso il fornitore. Solo service_role. Non chiama '
  'il fornitore e non accetta valori che non combaciano con il prelievo.';


-- ---------------------------------------------------------------------------
-- 11. Il titolare VEDE il prelievo bloccato
-- ---------------------------------------------------------------------------
--
-- `balance_riepilogo` elencava i prelievi aperti in tre stati. Un prelievo `esito_incerto` non
-- compariva: i suoi centesimi restavano impegnati e il titolare non aveva modo di sapere perche.
-- Corpo identico alla definizione di 20260826163000_d1_vinea_balance.sql; cambia soltanto l'elenco
-- degli stati. Stesso owner, stesso search_path, stesse porte.

create or replace function public.balance_riepilogo(p_movimenti integer default 20)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_account public.balance_accounts%rowtype;
  v_limite integer := least(greatest(coalesce(p_movimenti, 20), 1), 100);
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  select * into v_account from public.balance_accounts
  where owner_id = v_uid and currency = 'eur';

  return jsonb_build_object(
    'currency', 'eur',
    'pending_cents', coalesce(v_account.pending_cents, 0),
    'available_cents', coalesce(v_account.available_cents, 0),
    'reserved_cents', coalesce(v_account.reserved_cents, 0),
    'spendable_cents', greatest(
      coalesce(v_account.available_cents, 0) - coalesce(v_account.reserved_cents, 0), 0
    ),
    'movimenti', coalesce((
      select jsonb_agg(m)
      from (
        select
          x.id::text as id,
          x.tipo::text as tipo,
          x.delta_pending_cents as delta_pending_cents,
          x.delta_available_cents as delta_available_cents,
          x.delta_reserved_cents as delta_reserved_cents,
          x.created_at as created_at
        from public.balance_movimenti x
        where x.owner_id = v_uid and x.currency = 'eur'
        order by x.id desc
        limit v_limite
      ) m
    ), '[]'::jsonb),
    'prelievi', coalesce((
      select jsonb_agg(w)
      from (
        select
          y.id::text as id,
          y.stato::text as stato,
          y.amount_cents as amount_cents,
          y.created_at as created_at,
          y.transferred_at as transferred_at
        from public.balance_withdrawals y
        where y.owner_id = v_uid
          and y.stato in ('richiesto', 'in_corso', 'esito_incerto', 'fallito')
        order by y.created_at desc
        limit 10
      ) w
    ), '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.balance_riepilogo(integer) from public, anon;
grant execute on function public.balance_riepilogo(integer) to authenticated;
