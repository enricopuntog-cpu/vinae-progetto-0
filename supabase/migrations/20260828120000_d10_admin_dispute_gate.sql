-- ---------------------------------------------------------------------------
-- D10 — porta browser-admin per la risoluzione di una contestazione
-- ---------------------------------------------------------------------------
--
-- ADDITIVA. Nessun file distribuito viene modificato in place: vale la regola
-- 11 di CONTESTO_IA/03_ARCHITETTURA_REGOLE_DEBITI.md.
--
-- IL BUCO CHE QUESTA MIGRAZIONE CHIUDE
-- ====================================
-- La scheda «Controversie» del pannello di moderazione legge
-- public.moderation_dispute_queue — una vista `security_invoker = off` che
-- filtra su user_roles.role = 'admin' — e si ferma lì: mostra la pratica e non
-- ha alcun modo di chiuderla. L'unico motore di risoluzione è
-- public.ordine_contestazione_risolvi, la cui ACL, letta sul progetto reale, è
-- `postgres=X/postgres` e `service_role=X/postgres`. Dal browser non è
-- raggiungibile, ed è giusto così.
--
-- PERCHÉ NON SI CONCEDE SEMPLICEMENTE QUELLA RPC AD `authenticated`
-- ================================================================
-- Perché ha tre esiti e uno dei tre è `rimborsata`. Quel ramo non muove denaro
-- — la decisione (c) della 7f è esplicita: `rimborsato` lo scrive soltanto
-- payment_apply_provider_event, cioè un evento firmato e deduplicato del
-- fornitore — ma **dichiara un rimborso disposto** in tracking e lascia
-- l'ordine contestato con i fondi bloccati. È una leva che appartiene al
-- back-office, non a un pulsante di browser, finché refund e provider restano
-- spenti. Aprire la firma intera per ottenerne due terzi significherebbe
-- esporre anche il terzo.
--
-- Inoltre `ordine_contestazione_risolvi` è permissiva per costruzione verso il
-- chiamante senza `auth.uid()`: il suo controllo è «se c'è una sessione, deve
-- essere admin», forma corretta per service_role, che di sessione non ne ha.
-- Concessa ad `authenticated` resterebbe sicura per quel ramo, ma la sua
-- semantica di autorizzazione non è quella che serve a una porta di browser,
-- dove `auth.uid()` deve essere **obbligatorio** e non facoltativo.
--
-- LA FORMA SCELTA
-- ===============
-- Una porta stretta nuova che riusa il motore esistente invece di duplicarlo:
--
--   * `p_esito` è `text` e non `public.dispute_stato`. È deliberato. Con il
--     tipo enum in firma, `rimborsata` sarebbe un valore legale che una
--     validazione applicativa deve ricordarsi di respingere; con `text` più
--     lista chiusa, l'unico modo di raggiungere `rimborsata` è modificare
--     questo file. La lista è il confine, non un controllo aggiuntivo;
--   * l'esito ammesso viene castato all'enum una volta sola, dopo il
--     controllo, e passato al motore. Nessun ramo di questa funzione sa
--     scrivere su disputes, orders, payouts o payments: tutto ciò che accade
--     al dominio accade dentro `ordine_contestazione_risolvi`, con le sue
--     invarianti di denaro intatte;
--   * il ritorno è un `jsonb` di quattro campi e **non** `public.orders`. Una
--     SECURITY DEFINER che restituisce un rowtype consegna al chiamante ogni
--     colonna della tabella, i GRANT di colonna non si applicano al risultato
--     di una funzione, e public.orders ne ha di non esposte al client. La
--     scheda ha bisogno dell'esito, non della riga.
--
-- IDEMPOTENZA
-- ===========
-- Non ne viene inventata una nuova: `ordine_contestazione_risolvi` esce già
-- senza scrivere quando la pratica non è in ('aperta','in_valutazione').
-- Questa porta legge lo stato prima di chiamare per poterlo **riferire**
-- (`gia_chiusa`), così un secondo invio non produce né una seconda scrittura
-- né un errore che la scheda dovrebbe interpretare. Il `for update` sulla
-- riga di disputes serializza due moderatori che premono insieme: il secondo
-- attende, rilegge lo stato terminale scritto dal primo ed esce.
-- ---------------------------------------------------------------------------

create or replace function public.moderazione_contestazione_risolvi(
  p_order_id uuid,
  p_esito    text,
  p_nota     text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_nota    text := btrim(coalesce(p_nota, ''));
  v_dispute public.disputes%rowtype;
  v_esito   public.dispute_stato;
begin
  -- A differenza del motore, qui la sessione è obbligatoria: questa porta
  -- esiste per il browser di un moderatore, e un chiamante senza `auth.uid()`
  -- non è un caso da servire — è service_role, che ha già la sua.
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  -- Il ruolo reale, letto da user_roles. Il selettore Guest/User/Admin del
  -- frontend non arriva fin qui e non deve: è un ausilio locale, non un
  -- sistema di ruoli.
  if not public.has_role(v_uid, 'admin') then
    raise exception 'Non autorizzato a risolvere una contestazione.'
      using errcode = '42501';
  end if;

  -- La lista chiusa. `rimborsata` è assente per la ragione scritta in testa a
  -- questo file e non va aggiunta finché refund e provider restano spenti.
  if p_esito is null or p_esito not in ('risolta', 'respinta') then
    raise exception 'Esito non ammesso da questa porta: usa risolta o respinta.'
      using errcode = '22023';
  end if;

  -- La motivazione è obbligatoria qui e facoltativa nel motore. Non è una
  -- divergenza: una decisione di moderazione senza motivo scritto è ciò che il
  -- registro della Fase 9b vieta per le segnalazioni, e non c'è ragione per cui
  -- una controversia — che tocca denaro — debba esserne esente.
  if length(v_nota) = 0 then
    raise exception 'Una motivazione è obbligatoria.' using errcode = '22023';
  end if;
  if length(v_nota) > 1000 then
    raise exception 'Nota troppo lunga.' using errcode = '22023';
  end if;

  -- L'ordine è validato dal server: il client manda un id, non uno stato.
  if not exists (select 1 from public.orders o where o.id = p_order_id) then
    raise exception 'Ordine non trovato.' using errcode = 'P0001';
  end if;

  select * into v_dispute
  from public.disputes d
  where d.order_id = p_order_id
  for update;

  if not found then
    raise exception 'Nessuna contestazione da risolvere.' using errcode = 'P0001';
  end if;

  -- Pratica già terminale: nessuna chiamata al motore, nessuna scrittura, e lo
  -- stato reale torna al chiamante. Un retry non risolve due volte.
  if v_dispute.stato not in ('aperta', 'in_valutazione') then
    return jsonb_build_object(
      'order_id',      p_order_id,
      'dispute_stato', v_dispute.stato,
      'chiusura_at',   v_dispute.chiusura_at,
      'gia_chiusa',    true
    );
  end if;

  v_esito := p_esito::public.dispute_stato;

  -- Il motore. Tutta la semantica di dominio — azzeramento di contestato_at,
  -- stato dell'ordine, payout_stato, tracking, order_events — resta lì dentro,
  -- invariata. Il suo controllo di ruolo viene rieseguito su `auth.uid()`, che
  -- dentro una SECURITY DEFINER continua a essere l'utente reale: è una
  -- ridondanza voluta, non un residuo.
  perform public.ordine_contestazione_risolvi(p_order_id, v_esito, v_nota);

  select * into v_dispute from public.disputes d where d.order_id = p_order_id;

  return jsonb_build_object(
    'order_id',      p_order_id,
    'dispute_stato', v_dispute.stato,
    'chiusura_at',   v_dispute.chiusura_at,
    'gia_chiusa',    false
  );
end;
$$;

comment on function public.moderazione_contestazione_risolvi(uuid, text, text) is
  'Porta browser-admin per chiudere una contestazione. Ammette i soli esiti '
  'risolta e respinta: rimborsata resta fuori dalla firma finché refund e '
  'provider sono spenti. Richiede auth.uid() e il ruolo reale admin, valida '
  'ordine e motivazione, e delega a ordine_contestazione_risolvi senza '
  'duplicarne la semantica. Ritorna un jsonb stretto, mai la riga di orders.';

-- Una funzione appena creata nasce eseguibile da PUBLIC: il revoke è la prima
-- cosa che conta in questo file.
--
-- `service_role` è nell'elenco per una ragione che non si vede leggendo questo
-- file da solo. Il progetto Supabase porta un
-- `alter default privileges in schema public grant all on functions to postgres,
-- anon, authenticated, service_role`, quindi la funzione **nasce già** con
-- `service_role=X`: non concederla non basta a non dargliela. Verificato
-- sull'istanza locale — senza questa riga l'ACL risultante è
-- `postgres=X/postgres service_role=X/postgres authenticated=X/postgres`.
-- Il caso 34 della griglia asserisce l'assenza proprio perché l'omissione
-- silenziosa sarebbe passata inosservata.
revoke all on function public.moderazione_contestazione_risolvi(uuid, text, text)
  from public, anon, service_role;

-- `authenticated` è il ruolo con cui arriva il browser del moderatore, e resta
-- l'unico: il filtro non è il GRANT ma il controllo di ruolo in testa alla
-- funzione, che respinge con 42501 chiunque non sia admin per davvero.
--
-- `service_role` **non** la riceve. Non perché sarebbe pericolosa — non lo
-- sarebbe, `auth.uid()` è obbligatorio e una chiave di servizio non porta
-- `sub`, quindi la chiamata morirebbe alla prima riga — ma proprio per questo:
-- sarebbe un permesso che non può essere esercitato. E un permesso inutile su
-- una porta di autorizzazione non è neutro, è una trappola: invita a leggere
-- «il back-office passa di qui», e il primo che ci prova trova un 42501 e ha
-- davanti a sé la tentazione di rendere facoltativo `auth.uid()` per far
-- funzionare il GRANT. La regressione nascerebbe lì. Il back-office ha già la
-- sua porta, `ordine_contestazione_risolvi`, completa dei tre esiti.
grant execute on function public.moderazione_contestazione_risolvi(uuid, text, text)
  to authenticated;
