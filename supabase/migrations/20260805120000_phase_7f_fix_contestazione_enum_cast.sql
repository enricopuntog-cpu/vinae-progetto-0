-- ---------------------------------------------------------------------------
-- Fase 7f — ordine_contestazione_risolvi: i letterali di stato non arrivavano
-- all'enum, e i fondi del venditore non si sbloccavano mai
-- ---------------------------------------------------------------------------
--
-- ADDITIVA sopra la Fase 7c (20260804160000), che NON viene modificata in
-- place: vale la regola 11 di CONTESTO_IA/03_ARCHITETTURA_REGOLE_DEBITI.md.
-- La 7c è la diciottesima voce del ledger del progetto reale, quindi quel file
-- è congelato e ogni correzione è un file nuovo con timestamp successivo.
--
-- IL DIFETTO
-- ==========
-- In 20260804160000_phase_7c_delivery_packaging.sql:1125-1126 il ramo `else`
-- di ordine_contestazione_risolvi — quello che serve gli esiti `respinta` e
-- `risolta` — assegna a due colonne enum il risultato di un `case` fra due
-- letterali nudi:
--
--     stato        = case when p_esito = 'respinta' then 'consegnato'
--                                                  else 'completato' end,
--     payout_stato = case when p_esito = 'respinta' then 'trattenuto'
--                                                  else 'in_attesa'  end,
--
-- Un letterale isolato è di tipo `unknown` e si lascia coercire dalla colonna
-- di destinazione. Un `case` fra due letterali no: la risoluzione dei tipi lo
-- porta a `text`, e da `text` a un enum non esiste conversione implicita.
-- L'UPDATE non compila e la funzione solleva, alla prima esecuzione del ramo:
--
--     42804  column "stato" is of type public.order_stato
--            but expression is of type text
--
-- Il ramo `rimborsata` esce prima e non attraversa quell'UPDATE: è per questo
-- che il difetto era invisibile a lettura e a chiamata parziale.
--
-- LA CONSEGUENZA SUL DENARO
-- =========================
-- Il commento della 7c sopra quell'UPDATE dice che lasciare `contestato_at`
-- acceso «terrebbe i fondi del venditore congelati per sempre». È esattamente
-- ciò che accadeva: nessuna contestazione poteva chiudersi a favore del
-- venditore, perché l'unico codice che azzera il flag è quello che non
-- compilava. ordine_auto_rilascio_esegui, payout_coda e payout_prepara
-- filtrano su `contestato_at`, quindi l'ordine restava fuori da ogni rilascio
-- e la riga di public.payouts restava a 'bloccato' senza uscita.
--
-- Nessun ordine reale è stato colpito: al momento della correzione
-- public.orders, public.payments, public.disputes e public.payouts hanno zero
-- righe sul progetto (verificato in Fase 7e). Il difetto era latente, non
-- realizzato.
--
-- PROVENIENZA
-- ===========
-- Trovato dal caso 20 della griglia supabase/tests/7c_consegna_imballaggio.sql
-- alla sua prima esecuzione reale, Fase 7e — docs/PHASE_7E_DEBT_CLOSURE.md.
-- Quel caso esisteva per proteggere questa precisa invariante.
--
-- LA CORREZIONE
-- =============
-- Cambiano soltanto i quattro letterali, che prendono un cast esplicito al
-- tipo letto da pg_type sul progetto reale prima di scrivere questa riga:
--
--     public.orders.stato        -> public.order_stato   (enum, typtype='e')
--     public.orders.payout_stato -> public.payout_stato  (enum, typtype='e')
--
-- e le quattro etichette esistono in quegli enum: `consegnato` (5) e
-- `completato` (7) in order_stato, `trattenuto` (1) e `in_attesa` (2) in
-- payout_stato. Il cast sta su ENTRAMBI i rami di ogni `case`, non solo sul
-- primo: così il tipo del `case` è l'enum per costruzione e non per una regola
-- di risoluzione che un letterale in più potrebbe spostare di nuovo.
--
-- Nient'altro cambia: né la firma, né `security definer`, né `search_path`,
-- né i permessi, né la semantica dei tre esiti. Il corpo è quello della 7c.
-- ---------------------------------------------------------------------------

-- I commenti di progetto della 7c sono riportati qui perché `create or replace`
-- sostituisce il corpo per intero: se non li si riporta, la motivazione delle
-- decisioni (b) e (c) sparisce dal database e resta solo in un file congelato.
--
-- In frontend/ il DisputePanel mostra a ENTRAMBE le parti tre bottoni che
-- chiudono la pratica, sotto la scritta «Azioni demo». È impalcatura da demo,
-- non un modello di permessi: portarla alla lettera lascerebbe a una parte in
-- causa il potere di decidere la propria controversia, e a un venditore quello
-- di respingere la contestazione che blocca i suoi stessi fondi.
-- Decisione (b): solo admin e service_role.
create or replace function public.ordine_contestazione_risolvi(
  p_order_id uuid,
  p_esito    public.dispute_stato,
  p_nota     text default null
)
returns public.orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
  v_dispute public.disputes%rowtype;
begin
  -- service_role non ha auth.uid(): è il chiamante di back-office.
  if v_uid is not null and not public.has_role(v_uid, 'admin') then
    raise exception 'Non autorizzato a risolvere una contestazione.'
      using errcode = '42501';
  end if;
  if p_esito not in ('rimborsata', 'risolta', 'respinta') then
    raise exception 'Esito non valido.' using errcode = '22023';
  end if;
  if p_nota is not null and length(p_nota) > 1000 then
    raise exception 'Nota troppo lunga.' using errcode = '22023';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    raise exception 'Ordine non trovato.' using errcode = 'P0001';
  end if;

  select * into v_dispute from public.disputes where order_id = p_order_id for update;
  if not found then
    raise exception 'Nessuna contestazione da risolvere.' using errcode = 'P0001';
  end if;
  if v_dispute.stato not in ('aperta', 'in_valutazione') then
    return v_order;  -- idempotente
  end if;

  update public.disputes set
    stato = p_esito,
    esito_nota = p_nota,
    risolta_da = v_uid,
    chiusura_at = now()
  where id = v_dispute.id;

  if p_esito = 'rimborsata' then
    -- Decisione (c). L'ordine RESTA contestato e i fondi restano bloccati:
    -- `rimborsato` lo scrive soltanto payment_apply_provider_event, cioè un
    -- evento firmato e deduplicato del fornitore. Dire «rimborsato» prima che
    -- il denaro si sia mosso è ciò che quell'invariante vieta.
    perform private.tracking_registra(
      p_order_id, 'sistema', 'Rimborso disposto',
      coalesce(p_nota, 'In attesa di conferma dal fornitore di pagamento.'));
  else
    -- `respinta` riporta l'ordine dov'era prima della contestazione;
    -- `risolta` lo chiude con l'accordo fra le parti. In entrambi i casi il
    -- flag va azzerato: è su contestato_at che filtrano ordine_auto_rilascio_esegui,
    -- payout_coda e payout_prepara, e lasciarlo acceso terrebbe i fondi del
    -- venditore congelati per sempre.
    --
    -- Nessuna scrittura su public.payouts: payout_prepara fa
    -- `on conflict (order_id) do update set stato = 'in_corso'`, quindi la riga
    -- che ordine_contesta aveva messo a 'bloccato' viene ripresa da sola.
    --
    -- FASE 7F: i quattro letterali sono castati. Senza il cast il `case` si
    -- risolve a `text`, che verso un enum non ha conversione implicita, e
    -- l'intero UPDATE solleva 42804 — vedi l'intestazione di questo file.
    update public.orders set
      stato = case when p_esito = 'respinta'
                   then 'consegnato'::public.order_stato
                   else 'completato'::public.order_stato end,
      payout_stato = case when p_esito = 'respinta'
                          then 'trattenuto'::public.payout_stato
                          else 'in_attesa'::public.payout_stato end,
      contestato_at = null,
      contestazione_motivo = null
    where id = v_order.id returning * into v_order;

    perform private.tracking_registra(
      p_order_id, 'sistema',
      case when p_esito = 'respinta' then 'Contestazione respinta'
           else 'Contestazione risolta' end,
      p_nota);
  end if;

  insert into public.order_events (order_id, tipo, payload)
  values (p_order_id, 'contestazione_risolta', jsonb_build_object(
    'esito', p_esito, 'da_admin', v_uid is not null
  ));

  select * into v_order from public.orders where id = p_order_id;
  return v_order;
end;
$$;

-- `create or replace function` non azzera l'ACL di una funzione che esiste già,
-- quindi la chiusura della 7c resta in piedi da sola: sul progetto reale l'ACL
-- letto prima di questa migrazione è `postgres=X/postgres` e
-- `service_role=X/postgres`, senza anon, authenticated o PUBLIC.
-- Il revoke è ripetuto qui solo per sicurezza, ed è idempotente: dove le
-- migrazioni girano in ordine la 7c ha già chiuso la porta, e su un database
-- che non avesse ancora la funzione questa istruzione diventa l'unica
-- protezione, perché una funzione appena creata nasce eseguibile da PUBLIC.
-- Non serve a riparare nulla di rotto: costa zero e toglie un caso al ragionamento.
revoke execute on function
  public.ordine_contestazione_risolvi(uuid, public.dispute_stato, text)
  from public, anon, authenticated;
