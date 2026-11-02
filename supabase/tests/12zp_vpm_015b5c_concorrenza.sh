#!/usr/bin/env bash
# VPM-015B5C: sessioni PostgreSQL reali, SOLO gate CI su stack effimero.
# NON eseguire su produzione o su uno stack condiviso. Nessun provider chiamato.
# E2E_DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres bash "$0"
# 8 prove: preparazione duplicata; webhook/rilascio; rilascio duplicato;
# contestazione/rilascio con finestra aperta e scaduta; retry stessa chiave;
# storno dopo accredito; quadratura finale.
# Fixture minime di post-vendita, non una seconda prova del checkout B5A/B5B:
# snapshot sintetici inseriti con trigger sospesi SOLO nella transazione fixture.
# I conti pending sono invece aperti dalla funzione B5C reale. Importi inventati.
# Nessun flag viene acceso: snapshot prima/dopo e verifica anche nel trap EXIT.
set -euo pipefail

DB_URL="${E2E_DB_URL:-}"
[ -n "$DB_URL" ] || { echo 'E2E_DB_URL mancante.' >&2; exit 2; }
# Rifiuta query/options, host multipli, socket e ref ospitati: libpq non deve
# poter reinterpretare una URL apparentemente loopback tramite ?host=... .
case "$DB_URL" in
  postgresql://* | postgres://*) ;;
  *) echo 'Richiesta URL PostgreSQL esplicita.' >&2; exit 3 ;;
esac
case "$DB_URL" in *pijnmcllmfgjmgsvtcej* | *\?* | *\#* | *,*) echo 'URL non ammessa.' >&2; exit 3 ;; esac
rest="${DB_URL#*://}"; authority="${rest%%/*}"; authority="${authority##*@}"
case "$authority" in
  localhost:[0-9]* | 127.0.0.1:[0-9]* | '[::1]:'[0-9]*) ;;
  *) echo 'Richiesto database loopback con porta esplicita.' >&2; exit 3 ;;
esac
# Non ereditare opzioni libpq che possano cambiare il target o il search_path.
unset PGHOST PGHOSTADDR PGPORT PGDATABASE PGUSER PGSERVICE PGSERVICEFILE PGOPTIONS \
  PGPASSFILE PGSSLMODE PGSSLROOTCERT PGSSLCERT PGSSLKEY PGTARGETSESSIONATTRS
export PGCONNECT_TIMEOUT=5
PSQL=(psql "$DB_URL" -X -qAt -v ON_ERROR_STOP=1 --no-psqlrc)
sql() { "${PSQL[@]}" -c "$1"; }
# L'URL è loopback, ma dietro un port-forward Docker il server vede il proprio
# indirizzo sulla rete del container (bridge, es. 172.17.0.2): vale loopback OPPURE
# 172.16.0.0/12 (reti Docker). Non è una prova di "stack effimero": un tunnel verso un
# database privato con quell'intervallo la supererebbe, perciò la difesa decisiva sono
# i controlli sui dati qui sotto (nessun utente reale), non l'indirizzo.
[ "$(sql "select coalesce(inet_server_addr() <<= any (array['127.0.0.0/8','172.16.0.0/12','::1/128']::inet[]), false)")" = t ] \
  || { echo 'Server né loopback né su rete Docker locale.' >&2; exit 3; }
[ "$(sql "select count(*) from auth.users where email is null or email not like '%.test'")" = 0 ] \
  || { echo 'Rifiutato: utenti non sintetici.' >&2; exit 3; }

RUN="$(sql 'select gen_random_uuid()')"
U1="$(sql 'select gen_random_uuid()')" # venditore esclusivo di questa esecuzione
U2="$(sql 'select gen_random_uuid()')" # acquirente
PREFIX="12zp-$RUN"
FLAGS_SQL="select jsonb_build_array(
 (select to_jsonb(i) from private.cantina_accessori_impostazioni i),
 (select to_jsonb(i) from private.annunci_accessori_impostazioni i),
 (select to_jsonb(i) from private.accessori_logistica_impostazioni i),
 (select to_jsonb(i) from private.accessori_checkout_impostazioni i))::text"
FLAGS_PRIMA="$(sql "$FLAGS_SQL")"
TMP="$(mktemp -d)"
passed=0; total=0; owned=0; holder=''; pa=''; pb=''; ALL_ORDINI='{}'
esito() {
  total=$((total + 1))
  if [ "$2" = t ]; then passed=$((passed + 1)); echo "PASS $total $1"
  else echo "FAIL $total $1"; fi
}

pulizia() {
  "${PSQL[@]}" <<SQL
begin;
set local statement_timeout = '15s';
set local session_replication_role = replica;
-- Prima i figli B5C, poi pagamenti/ordini e infine il libro e i profili.
delete from private.accessori_rimborsi_evidenze where pagamento_id in (select id from private.accessori_pagamenti where buyer_id = '$U2');
delete from private.accessori_resi where ordine_id in (select id from private.accessori_ordini where seller_id = '$U1');
delete from private.accessori_rimborsi where ordine_id in (select id from private.accessori_ordini where seller_id = '$U1');
delete from private.accessori_contestazioni where ordine_id in (select id from private.accessori_ordini where seller_id = '$U1');
delete from private.accessori_postvendita_eventi where ordine_id in (select id from private.accessori_ordini where seller_id = '$U1');
delete from private.accessori_postvendita where seller_id = '$U1';
delete from private.accessori_pagamenti where buyer_id = '$U2';
delete from private.accessori_ordini where seller_id = '$U1';
delete from public.payment_provider_events where provider = 'stripe' and starts_with(event_id, '$PREFIX:');
delete from public.balance_movimenti where owner_id in ('$U1', '$U2');
delete from public.balance_accounts where owner_id in ('$U1', '$U2');
delete from public.notifications where recipient_id in ('$U1', '$U2');
delete from public.user_roles where user_id in ('$U1', '$U2');
delete from public.profiles where id in ('$U1', '$U2');
delete from auth.users where id in ('$U1', '$U2');
commit;
SQL
}
residui() {
  sql "select
    (select count(*) from auth.users where id in ('$U1','$U2')) +
    (select count(*) from public.profiles where id in ('$U1','$U2')) +
    (select count(*) from public.user_roles where user_id in ('$U1','$U2')) +
    (select count(*) from public.notifications where recipient_id in ('$U1','$U2')) +
    (select count(*) from private.accessori_ordini where seller_id = '$U1') +
    (select count(*) from private.accessori_rimborsi_evidenze where pagamento_id in (select id from private.accessori_pagamenti where ordine_id = any('$ALL_ORDINI'::uuid[]))) +
    (select count(*) from private.accessori_pagamenti where buyer_id = '$U2') +
    (select count(*) from private.accessori_postvendita where seller_id = '$U1') +
    (select count(*) from private.accessori_resi where ordine_id = any('$ALL_ORDINI'::uuid[])) +
    (select count(*) from private.accessori_rimborsi where ordine_id = any('$ALL_ORDINI'::uuid[])) +
    (select count(*) from private.accessori_postvendita_eventi where ordine_id = any('$ALL_ORDINI'::uuid[])) +
    (select count(*) from private.accessori_contestazioni where aperta_da = '$U2') +
    (select count(*) from public.payment_provider_events where provider = 'stripe' and starts_with(event_id, '$PREFIX:')) +
    (select count(*) from public.balance_movimenti where owner_id in ('$U1','$U2')) +
    (select count(*) from public.balance_accounts where owner_id in ('$U1','$U2'))"
}
finale() {
  local status=$? r='?' flags='?'
  trap - EXIT INT TERM
  # Arresta solo le sessioni marcate da QUESTO run, prima di eliminare fixture.
  sql "select pg_terminate_backend(pid) from pg_stat_activity
       where application_name in ('$PREFIX-holder','$PREFIX-a','$PREFIX-b') and pid <> pg_backend_pid()" >/dev/null 2>&1 || status=1
  for pid in "$pa" "$pb" "$holder"; do
    if [ -n "$pid" ]; then wait "$pid" 2>/dev/null || true; fi
  done
  if [ "$owned" = 1 ]; then
    ALL_ORDINI="$(sql "select coalesce(array_agg(id),'{}'::uuid[]) from private.accessori_ordini where seller_id='$U1'")" || status=1
    pulizia >"$TMP/cleanup" 2>&1 || { cat "$TMP/cleanup" >&2; status=1; }
  fi
  r="$(residui)" || status=1
  flags="$(sql "$FLAGS_SQL")" || status=1
  # Non sovrascrivere una variazione estranea: questo script non modifica flag.
  # In caso di differenza fallisce invece di ripristinare dati di un altro job.
  [ "$flags" = "$FLAGS_PRIMA" ] || status=1
  [ "$r" = 0 ] && [ "$total" = 8 ] && [ "$passed" = "$total" ] || status=1
  rm -rf -- "$TMP"
  echo "12zp concorrenza: $passed/$total; residui: $r; flag invariati: $([ "$flags" = "$FLAGS_PRIMA" ] && echo si || echo NO)"
  exit "$status"
}
trap finale EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# Gli UUID sono nuovi: nessuna pulizia preventiva di eventuali fixture altrui.
owned=1
"${PSQL[@]}" <<SQL
begin;
set local session_replication_role = replica;
insert into auth.users (id,email,email_confirmed_at,raw_user_meta_data) values
 ('$U1','seller-$RUN@conc-12zp.test',now(),'{}'),('$U2','buyer-$RUN@conc-12zp.test',now(),'{}');
insert into public.profiles (id,username,dob) values
 ('$U1','s-' || left('$RUN',18),'1980-01-01'),('$U2','b-' || left('$RUN',18),'1980-01-01');
insert into public.user_roles (user_id,role) values ('$U1','user'),('$U2','user');
commit;
SQL

# Crea snapshot pagato coerente. Nessun annuncio/Cantina/Storage/logistica
# necessario per le porte post-vendita: i riferimenti snapshot non hanno FK.
fixture() {
  local tag=$1 ord
  ord="$(sql 'select gen_random_uuid()')"
  "${PSQL[@]}" >/dev/null <<SQL
begin;
set local session_replication_role = replica;
insert into private.accessori_ordini (
 id,buyer_id,seller_id,annuncio_id,cantina_accessorio_id,preventivo_id,chiave_idempotenza,
 stato,articolo_nome,articolo_condizione,quantita,prezzo_unitario_cents,prezzo_cents,
 commissione_cents,copertura_pagamento_cents,logistica_cents,totale_acquirente_cents,
 venditore_classe,margine_obiettivo_bps,riferimento_percentuale_bps,riferimento_fisso_cents,
 colli,pezzi_per_collo,logistica_config_versione,logistica_dettaglio,scade_at,pagato_at,pagamento_modo)
values ('$ord','$U2','$U1',gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),'$PREFIX:$tag',
 'pagato','Calice sintetico B5C','come_nuovo',1,2000,2000,160,40,800,3000,
 'privato',800,209,25,1,1,1,'{}',now()+interval '15 minutes',now(),'provider');
insert into private.accessori_pagamenti
 (ordine_id,buyer_id,provider,provider_session_id,provider_intent_id,stato,amount_cents,currency)
values ('$ord','$U2','stripe','pi_$ord','pi_$ord','paid',3000,'eur');
commit;
-- Qui i trigger e le funzioni di contabilita sono nuovamente tutti attivi.
begin;
select private.accessori_postvendita_apri('$ord');
select public.accessori_consegna_vettore_registra('$ord','consegna sintetica',now());
commit;
SQL
  echo "$ord"
}
scadenza() {
  # Viaggio temporale di prova: trigger sospesi solo in questa transazione,
  # nessuna ALTER TABLE globale. Finestra sempre esattamente 48h dalla consegna.
  sql "begin; set local session_replication_role = replica;
    update private.accessori_postvendita set
      consegnato_at = now() + interval '$2' - interval '48 hours',
      finestra_scade_at = now() + interval '$2' where ordine_id = '$1'; commit;" >/dev/null
}

# Holder con FIFO: nessuna durata fissa per la barriera. Si apre SOLO quando
# pg_locks mostra ENTRAMBI i partecipanti effettivamente in attesa advisory.
avvia() {
  mkfifo "$TMP/holder-in"
  exec 9<>"$TMP/holder-in"
  PGAPPNAME="$PREFIX-holder" "${PSQL[@]}" <"$TMP/holder-in" >"$TMP/holder-out" 2>&1 & holder=$!
  printf "begin;\nselect pg_advisory_xact_lock(hashtextextended('%s',0));\n" "$RUN" >&9
  attendi "select count(*) from pg_locks l join pg_stat_activity a on a.pid=l.pid
    where a.application_name='$PREFIX-holder' and l.locktype='advisory' and l.granted" 1
}
attendi() {
  local i
  for i in {1..200}; do
    [ "$(sql "$1")" = "$2" ] && return 0
    sleep 0.05
  done
  echo "Timeout barriera: $1" >&2; return 1
}
worker() {
  local nome=$1 ruolo=$2 uid=$3 corpo=$4
  PGAPPNAME="$PREFIX-$nome" "${PSQL[@]}" <<SQL
begin;
set local statement_timeout = '20s';
select pg_advisory_xact_lock_shared(hashtextextended('$RUN',0)) \g /dev/null
select set_config('request.jwt.claims',json_build_object('sub','$uid','role','$ruolo')::text,true) \g /dev/null
select set_config('request.jwt.claim.sub','$uid',true) \g /dev/null
set local role $ruolo;
$corpo
commit;
SQL
}
corsa() {
  local ruolo1=$1 uid1=$2 corpo1=$3 ruolo2=$4 uid2=$5 corpo2=$6
  avvia
  worker a "$ruolo1" "$uid1" "$corpo1" >"$TMP/a" 2>&1 & pa=$!
  worker b "$ruolo2" "$uid2" "$corpo2" >"$TMP/b" 2>&1 & pb=$!
  attendi "select count(*) from pg_locks l join pg_stat_activity a on a.pid=l.pid
    where a.application_name in ('$PREFIX-a','$PREFIX-b') and l.locktype='advisory' and not l.granted" 2
  printf 'commit;\n\\q\n' >&9
  ra=0; rb=0
  wait "$pa" || ra=$?; wait "$pb" || rb=$?; wait "$holder"
  pa=''; pb=''; holder=''; exec 9>&-; rm -- "$TMP/holder-in"
  if [ "$ra" != 0 ] || [ "$rb" != 0 ]; then cat "$TMP/a" "$TMP/b" >&2; return 1; fi
}
# Una sola riga precisa: il nucleo privato e lo stesso chiamato dallo scheduler.
# Evita che la prova rilasci ordini sintetici di altri job presenti nello stack.
rilascio() { echo "reset role; select private.accessori_ricavo_rilascia_uno('$1');"; }
movimenti() {
  sql "select count(*) from public.balance_movimenti where owner_id='$U1'
    and idempotency_key='accessori:' || replace('$1','-','') || ':$2'"
}

# 1. Rimborso amministrativo sintetico gia dovuto: due worker di invio
# devono ricevere la stessa chiave, non due richieste economiche diverse.
O1="$(fixture prep)"
R1="$(sql "insert into private.accessori_rimborsi (ordine_id,pagamento_id,origine,importo_cents)
 select ordine_id,id,'contestazione',500 from private.accessori_pagamenti where ordine_id='$O1' returning id")"
corsa service_role '' "select coalesce(x->>'idempotency_key',x->>'motivo') from (select public.accessori_rimborso_prepara('$R1') x) q;" \
      service_role '' "select coalesce(x->>'idempotency_key',x->>'motivo') from (select public.accessori_rimborso_prepara('$R1') x) q;"
K="vinea-rimborso-accessori-${O1//-/}-contestazione-500"
esito 'doppia preparazione: una richiesta e un invio, concorrente bloccato dal backoff' "$(sql "select
 (select count(*)=1 and min(tentativi)=1 and min(stato)='in_invio' and min(idempotency_key)='$K'
  from private.accessori_rimborsi where ordine_id='$O1')")"
a="$(<"$TMP/a")"; b="$(<"$TMP/b")"
[ "$a/$b" = "$K/retry_backoff" ] || [ "$a/$b" = "retry_backoff/$K" ] || exit 1

# 2. Webhook charge.refunded autorevole contro rilascio: storno parziale 500.
# Il rilascio usa SKIP LOCKED: se perde, il successivo giro deve convergere.
O2="$(fixture webhook)"; scadenza "$O2" '-1 hour'
corsa service_role '' "select public.accessori_pagamento_applica_evento('stripe','$PREFIX:refund',
 'refunded',extract(epoch from now())::bigint,jsonb_build_object('intent_id','pi_$O2',
 'provider_event_type','charge.refunded','amount_cents',3000,'amount_refunded',500,'currency','eur'));" \
      service_role '' "$(rilascio "$O2")"
[ "$(<"$TMP/a")" = processed ] || exit 1
sql "select private.accessori_ricavo_rilascia_uno('$O2')" >/dev/null
esito 'webhook contro rilascio: storno 500, ricavo disponibile 1500, una sola liberazione' "$(sql "select
 (select ricavo_stato='rilasciato' and ricavo_stornato_cents=500 from private.accessori_postvendita where ordine_id='$O2')
 and (select stato='partially_refunded' and amount_refunded_cents=500 from private.accessori_pagamenti where ordine_id='$O2')
 and (select sum(delta_pending_cents)=0 and sum(delta_available_cents)=1500 and count(*)=3
 from public.balance_movimenti where owner_id='$U1' and starts_with(idempotency_key,'accessori:' || replace('$O2','-','') || ':'))")"

# 3. Due rilasci sullo stesso ordine maturo: esattamente uno true.
O3="$(fixture double)"; scadenza "$O3" '-1 hour'
corsa service_role '' "$(rilascio "$O3")" service_role '' "$(rilascio "$O3")"
a="$(<"$TMP/a")"; b="$(<"$TMP/b")"
[ "$a/$b" = t/f ] || [ "$a/$b" = f/t ] || exit 1
esito 'due rilasci: una scrittura ledger e un evento' "$(sql "select
 (select count(*)=1 from public.balance_movimenti where owner_id='$U1' and idempotency_key='accessori:' || replace('$O3','-','') || ':vendita_disponibile')
 and (select count(*)=1 from private.accessori_postvendita_eventi where ordine_id='$O3' and evento='ricavo_rilasciato')")"

# 4/5. Non inventare una sovrapposizione temporale impossibile: nella stessa
# finestra aprire e rilasciare non sono entrambi ammissibili. Proviamo entrambe
# le finestre, con contesa reale sullo stesso ordine e hint esatto sul rifiuto.
for finestra in aperta scaduta; do
  O="$(fixture "$finestra")"
  if [ "$finestra" = aperta ]; then scadenza "$O" '1 hour'; else scadenza "$O" '-1 hour'; fi
  contestazione="do \$c\$ declare h text; begin
    perform public.accessori_contestazione_apri('$O','Articolo rotto','Prova sintetica B5C','{}');
    if '$finestra' = 'scaduta' then raise exception 'Contestazione tardiva accettata'; end if;
    exception when sqlstate '22023' then
      get stacked diagnostics h = pg_exception_hint;
      if '$finestra' <> 'scaduta' or h is distinct from 'finestra_scaduta' then raise; end if;
    end \$c\$;"
  corsa authenticated "$U2" "$contestazione" service_role '' "$(rilascio "$O")"
  if [ "$finestra" = aperta ]; then
    esito 'contestazione contro rilascio, finestra aperta: contestazione presente, zero rilascio' "$(sql "select
      (select count(*)=1 from private.accessori_contestazioni where ordine_id='$O' and stato='aperta')
      and (select ricavo_stato='trattenuto' from private.accessori_postvendita where ordine_id='$O')
      and $(movimenti "$O" vendita_disponibile)=0")"
  else
    # Se il worker contestazione teneva il lock, il primo rilascio salta.
    sql "select private.accessori_ricavo_rilascia_uno('$O')" >/dev/null
    esito 'contestazione contro rilascio, finestra scaduta: hint preciso, una liberazione' "$(sql "select
      not exists(select 1 from private.accessori_contestazioni where ordine_id='$O')
      and (select ricavo_stato='rilasciato' from private.accessori_postvendita where ordine_id='$O')
      and $(movimenti "$O" vendita_disponibile)=1")"
  fi
done

# 6. Fallimento/retry dell'invio: stessa operazione provider e stessa chiave,
# anche se due scheduler riprendono contemporaneamente la richiesta fallita.
sql "select public.accessori_rimborso_registra_esito('$R1',false,null,'errore sintetico')" >/dev/null
# Backoff trascorso nella sola fixture, senza attese reali né cambio della chiave.
sql "begin; set local session_replication_role = replica;
 update private.accessori_rimborsi set aggiornato_at=now()-interval '2 hours' where id='$R1'; commit;" >/dev/null
corsa service_role '' "select coalesce(x->>'idempotency_key',x->>'motivo') from (select public.accessori_rimborso_prepara('$R1') x) q;" \
      service_role '' "select coalesce(x->>'idempotency_key',x->>'motivo') from (select public.accessori_rimborso_prepara('$R1') x) q;"
a="$(<"$TMP/a")"; b="$(<"$TMP/b")"
[ "$a/$b" = "$K/retry_backoff" ] || [ "$a/$b" = "retry_backoff/$K" ] || exit 1
corsa service_role '' "select public.accessori_rimborso_registra_esito('$R1',true,'re_$RUN',null);" \
      service_role '' "select public.accessori_rimborso_registra_esito('$R1',true,'re_$RUN',null);"
esito 'retry: chiave stabile, una richiesta e una registrazione provider, non ancora eseguito' "$(sql "select
 (select count(*)=1 and min(stato)='inviato' and min(tentativi)=2 and min(idempotency_key)='$K'
    and min(provider_refund_id)='re_$RUN' from private.accessori_rimborsi where ordine_id='$O1')
 and (select count(*)=1 from private.accessori_postvendita_eventi where ordine_id='$O1' and evento='rimborso_inviato')")"

# 7. Ordinamento esplicito: prima accredito, poi DUE consegne parallele dello
# stesso webhook. La rettifica e sul disponibile, non sul pending, una volta.
O6="$(fixture storno)"; scadenza "$O6" '-1 hour'
[ "$(sql "select private.accessori_ricavo_rilascia_uno('$O6')")" = t ] || exit 1
REFUND="select public.accessori_pagamento_applica_evento('stripe','$PREFIX:after-release',
 'refunded',extract(epoch from now())::bigint,jsonb_build_object('intent_id','pi_$O6',
 'provider_event_type','charge.refunded','amount_cents',3000,'amount_refunded',500,'currency','eur'));"
corsa service_role '' "$REFUND" service_role '' "$REFUND"
a="$(<"$TMP/a")"; b="$(<"$TMP/b")"
[ "$a/$b" = processed/duplicate ] || [ "$a/$b" = duplicate/processed ] || exit 1
esito 'storno dopo accredito e webhook duplicato: una rettifica disponibile -500' "$(sql "select
 (select count(*)=1 and sum(delta_pending_cents)=0 and sum(delta_available_cents)=-500
  from public.balance_movimenti where owner_id='$U1' and tipo='rettifica_rimborso'
    and starts_with(idempotency_key,'accessori:' || replace('$O6','-','') || ':'))
 and (select ricavo_stato='rilasciato' and ricavo_stornato_cents=500 from private.accessori_postvendita where ordine_id='$O6')
 and (select count(*)=1 from public.payment_provider_events where provider='stripe' and event_id='$PREFIX:after-release')")"

esito 'quadratura conti/ledger e unicita eventi di rilascio per i soli utenti fixture' "$(sql "select
 (select pending_cents=4000 and available_cents=7000 and reserved_cents=0
    and pending_cents=(select sum(delta_pending_cents) from public.balance_movimenti where owner_id='$U1')
    and available_cents=(select sum(delta_available_cents) from public.balance_movimenti where owner_id='$U1')
  from public.balance_accounts where owner_id='$U1' and currency='eur')
 and not exists(select 1 from private.accessori_postvendita_eventi e
   join private.accessori_ordini o on o.id=e.ordine_id where o.seller_id='$U1' and e.evento='ricavo_rilasciato'
   group by e.ordine_id having count(*)>1)")"
