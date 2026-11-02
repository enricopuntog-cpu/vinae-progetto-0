#!/usr/bin/env bash
# VPM-015QA-FINAL-A - annullamento contro pagamento aperto e ultima unita Partner su SESSIONI
# POSTGRESQL SEPARATE (concorrenza reale). 12 prove: 1-8 annullo/pagamento (apertura, collegato,
# processing, incasso, doppio annullo, scaduta, processing scaduto, expired); 9-12 Partner
# (ultima unita, incasso, sospensione/revoca, aliquote e vino invariati). Nessuna chiamata a Stripe.
#
# SOLO stack locale/effimero: loopback + nonce di identita (E2E_STACK_NONCE, scritto da 12g_ci_run.sh).
# Fixture `@conc-12zs.test` rimosse in trap EXIT, residui = 0, interruttori (compreso
# vendita_partner) ripristinati e verificati.
#
#   E2E_DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres E2E_STACK_NONCE=... #   bash supabase/tests/12zs_vpm_qa_final_a_concorrenza.sh

set -euo pipefail

readonly PRODUCTION_REF="pijnmcllmfgjmgsvtcej"
DB_URL="${E2E_DB_URL:-}"
[ -n "$DB_URL" ] || { echo "E2E_DB_URL mancante." >&2; exit 2; }
case "$DB_URL" in *"$PRODUCTION_REF"*) echo "Rifiutato: ref di produzione." >&2; exit 3 ;; esac
rest="${DB_URL#*://}"; authority="${rest%%[/?#]*}"; authority="${authority##*@}"; host="${authority%%:*}"
case "$host" in 127.0.0.1 | localhost | ::1) ;; *) echo "Rifiutato: database non su loopback ($host)." >&2; exit 3 ;; esac

PSQL=(psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 --no-psqlrc -At)
sql() { "${PSQL[@]}" -c "$1"; }

# Prova di identita dello stack effimero (come 12zp): il runner del gate scrive il nonce nel commento
# del database; senza nonce o con marcatore diverso lo script non tocca nulla.
NONCE="${E2E_STACK_NONCE:-}"
[ -n "$NONCE" ] && [ "${#NONCE}" -ge 16 ] \
  || { echo "E2E_STACK_NONCE mancante: identita dello stack effimero non dimostrata." >&2; exit 3; }
[ "$(sql "select coalesce(shobj_description((select oid from pg_database where datname = current_database()), 'pg_database'), '')")" = "vinea-ephemeral-stack:$NONCE" ] \
  || { echo "Marcatore dello stack effimero assente o diverso: rifiutato." >&2; exit 3; }

readonly DOMINIO="conc-12zs.test"
readonly PROVIDER="conc_qfa"
readonly BARRIERA=424245
readonly U1="12f70000-0000-4000-8000-0000000000d1"   # venditore
readonly U2="12f70000-0000-4000-8000-0000000000d2"   # admin con ruolo di rilascio
readonly U3="12f70000-0000-4000-8000-0000000000d3"   # acquirente A
readonly U4="12f70000-0000-4000-8000-0000000000d4"   # acquirente B
readonly U5="12f70000-0000-4000-8000-0000000000d5"   # acquirente C
readonly U6="12f70000-0000-4000-8000-0000000000d6"   # Vinea Partner

[ "$(sql "select count(*) from auth.users where email not like '%.test'")" = "0" ] \
  || { echo "Rifiutato: il database contiene utenti reali." >&2; exit 3; }
[ "$(sql "select count(*) from private.annunci_accessori_categorie_pubblicabili")" = "0" ] \
  || { echo "Rifiutato: il database ha gia categorie approvate alla pubblicazione." >&2; exit 3; }
[ "$(sql "select count(*) from private.accessori_logistica_tariffe")" = "0" ] \
  || { echo "Rifiutato: il database ha gia tariffe Accessori." >&2; exit 3; }
[ "$(sql "select count(*) from private.accessori_ordini")" = "0" ] \
  || { echo "Rifiutato: il database ha gia ordini Accessori." >&2; exit 3; }

FUNZ_PRIMA="$(sql "select funzione_attiva from private.cantina_accessori_impostazioni")"
PREP_PRIMA="$(sql "select preparazione_attiva from private.annunci_accessori_impostazioni")"
PUBB_PRIMA="$(sql "select pubblicazione_attiva from private.annunci_accessori_impostazioni")"
LOGI_PRIMA="$(sql "select logistica_attiva from private.accessori_logistica_impostazioni")"
LVERS_PRIMA="$(sql "select versione from private.accessori_logistica_impostazioni")"
CHK_PRIMA="$(sql "select checkout_attivo from private.accessori_checkout_impostazioni")"
CVERS_PRIMA="$(sql "select versione from private.accessori_checkout_impostazioni")"
DA1_PRIMA="$(sql "select coalesce(aggiornato_da::text, 'null') from private.cantina_accessori_impostazioni")"
DA2_PRIMA="$(sql "select coalesce(aggiornato_da::text, 'null') from private.annunci_accessori_impostazioni")"
DA3_PRIMA="$(sql "select coalesce(aggiornato_da::text, 'null') from private.accessori_logistica_impostazioni")"
DA4_PRIMA="$(sql "select coalesce(aggiornato_da::text, 'null') from private.accessori_checkout_impostazioni")"

VP_PRIMA="$(sql "select vendita_partner from private.inventario_impostazioni")"
passed=0
total=0
esito() {
  total=$((total + 1))
  if [ "$2" = "ok" ]; then
    passed=$((passed + 1)); echo "PASS $1"
  else
    echo "FAIL $1 :: $2"
  fi
}

pulizia() {
  "${PSQL[@]}" <<SQL
begin;
set local session_replication_role = replica;
select set_config('vinae.accessori_ordini_pulizia', 'on', true) \g /dev/null
-- B5C: l'ordine pagato via provider apre il post-vendita e il ricavo pending del
-- venditore; vanno tolti prima di pagamenti e ordini, figli per primi.
delete from private.accessori_rimborsi_evidenze
  where pagamento_id in (select id from private.accessori_pagamenti where buyer_id in ('$U3', '$U4', '$U5'));
delete from private.accessori_resi where ordine_id in (select id from private.accessori_ordini where seller_id in ('$U1', '$U6'));
delete from private.accessori_rimborsi where ordine_id in (select id from private.accessori_ordini where seller_id in ('$U1', '$U6'));
delete from private.accessori_contestazioni where ordine_id in (select id from private.accessori_ordini where seller_id in ('$U1', '$U6'));
delete from private.accessori_postvendita_eventi where ordine_id in (select id from private.accessori_ordini where seller_id in ('$U1', '$U6'));
delete from private.accessori_postvendita where seller_id in ('$U1', '$U6');
delete from public.balance_movimenti where owner_id in ('$U1', '$U3', '$U4', '$U5', '$U6');
delete from public.balance_accounts where owner_id in ('$U1', '$U3', '$U4', '$U5', '$U6');
delete from private.accessori_pagamenti where buyer_id in ('$U3', '$U4', '$U5');
delete from private.accessori_ordini where buyer_id in ('$U3', '$U4', '$U5') or seller_id in ('$U1', '$U6');
delete from private.accessori_logistica_preventivi where buyer_id in ('$U3', '$U4', '$U5');
delete from private.annunci_accessori_logistica
  where annuncio_id in (select id from private.annunci_accessori where seller_id in ('$U1', '$U6'));
delete from public.audit_log where target_tipo = 'annuncio_accessorio'
  and target_id in (select id from private.annunci_accessori where seller_id in ('$U1', '$U6'));
delete from private.annunci_accessori_snapshot
  where annuncio_id in (select id from private.annunci_accessori where seller_id in ('$U1', '$U6'));
delete from private.annunci_accessori where seller_id in ('$U1', '$U6');
delete from storage.objects where bucket_id = 'cantina-accessori-foto' and (name like '$U1/%' or name like '$U6/%');
delete from private.accessori_partner_movimenti where partner_id in (select id from private.partners where titolare_id = '$U6');
delete from private.partner_eventi where partner_id in (select id from private.partners where titolare_id = '$U6');
delete from private.partner_vetrine where partner_id in (select id from private.partners where titolare_id = '$U6');
delete from private.partner_riabilitazioni where partner_id in (select id from private.partners where titolare_id = '$U6');
delete from private.cantina_accessori where owner_id in ('$U1', '$U6');
delete from private.partners where titolare_id = '$U6';
delete from private.partner_inviti where email like '%@$DOMINIO' or creato_da = '$U2';
delete from public.audit_log where attore_id in ('$U2', '$U6');
delete from private.annunci_accessori_categorie_pubblicabili where approvata_da = '$U2';
delete from private.accessori_logistica_tariffe where provider_code = '$PROVIDER';
delete from private.logistics_service_pudo_networks
  where service_definition_id in (select id from private.logistics_service_definitions where provider_code = '$PROVIDER');
delete from private.logistics_service_capabilities
  where service_definition_id in (select id from private.logistics_service_definitions where provider_code = '$PROVIDER');
delete from private.logistics_service_definitions where provider_code = '$PROVIDER';
delete from private.logistics_pudo_networks where provider_code = '$PROVIDER';
delete from private.accessori_registro where admin_id = '$U2';
delete from public.payment_provider_events where provider = 'stripe' and event_id like 'conc-evs-%';
delete from private.rate_limit_buckets where subject in ('user:$U1', 'user:$U3', 'user:$U4', 'user:$U5', 'user:$U6', 'user:$U2');
delete from public.notifications where recipient_id in ('$U1', '$U2', '$U3', '$U4', '$U5', '$U6');
delete from public.user_roles where user_id in ('$U1', '$U2', '$U3', '$U4', '$U5', '$U6');
delete from public.profiles where id in ('$U1', '$U2', '$U3', '$U4', '$U5', '$U6');
delete from auth.users where id in ('$U1', '$U2', '$U3', '$U4', '$U5', '$U6');
commit;
SQL
}

residui() {
  sql "select (select count(*) from auth.users where email like '%@$DOMINIO')
            + (select count(*) from private.annunci_accessori where seller_id in ('$U1', '$U6'))
            + (select count(*) from private.cantina_accessori where owner_id in ('$U1', '$U6'))
            + (select count(*) from private.accessori_ordini where seller_id in ('$U1', '$U6'))
            + (select count(*) from private.accessori_pagamenti where buyer_id in ('$U3', '$U4', '$U5'))
            + (select count(*) from public.payment_provider_events where provider = 'stripe' and event_id like 'conc-evs-%')
            + (select count(*) from private.accessori_logistica_preventivi where buyer_id in ('$U3', '$U4', '$U5'))
            + (select count(*) from private.accessori_logistica_tariffe where provider_code = '$PROVIDER')
            + (select count(*) from private.logistics_service_definitions where provider_code = '$PROVIDER')
            + (select count(*) from private.logistics_pudo_networks where provider_code = '$PROVIDER')
            + (select count(*) from private.annunci_accessori_categorie_pubblicabili where approvata_da = '$U2')
            + (select count(*) from storage.objects where bucket_id = 'cantina-accessori-foto' and (name like '$U1/%' or name like '$U6/%'))
            + (select count(*) from public.audit_log where attore_id = '$U2')
            + (select count(*) from private.accessori_postvendita where seller_id in ('$U1', '$U6'))
            + (select count(*) from public.balance_movimenti where owner_id in ('$U1', '$U3', '$U4', '$U5', '$U6'))
            + (select count(*) from public.balance_accounts where owner_id in ('$U1', '$U3', '$U4', '$U5', '$U6'))
            + (select count(*) from private.partners where titolare_id = '$U6')
            + (select count(*) from private.partner_inviti where email like '%@$DOMINIO' or creato_da = '$U2')
            + (select count(*) from private.accessori_partner_movimenti where partner_id in (select id from private.partners where titolare_id = '$U6'))"
}

riporta() {
  local da1="null" da2="null" da3="null" da4="null"
  [ "$DA1_PRIMA" = "null" ] || da1="'$DA1_PRIMA'"
  [ "$DA2_PRIMA" = "null" ] || da2="'$DA2_PRIMA'"
  [ "$DA3_PRIMA" = "null" ] || da3="'$DA3_PRIMA'"
  [ "$DA4_PRIMA" = "null" ] || da4="'$DA4_PRIMA'"
  "${PSQL[@]}" >/dev/null <<SQL
begin;
set local session_replication_role = replica;
update private.cantina_accessori_impostazioni set funzione_attiva = '$FUNZ_PRIMA'::boolean, aggiornato_da = $da1;
update private.annunci_accessori_impostazioni
  set preparazione_attiva = '$PREP_PRIMA'::boolean, pubblicazione_attiva = '$PUBB_PRIMA'::boolean, aggiornato_da = $da2;
update private.accessori_logistica_impostazioni
  set logistica_attiva = '$LOGI_PRIMA'::boolean, versione = $LVERS_PRIMA, aggiornato_da = $da3;
update private.accessori_checkout_impostazioni
  set checkout_attivo = '$CHK_PRIMA'::boolean, versione = $CVERS_PRIMA, aggiornato_da = $da4;
update private.inventario_impostazioni set vendita_partner = '$VP_PRIMA'::boolean;
commit;
SQL
}

finale() {
  local status=$?
  riporta 2>/dev/null || status=1
  pulizia >/dev/null 2>&1 || status=1
  local r f p b l lv c cv vp
  vp="$(sql "select vendita_partner from private.inventario_impostazioni" 2>/dev/null || echo '?')"
  r="$(residui 2>/dev/null || echo '?')"
  f="$(sql "select funzione_attiva from private.cantina_accessori_impostazioni" 2>/dev/null || echo '?')"
  p="$(sql "select preparazione_attiva from private.annunci_accessori_impostazioni" 2>/dev/null || echo '?')"
  b="$(sql "select pubblicazione_attiva from private.annunci_accessori_impostazioni" 2>/dev/null || echo '?')"
  l="$(sql "select logistica_attiva from private.accessori_logistica_impostazioni" 2>/dev/null || echo '?')"
  lv="$(sql "select versione from private.accessori_logistica_impostazioni" 2>/dev/null || echo '?')"
  c="$(sql "select checkout_attivo from private.accessori_checkout_impostazioni" 2>/dev/null || echo '?')"
  cv="$(sql "select versione from private.accessori_checkout_impostazioni" 2>/dev/null || echo '?')"
  echo "12zs concorrenza: $passed/$total; residui: $r; interruttori ripristinati: $f/$p/$b/$l/$c (versioni $lv/$cv)"
  if [ "$r" != "0" ] || [ "$f" != "$FUNZ_PRIMA" ] || [ "$p" != "$PREP_PRIMA" ] || [ "$b" != "$PUBB_PRIMA" ] \
     || [ "$l" != "$LOGI_PRIMA" ] || [ "$lv" != "$LVERS_PRIMA" ] || [ "$c" != "$CHK_PRIMA" ] \
     || [ "$cv" != "$CVERS_PRIMA" ] || [ "$vp" != "$VP_PRIMA" ] || [ "$total" = "0" ] || [ "$passed" != "$total" ]; then
    status=1
  fi
  exit "$status"
}
trap finale EXIT

pulizia >/dev/null

# --- fixture ----------------------------------------------------------------
"${PSQL[@]}" <<SQL
begin;
set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('$U1', 'u1@$DOMINIO', now(), '{}'::jsonb), ('$U2', 'u2@$DOMINIO', now(), '{}'::jsonb),
  ('$U3', 'u3@$DOMINIO', now(), '{}'::jsonb), ('$U4', 'u4@$DOMINIO', now(), '{}'::jsonb),
  ('$U5', 'u5@$DOMINIO', now(), '{}'::jsonb), ('$U6', 'u6@$DOMINIO', now(), '{}'::jsonb);
insert into public.profiles (id, username, dob) values
  ('$U1', 'u1-conc12zs', date '1980-01-01'), ('$U2', 'u2-conc12zs', date '1980-01-01'),
  ('$U3', 'u3-conc12zs', date '1980-01-01'), ('$U4', 'u4-conc12zs', date '1980-01-01'),
  ('$U5', 'u5-conc12zs', date '1980-01-01'), ('$U6', 'u6-conc12zs', date '1980-01-01');
insert into public.user_roles (user_id, role) values
  ('$U1', 'user'), ('$U3', 'user'), ('$U4', 'user'), ('$U5', 'user'), ('$U6', 'user'),
  ('$U2', 'admin'), ('$U2', 'accessori_release');
commit;
SQL

# Servizio e tariffa di PROVA (provider fittizio, valori inventati, non tariffe).
"${PSQL[@]}" <<SQL
begin;
do \$f\$
declare
  v_t timestamptz := now() - interval '1 hour';
  v_srv uuid;
  v_rete uuid;
begin
  insert into private.logistics_service_definitions (
    provider_code, service_code, service_level, max_weight_g, max_length_mm, max_width_mm,
    max_height_mm, max_volume_cm3, eligible_packaging_formats, operational_eligibility, active,
    effective_from
  ) values ('$PROVIDER', 'standard', 'standard', 20000, 600, 400, 400, 90000, '{}', true, true, v_t)
  returning id into v_srv;
  insert into private.logistics_service_capabilities (service_definition_id, capability)
  values (v_srv, 'PUDO_TO_PUDO');
  insert into private.logistics_pudo_networks (provider_code, network_code, label, active, effective_from)
  values ('$PROVIDER', 'conc_qfa_rete', 'Rete di prova concorrenza B5A', true, v_t) returning id into v_rete;
  insert into private.logistics_service_pudo_networks (service_definition_id, network_id, endpoint_role)
  values (v_srv, v_rete, 'both');
  insert into private.accessori_logistica_tariffe (
    provider_code, service_code, capability, classe_codice, peso_max_g, lunghezza_max_mm,
    larghezza_max_mm, altezza_max_mm, fragile_ammesso, prezzo_cents, fonte, stato, effective_from)
  values ('$PROVIDER', 'standard', 'PUDO_TO_PUDO', 'm', 8000, 450, 300, 300, true, 790,
          'Prova concorrenza B5A (non una tariffa)', 'active', v_t);
end
\$f\$;
commit;
SQL

# Interruttori e approvazioni come farebbe la porta di rilascio.
"${PSQL[@]}" >/dev/null <<SQL
begin;
select set_config('vinae.accessori_rilascio', 'rilascio:$U2', true);
update private.cantina_accessori_impostazioni set funzione_attiva = true, aggiornato_da = '$U2';
update private.annunci_accessori_impostazioni
  set preparazione_attiva = true, pubblicazione_attiva = true, aggiornato_da = '$U2';
update private.accessori_logistica_impostazioni set logistica_attiva = true, aggiornato_da = '$U2';
update private.accessori_checkout_impostazioni set checkout_attivo = true, aggiornato_da = '$U2';
insert into private.annunci_accessori_categorie_pubblicabili (categoria_id, pubblicabile, approvata_da)
  select c.id, true, '$U2' from private.accessori_categorie c where c.slug = 'calici';
insert into private.annunci_accessori_categorie_pubblicabili (categoria_id, pubblicabile, approvata_da)
  select c.id, true, '$U2' from private.accessori_categorie c where c.slug = 'calici-da-rosso';
commit;
SQL

# Esegue SQL come un utente autenticato (PostgREST) in una transazione.
come() {
  local uid=$1 corpo=$2
  "${PSQL[@]}" <<SQL
begin;
select set_config('request.jwt.claims', json_build_object('sub', '$uid', 'role', 'authenticated')::text, true) \g /dev/null
select set_config('request.jwt.claim.sub', '$uid', true) \g /dev/null
set local role authenticated;
$corpo
commit;
SQL
}

CAT="$(sql "select id from private.accessori_categorie where slug = 'calici-da-rosso'")"
ID_FOTO=0

# Un annuncio pubblicato di U1: `pezzi` in Cantina e in annuncio, prezzo 1500.
# Stampa "annuncio cantina".
annuncio() {
  local pezzi=$1 item ann foto
  ID_FOTO=$((ID_FOTO + 1))
  item="$(sql "select gen_random_uuid()")"; ann="$(sql "select gen_random_uuid()")"
  foto="$U1/$item/12f70000-0000-4000-8000-0000000000$(printf '%02d' "$ID_FOTO").webp"
  come "$U1" "select public.cantina_accessori_salva('$item', jsonb_build_object(
    'categoria_id', '$CAT', 'nome', 'Calice conc 12zs', 'quantita', $pezzi, 'condizione', 'usato')) \g /dev/null" >/dev/null
  sql "insert into storage.objects (bucket_id, name) values ('cantina-accessori-foto', '$foto')" >/dev/null
  come "$U1" "select public.cantina_accessori_immagini_imposta('$item', array['$foto']) \g /dev/null" >/dev/null
  come "$U1" "select public.annunci_accessori_salva('$ann', jsonb_build_object(
    'cantina_id', '$item', 'quantita', $pezzi, 'prezzo_unitario_cents', 1500, 'conforme', true,
    'descrizione', 'Annuncio di prova per la concorrenza.', 'condizione', 'come_nuovo',
    'peso_g', 400, 'lunghezza_mm', 250, 'larghezza_mm', 100, 'altezza_mm', 100, 'fragile', false))
    \g /dev/null" >/dev/null
  come "$U1" "select public.annunci_accessori_pubblica('$ann') \g /dev/null" >/dev/null
  echo "$ann $item"
}

# Congela un preventivo (quantita `q`) per l'acquirente e stampa l'id.
congela() {
  local uid=$1 ann=$2 q=$3
  come "$uid" "select public.accessori_logistica_preventivo_congela('$ann', $q) ->> 'preventivoId';"
}

# Tiene la barriera chiusa per `secondi`, poi la rilascia.
barriera() {
  "${PSQL[@]}" <<SQL
begin;
select pg_advisory_xact_lock($BARRIERA) \g /dev/null
select pg_sleep($1) \g /dev/null
commit;
SQL
}

# Corpo in barriera: la sessione aspetta il rilascio, poi esegue il corpo.
in_barriera() {
  local uid=$1 corpo=$2
  "${PSQL[@]}" <<SQL
begin;
select pg_advisory_xact_lock_shared($BARRIERA) \g /dev/null
select set_config('request.jwt.claims', json_build_object('sub', '$uid', 'role', 'authenticated')::text, true) \g /dev/null
select set_config('request.jwt.claim.sub', '$uid', true) \g /dev/null
set local role authenticated;
$corpo
commit;
SQL
}

# Corpo privilegiato in barriera (il pagamento simulato e privato).
in_barriera_db() {
  local corpo=$1
  "${PSQL[@]}" <<SQL
begin;
select pg_advisory_xact_lock_shared($BARRIERA) \g /dev/null
$corpo
commit;
SQL
}

crea() { echo "select public.accessori_checkout_crea('$1', '$2') ->> 'id';"; }

q_n() { sql "$1"; }
inv() { sql "select (select quantita from private.cantina_accessori where id = '$2') || '/' || (select quantita from private.annunci_accessori where id = '$1') || '/' || private.accessori_disponibili('$1')"; }

# Lancia i job in background con la barriera chiusa, poi la rilascia.
#   avvia_barriera <secondi> -> sessione holder in background (pid in HOLDER)
HOLDER=""
avvia_barriera() { barriera "$1" >/dev/null 2>&1 & HOLDER=$!; sleep 0.8; }

out1="$(mktemp)"; out2="$(mktemp)"; out3="$(mktemp)"

# Il vincitore di una contesa e casuale: ogni prova parte senza prenotazioni aperte,
# cosi il tetto per acquirente non dipende dall'esito della prova precedente.
libera() {
  "${PSQL[@]}" >/dev/null <<SQL
begin;
alter table private.accessori_ordini disable trigger accessori_ordini_guard;
update private.accessori_ordini set stato = 'annullato', motivo_chiusura = 'acquirente'
 where stato = 'in_attesa_pagamento' and buyer_id in ('$U3', '$U4', '$U5');
alter table private.accessori_ordini enable trigger accessori_ordini_guard;
commit;
SQL
}

# --- helper dei pagamenti ----------------------------------------------------

# Prenota `q` pezzi per l'acquirente, apre e collega il pagamento (sessioni
# separate, senza concorrenza). Stampa "ordine sessione".
prepara() {
  local uid=$1 ann=$2 q=$3 chiave=$4 prev ord sess
  prev="$(congela "$uid" "$ann" "$q")"
  ord="$(come "$uid" "$(crea "$prev" "conc-12zs-k-$chiave")")"
  sess="pi_qfa_${chiave}"
  sql "select public.accessori_pagamento_apri('$ord', '$uid')" >/dev/null
  sql "select public.accessori_pagamento_collega('$ord', '$uid', 'stripe', '$sess')" >/dev/null
  echo "$ord $sess"
}

# Evento di incasso (come lo consegnerebbe il webhook firmato) per l'ordine.
incasso() {
  local evt=$1 ord=$2 sess=$3 tot
  tot="$(q_n "select totale_acquirente_cents from private.accessori_ordini where id = '$ord'")"
  echo "select public.accessori_pagamento_applica_evento('stripe', '$evt', 'settled'::public.payment_outcome,
    extract(epoch from now())::bigint, jsonb_build_object('session_id', '$sess', 'intent_id', '$sess',
    'provider_event_type', 'payment_intent.succeeded', 'amount_cents', $tot, 'currency', 'eur',
    'order_id', '$ord', 'dominio', 'accessori'))::text;"
}

stato_pag() { q_n "select stato from private.accessori_pagamenti where ordine_id = '$1'"; }


# --- helper QA-FINAL-A -------------------------------------------------------

# Evento del fornitore (come lo consegnerebbe il webhook firmato).
#   evento <id evento> <ordine> <sessione> <outcome> <tipo>
evento() {
  local tot
  tot="$(q_n "select totale_acquirente_cents from private.accessori_ordini where id = '$2'")"
  echo "select public.accessori_pagamento_applica_evento('stripe', '$1', '$4'::public.payment_outcome,
    extract(epoch from now())::bigint, jsonb_build_object('session_id', '$3', 'intent_id', '$3',
    'provider_event_type', '$5', 'amount_cents', $tot, 'currency', 'eur',
    'order_id', '$2', 'dominio', 'accessori'))::text;"
}
ev() { sql "$(evento "$@")"; }

# Invecchia la prenotazione (la scrittura diretta e vietata a tutti: guardia sospesa solo qui).
invecchia() {
  "${PSQL[@]}" >/dev/null <<SQL
begin;
alter table private.accessori_ordini disable trigger accessori_ordini_guard;
update private.accessori_ordini set creato_at = now() - interval '$2' - interval '15 minutes', scade_at = now() - interval '$2'
 where id = '$1';
alter table private.accessori_ordini enable trigger accessori_ordini_guard;
commit;
SQL
}

stato_ord() { q_n "select stato || '/' || coalesce(motivo_chiusura, '-') from private.accessori_ordini where id = '$1'"; }
stato_pag2() { q_n "select coalesce((select stato || '/' || coalesce(motivo, '-') || '/' || (provider_session_id is not null)::text from private.accessori_pagamenti where ordine_id = '$1'), 'nessuno')"; }
rc() { local r=0; "$@" >/dev/null 2>&1 || r=$?; echo "$r"; }
# Esito di una chiamata autenticata: testo dell'errore o dell'esito (mai fa fallire lo script).
prova() { come "$1" "$2" 2>&1 | head -c 400 || true; }

# Prenota `q` pezzi e apre il pagamento SENZA collegarlo (l'Edge Function non ha ancora risposto).
prepara_aperto() {
  local uid=$1 ann=$2 q=$3 chiave=$4 prev ord
  prev="$(congela "$uid" "$ann" "$q")"
  ord="$(come "$uid" "$(crea "$prev" "conc-12zs-k-$chiave")")"
  sql "select public.accessori_pagamento_apri('$ord', '$uid')" >/dev/null
  echo "$ord"
}
collega() { sql "select public.accessori_pagamento_collega('$1', '$2', 'stripe', '$3')" >/dev/null; }

# ---------------------------------------------------------------------------
# 1. Apertura del pagamento contro annullamento (3 giri): un intento non si aggancia mai a un ordine annullato.
ok1=0
for giro in 1 2 3; do
  libera
  read -r A1 C1 <<<"$(annuncio 4)"
  P1="$(congela "$U3" "$A1" 2)"
  O1="$(come "$U3" "$(crea "$P1" "conc-12zs-k-a$giro")")"
  avvia_barriera 2
  in_barriera_db "select public.accessori_pagamento_apri('$O1', '$U3') ->> 'order_id';" >"$out1" 2>&1 & pa=$!
  in_barriera "$U3" "select public.accessori_ordine_annulla('$O1') ->> 'stato';" >"$out2" 2>&1 & pb=$!
  ra=0; rb=0; wait "$pa" || ra=$?; wait "$pb" || rb=$?; wait "$HOLDER" || true
  rcol="$(rc collega "$O1" "$U3" "pi_qfa_a$giro")"
  st="$(stato_ord "$O1")"; pg="$(stato_pag2 "$O1")"; invg="$(inv "$A1" "$C1")"
  if [ "$rb" = "0" ] && [ "$st" = "annullato/acquirente" ] && [ "$rcol" != "0" ] && [ "$invg" = "4/4/4" ] \
     && { [ "$pg" = "nessuno" ] || [ "$pg" = "expired/ordine_annullato/false" ]; }; then
    ok1=$((ok1 + 1))
  else echo "giro $giro: ra=$ra rb=$rb collega=$rcol stato=$st pag=$pg inv=$invg" >&2; fi
done
if [ "$ok1" = "3" ]; then
  esito "1 apertura contro annullamento (3 giri): ordine annullato, pagamento assente o expired non collegato, collega rifiutato, quantita 4/4/4" ok
else esito "1 apertura contro annullamento" "giri coerenti: $ok1/3"; fi

# ---------------------------------------------------------------------------
# 2. Pagamento COLLEGATO e aperto: annullo diretto rifiutato; l'esito `failed` libera.
libera
read -r A2 C2 <<<"$(annuncio 4)"
read -r O2 S2 <<<"$(prepara "$U3" "$A2" 2 "b1")"
r_an="$(prova "$U3" "select public.accessori_ordine_annulla('$O2');")"
st_dopo="$(stato_ord "$O2")"; inv_dopo="$(inv "$A2" "$C2")"
f1="$(ev conc-evs-2f "$O2" "$S2" failed payment_intent.payment_failed)"
st_f="$(stato_ord "$O2")"; pg_f="$(stato_pag2 "$O2")"; inv_f="$(inv "$A2" "$C2")"
an2="$(prova "$U3" "select public.accessori_ordine_annulla('$O2') ->> 'stato';" | tail -n 1)"
f2="$(ev conc-evs-2f "$O2" "$S2" failed payment_intent.payment_failed)"
if echo "$r_an" | grep -q "Il pagamento e in corso" && [ "$st_dopo" = "in_attesa_pagamento/-" ] && [ "$inv_dopo" = "4/4/2" ] \
   && [ "$f1" = "processed" ] && [ "$st_f" = "annullato/pagamento_fallito" ] && [ "$pg_f" = "failed/-/true" ] && [ "$inv_f" = "4/4/4" ] \
   && [ "$an2" = "annullato" ] && [ "$f2" = "duplicate" ]; then
  esito "2 pagamento collegato aperto: annullo rifiutato (pagamento_in_corso), ordine e pezzi invariati; failed libera 4/4/4; annullo poi idempotente; replay failed = duplicate" ok
else esito "2 pagamento collegato" "r_an=$(echo "$r_an" | head -c 120) st=$st_dopo inv=$inv_dopo f1=$f1 st_f=$st_f pg_f=$pg_f inv_f=$inv_f an2=$an2 f2=$f2"; fi

# ---------------------------------------------------------------------------
# 3. Pagamento in elaborazione (processing): annullo rifiutato, poi incasso: una sola sottrazione.
libera
read -r A3 C3 <<<"$(annuncio 4)"
read -r O3 S3 <<<"$(prepara "$U3" "$A3" 2 "b2")"
ev conc-evs-3a "$O3" "$S3" authorized payment_intent.processing >/dev/null
r_pr="$(prova "$U3" "select public.accessori_ordine_annulla('$O3');")"
st_pr="$(stato_ord "$O3")"; pg_pr="$(stato_pag2 "$O3")"
s3="$(ev conc-evs-3b "$O3" "$S3" settled payment_intent.succeeded)"
s3b="$(ev conc-evs-3b "$O3" "$S3" settled payment_intent.succeeded)"
r_po="$(prova "$U3" "select public.accessori_ordine_annulla('$O3');")"
if echo "$r_pr" | grep -q "Il pagamento e in corso" && [ "$st_pr" = "in_attesa_pagamento/-" ] && [ "$pg_pr" = "processing/-/true" ] \
   && [ "$s3" = "processed" ] && [ "$s3b" = "duplicate" ] && [ "$(stato_ord "$O3")" = "pagato/-" ] && [ "$(inv "$A3" "$C3")" = "2/2/2" ] \
   && echo "$r_po" | grep -q "Un ordine pagato non si annulla"; then
  esito "3 processing: annullo rifiutato; incasso applicato una volta (2/2/2), replay duplicate; dopo il pagamento l'annullo e rifiutato (ordine_pagato)" ok
else esito "3 processing" "pr=$(echo "$r_pr" | head -c 100) st=$st_pr pg=$pg_pr s3=$s3 s3b=$s3b ord=$(stato_ord "$O3") inv=$(inv "$A3" "$C3")"; fi

# ---------------------------------------------------------------------------
# 4. Incasso contro annullamento con pagamento COLLEGATO (3 giri): sempre pagato, annullo rifiutato.
ok4=0
for giro in 1 2 3; do
  libera
  read -r A4 C4 <<<"$(annuncio 4)"
  read -r O4 S4 <<<"$(prepara "$U3" "$A4" 2 "c$giro")"
  avvia_barriera 2
  in_barriera_db "$(evento "conc-evs-4-$giro" "$O4" "$S4" settled payment_intent.succeeded)" >"$out1" 2>&1 & pa=$!
  in_barriera "$U3" "select public.accessori_ordine_annulla('$O4') ->> 'stato';" >"$out2" 2>&1 & pb=$!
  ra=0; rb=0; wait "$pa" || ra=$?; wait "$pb" || rb=$?; wait "$HOLDER" || true
  if [ "$(stato_ord "$O4")" = "pagato/-" ] && [ "$(stato_pag2 "$O4" | cut -d/ -f1)" = "paid" ] && [ "$ra" = "0" ] && [ "$rb" != "0" ] \
     && grep -qE "Il pagamento e in corso|Un ordine pagato non si annulla" "$out2"      && [ "$(inv "$A4" "$C4")" = "2/2/2" ]; then ok4=$((ok4 + 1))
  else echo "giro $giro: ord=$(stato_ord "$O4") pag=$(stato_pag2 "$O4") ra=$ra rb=$rb inv=$(inv "$A4" "$C4")" >&2; fi
done
if [ "$ok4" = "3" ]; then
  esito "4 incasso contro annullamento con pagamento collegato (3 giri): sempre pagato+paid, annullo rifiutato, una sottrazione (2/2/2), nessun refund_due" ok
else esito "4 incasso contro annullamento" "giri coerenti: $ok4/3"; fi

# ---------------------------------------------------------------------------
# 5. Due annulli paralleli (pagamento aperto non collegato): idempotenti, un solo esito, pezzi liberi una volta.
libera
read -r A5 C5 <<<"$(annuncio 4)"
O5="$(prepara_aperto "$U3" "$A5" 2 "d1")"
avvia_barriera 2
in_barriera "$U3" "select public.accessori_ordine_annulla('$O5') ->> 'stato';" >"$out1" 2>&1 & pa=$!
in_barriera "$U3" "select public.accessori_ordine_annulla('$O5') ->> 'stato';" >"$out2" 2>&1 & pb=$!
ra=0; rb=0; wait "$pa" || ra=$?; wait "$pb" || rb=$?; wait "$HOLDER" || true
if [ "$ra" = "0" ] && [ "$rb" = "0" ] && [ "$(cat "$out1")" = "annullato" ] && [ "$(cat "$out2")" = "annullato" ] \
   && [ "$(stato_ord "$O5")" = "annullato/acquirente" ] && [ "$(stato_pag2 "$O5")" = "expired/ordine_annullato/false" ] \
   && [ "$(inv "$A5" "$C5")" = "4/4/4" ]; then
  esito "5 due annulli paralleli: entrambi annullato, un solo esito, pagamento expired non collegato, 4/4/4" ok
else esito "5 due annulli" "ra=$ra rb=$rb $(head -c 100 "$out1") $(head -c 100 "$out2") ord=$(stato_ord "$O5") pag=$(stato_pag2 "$O5") inv=$(inv "$A5" "$C5")"; fi

# ---------------------------------------------------------------------------
# 6. Prenotazione scaduta con intento collegato: annullo ammesso (scaduto); incasso tardivo -> refund_due una volta.
libera
read -r A6 C6 <<<"$(annuncio 4)"
read -r O6 S6 <<<"$(prepara "$U3" "$A6" 2 "e1")"
invecchia "$O6" "10 minutes"
an6="$(prova "$U3" "select public.accessori_ordine_annulla('$O6') ->> 'stato';" | tail -n 1)"
inv6a="$(inv "$A6" "$C6")"
bal0="$(q_n "select count(*) from public.balance_movimenti")"
l1="$(ev conc-evs-6a "$O6" "$S6" settled payment_intent.succeeded)"
l2="$(ev conc-evs-6a "$O6" "$S6" settled payment_intent.succeeded)"
l3="$(ev conc-evs-6b "$O6" "$S6" settled payment_intent.succeeded)"
rimb="$(q_n "select count(*) from private.accessori_rimborsi r join private.accessori_pagamenti p on p.id = r.pagamento_id where p.ordine_id = '$O6'")"
if [ "$an6" = "scaduto" ] && [ "$inv6a" = "4/4/4" ] && [ "$l1" = "late_paid_requires_refund" ] && [ "$l2" = "duplicate" ] && [ "$l3" = "processed" ] \
   && [ "$(stato_pag2 "$O6" | cut -d/ -f1)" = "refund_due" ] && [ "$(stato_ord "$O6")" = "scaduto/scadenza" ] \
   && [ "$(inv "$A6" "$C6")" = "4/4/4" ] && [ "$rimb" -le 1 ] \
   && [ "$(q_n "select count(*) from public.balance_movimenti")" = "$bal0" ]; then
  esito "6 scaduta+collegato: annullo -> scaduto; incasso tardivo -> refund_due una volta, replay duplicate, nessun doppio rimborso ($rimb <= 1), quantita 4/4/4, nessun accredito al venditore" ok
else esito "6 scaduta e tardivo" "an=$an6 inv=$inv6a l1=$l1 l2=$l2 l3=$l3 pag=$(stato_pag2 "$O6") ord=$(stato_ord "$O6") rimb=$rimb"; fi

# ---------------------------------------------------------------------------
# 7. Processing oltre la scadenza: rifiutato entro l'ora, ammesso dopo l'ora; poi incasso -> refund_due.
libera
read -r A7 C7 <<<"$(annuncio 4)"
read -r O7 S7 <<<"$(prepara "$U3" "$A7" 2 "f1")"
ev conc-evs-7a "$O7" "$S7" authorized payment_intent.processing >/dev/null
invecchia "$O7" "10 minutes"
r7a="$(prova "$U3" "select public.accessori_ordine_annulla('$O7');")"
st7a="$(stato_ord "$O7")"
invecchia "$O7" "2 hours"
an7="$(prova "$U3" "select public.accessori_ordine_annulla('$O7') ->> 'stato';" | tail -n 1)"
l7="$(ev conc-evs-7b "$O7" "$S7" settled payment_intent.succeeded)"
if echo "$r7a" | grep -q "Il pagamento e in corso" && [ "$st7a" = "in_attesa_pagamento/-" ] && [ "$an7" = "scaduto" ] \
   && [ "$l7" = "late_paid_requires_refund" ] && [ "$(stato_pag2 "$O7" | cut -d/ -f1)" = "refund_due" ] && [ "$(inv "$A7" "$C7")" = "4/4/4" ]; then
  esito "7 processing oltre scadenza: annullo rifiutato entro l'ora, ammesso oltre; incasso successivo -> refund_due, 4/4/4 (nessun blocco permanente)" ok
else esito "7 processing scaduto" "r7a=$(echo "$r7a" | head -c 80) st=$st7a an=$an7 l7=$l7 pag=$(stato_pag2 "$O7") inv=$(inv "$A7" "$C7")"; fi

# ---------------------------------------------------------------------------
# 8. Evento `expired` del fornitore libera l'ordine; l'annullo successivo e idempotente.
libera
read -r A8 C8 <<<"$(annuncio 4)"
read -r O8 S8 <<<"$(prepara "$U3" "$A8" 2 "g1")"
x8="$(ev conc-evs-8a "$O8" "$S8" expired payment_intent.canceled)"
an8="$(prova "$U3" "select public.accessori_ordine_annulla('$O8') ->> 'stato';" | tail -n 1)"
if [ "$x8" = "processed" ] && [ "$(stato_ord "$O8")" = "scaduto/scadenza" ] && [ "$(stato_pag2 "$O8" | cut -d/ -f1)" = "expired" ] \
   && [ "$an8" = "scaduto" ] && [ "$(inv "$A8" "$C8")" = "4/4/4" ]; then
  esito "8 evento expired: ordine scaduto, pezzi liberi 4/4/4, annullo idempotente" ok
else esito "8 evento expired" "x8=$x8 ord=$(stato_ord "$O8") pag=$(stato_pag2 "$O8") an=$an8"; fi

# ---------------------------------------------------------------------------
# PARTNER - ultima unita commerciale, due acquirenti, sessioni reali.
sql "update private.inventario_impostazioni set vendita_partner = true" >/dev/null
cfg() {
  echo "$(sql "select string_agg(classe_venditore::text || ':' || margine_obiettivo_bps, ',' order by classe_venditore::text) from public.marketplace_config where valida_fino is null")|$(sql "select string_agg(dominio || ':' || classe_venditore::text || ':' || margine_obiettivo_bps, ',' order by dominio, classe_venditore::text) from private.marketplace_margini_dominio where valida_fino is null")"
}
vino() { sql "select (select count(*) from public.orders) || '/' || (select count(*) from public.payments) || '/' || (select count(*) from public.listings)"; }
BASE_ORD="$(vino)"
CFG_PRIMA="$(cfg)"

"${PSQL[@]}" >/dev/null <<SQL
begin;
create function pg_temp.ch(p_sql text, p_uid uuid) returns jsonb language plpgsql as \$f\$
declare r jsonb;
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  execute p_sql into r;
  execute 'reset role';
  return r;
end \$f\$;
do \$f\$
declare
  v_t jsonb; v_id uuid; v_piva text;
begin
  select '1270000009' || d::text into v_piva from generate_series(0, 9) d
   where private.partita_iva_valida('1270000009' || d::text) limit 1;
  v_t := pg_temp.ch('select public.partner_admin_invito_crea(''u6@$DOMINIO'')', '$U2');
  v_t := pg_temp.ch(format('select to_jsonb(public.partner_invito_accetta(%L))', v_t ->> 'token'), '$U6');
  v_id := (v_t #>> '{}')::uuid;
  perform pg_temp.ch(format('select public.partner_dati_aggiorna(''Ragione conc Srl'', ''Enoteca conc'', %L, %L, ''enoteca'', ''Via Prova 1'', ''12051'', ''Alba'', ''CN'')', v_piva, 'commerciale.conc@$DOMINIO'), '$U6');
  perform pg_temp.ch('select to_jsonb(public.partner_invia_verifica())', '$U6');
  perform pg_temp.ch(format('select to_jsonb(public.partner_admin_decidi(%L, ''approva''))', v_id), '$U2');
  if (select stato::text from private.partners where id = v_id) <> 'attivo' then
    raise exception 'fixture 12zs: Partner non attivo';
  end if;
end \$f\$;
commit;
SQL
PID="$(sql "select id from private.partners where titolare_id = '$U6'")"

# Scorta commerciale del Partner + annuncio pubblicato. Stampa "annuncio scorta".
annuncio_partner() {
  local pezzi=$1 item ann foto
  ID_FOTO=$((ID_FOTO + 1))
  item="$(sql "select gen_random_uuid()")"; ann="$(sql "select gen_random_uuid()")"
  foto="$U6/$item/12f70000-0000-4000-8000-0000000000$(printf '%02d' "$ID_FOTO").webp"
  come "$U6" "select public.accessori_partner_scorta_salva('$item', jsonb_build_object(
    'categoria_id', '$CAT', 'nome', 'Calice Partner conc 12zs', 'quantita', $pezzi, 'condizione', 'usato')) \g /dev/null" >/dev/null
  sql "insert into storage.objects (bucket_id, name) values ('cantina-accessori-foto', '$foto')" >/dev/null
  come "$U6" "select public.cantina_accessori_immagini_imposta('$item', array['$foto']) \g /dev/null" >/dev/null
  come "$U6" "select public.annunci_accessori_salva('$ann', jsonb_build_object(
    'cantina_id', '$item', 'quantita', $pezzi, 'prezzo_unitario_cents', 2000, 'conforme', true,
    'descrizione', 'Annuncio Partner di prova per la concorrenza.', 'condizione', 'nuovo',
    'peso_g', 400, 'lunghezza_mm', 250, 'larghezza_mm', 100, 'altezza_mm', 100, 'fragile', false))
    \g /dev/null" >/dev/null
  come "$U6" "select public.annunci_accessori_pubblica('$ann') \g /dev/null" >/dev/null
  echo "$ann $item"
}

# ---------------------------------------------------------------------------
# 9. ULTIMA UNITA: due acquirenti prenotano insieme; vince uno solo.
libera
read -r AP CP <<<"$(annuncio_partner 1)"
PV3="$(congela "$U3" "$AP" 1)"; PV4="$(congela "$U4" "$AP" 1)"
avvia_barriera 2
in_barriera "$U3" "$(crea "$PV3" "conc-12zs-k-p3")" >"$out1" 2>&1 & pa=$!
in_barriera "$U4" "$(crea "$PV4" "conc-12zs-k-p4")" >"$out2" 2>&1 & pb=$!
ra=0; rb=0; wait "$pa" || ra=$?; wait "$pb" || rb=$?; wait "$HOLDER" || true
nord="$(q_n "select count(*) from private.accessori_ordini where annuncio_id = '$AP' and stato = 'in_attesa_pagamento'")"
if [ "$ra" = "0" ]; then VINC="$U3"; PVV="$PV3"; KV="p3"; ORDP="$(cat "$out1")"; PERD="$U4"; PVP="$PV4"; KP="p4"
else VINC="$U4"; PVV="$PV4"; KV="p4"; ORDP="$(cat "$out2")"; PERD="$U3"; PVP="$PV3"; KP="p3"; fi
retry="$(prova "$VINC" "$(crea "$PVV" "conc-12zs-k-$KV")" | tail -n 1)"
perso_txt="$(prova "$PERD" "$(crea "$PVP" "conc-12zs-k-$KP")")"
perso=1; echo "$perso_txt" | grep -q "quantita_non_disponibile" || perso=0
if [ $(( (ra == 0) + (rb == 0) )) -eq 1 ] && [ "$nord" = "1" ] && [ "$retry" = "$ORDP" ] && [ "$perso" = "1" ] \
   && [ "$(q_n "select count(*) from private.accessori_ordini where annuncio_id = '$AP'")" = "1" ] \
   && [ "$(inv "$AP" "$CP")" = "1/1/0" ] \
   && [ "$(q_n "select venditore_classe::text || ':' || margine_obiettivo_bps from private.accessori_ordini where id = '$ORDP'")" = "partner:1500" ]; then
  esito "9 ultima unita Partner: una sola prenotazione valida, retry idempotente (stesso ordine), il perdente resta rifiutato, 1/1/0, partner:1500 bps" ok
else esito "9 ultima unita Partner" "ra=$ra rb=$rb nord=$nord retry=$retry ord=$ORDP perso=$perso inv=$(inv "$AP" "$CP") $(head -c 120 "$out1") $(head -c 120 "$out2")"; fi

# ---------------------------------------------------------------------------
# 10. Il vincitore paga: vendita applicata una volta; quantita mai negativa; storico = giacenza.
sql "select public.accessori_pagamento_apri('$ORDP', '$VINC')" >/dev/null
collega "$ORDP" "$VINC" "pi_qfa_p1"
s10="$(ev conc-evs-10a "$ORDP" "pi_qfa_p1" settled payment_intent.succeeded)"
s10b="$(ev conc-evs-10a "$ORDP" "pi_qfa_p1" settled payment_intent.succeeded)"
if [ "$s10" = "processed" ] && [ "$s10b" = "duplicate" ] && [ "$(stato_ord "$ORDP")" = "pagato/-" ] \
   && [ "$(q_n "select quantita from private.cantina_accessori where id = '$CP'")" = "0" ] \
   && [ "$(q_n "select coalesce(sum(delta), 0) from private.accessori_partner_movimenti where cantina_accessorio_id = '$CP'")" = "0" ] \
   && [ "$(q_n "select count(*) from private.accessori_partner_movimenti where cantina_accessorio_id = '$CP' and quantita_dopo < 0")" = "0" ] \
   && [ "$(q_n "select count(*) from private.accessori_partner_movimenti where cantina_accessorio_id = '$CP' and causale = 'carico'")" = "1" ] \
   && [ "$(q_n "select count(*) from private.accessori_postvendita where ordine_id = '$ORDP'")" = "1" ]; then
  esito "10 incasso del vincitore: pagato, giacenza 0 = somma dei movimenti (carico 1, vendita -1), nessuna quantita negativa, replay duplicate, post-vendita aperto una volta" ok
else esito "10 vincitore paga" "s10=$s10 s10b=$s10b ord=$(stato_ord "$ORDP") qta=$(q_n "select quantita from private.cantina_accessori where id = '$CP'") mov=$(q_n "select string_agg(causale || ':' || delta, ',' order by created_at) from private.accessori_partner_movimenti where cantina_accessorio_id = '$CP'")"; fi

# ---------------------------------------------------------------------------
# 11. Sospensione e revoca durante la vendita.
libera
read -r AS CS <<<"$(annuncio_partner 3)"
PS5="$(congela "$U5" "$AS" 1)"; PS4="$(congela "$U4" "$AS" 1)"; PS3="$(congela "$U3" "$AS" 1)"
OSEQ="$(come "$U3" "$(crea "$PS3" "conc-12zs-k-s3")")"
avvia_barriera 2
in_barriera "$U5" "$(crea "$PS5" "conc-12zs-k-s5")" >"$out1" 2>&1 & pa=$!
in_barriera "$U2" "select to_jsonb(public.partner_admin_decidi('$PID', 'sospendi', 'motivo di prova 12zs'));" >"$out2" 2>&1 & pb=$!
ra=0; rb=0; wait "$pa" || ra=$?; wait "$pb" || rb=$?; wait "$HOLDER" || true
stp="$(q_n "select stato from private.partners where id = '$PID'")"
t_sosp="$(prova "$U4" "$(crea "$PS4" "conc-12zs-k-s4")")"; dopo_sosp=0; echo "$t_sosp" | grep -qE "venditore_non_ammesso|annuncio_non_disponibile" && dopo_sosp=1
come "$U2" "select to_jsonb(public.partner_admin_decidi('$PID', 'revoca', 'motivo di prova 12zs'));" >/dev/null 2>&1 || true
stp2="$(q_n "select stato from private.partners where id = '$PID'")"
t_rev="$(prova "$U4" "$(crea "$PS4" "conc-12zs-k-s4b")")"; dopo_rev=0; echo "$t_rev" | grep -qE "venditore_non_ammesso|annuncio_non_disponibile" && dopo_rev=1
n11="$(q_n "select count(*) from private.accessori_ordini where annuncio_id = '$AS'")"
OS="$(q_n "select id from private.accessori_ordini where annuncio_id = '$AS' and id <> '$OSEQ' limit 1")"
esito11="ok"
sql "select public.accessori_pagamento_apri('$OSEQ', '$U3')" >/dev/null
collega "$OSEQ" "$U3" "pi_qfa_s0"
e11s="$(ev conc-evs-11s "$OSEQ" "pi_qfa_s0" settled payment_intent.succeeded)"
if [ "$e11s" != "processed" ] || [ "$(stato_ord "$OSEQ")" != "pagato/-" ]; then esito11="ordine prenotato prima della sospensione non incassato ($e11s $(stato_ord "$OSEQ"))"; fi
if [ -n "$OS" ]; then
  # Ordine prenotato prima della sospensione: il pagamento non resta congelato.
  sql "select public.accessori_pagamento_apri('$OS', '$U5')" >/dev/null
  collega "$OS" "$U5" "pi_qfa_s1"
  e11="$(ev conc-evs-11a "$OS" "pi_qfa_s1" settled payment_intent.succeeded)"
  if [ "$e11" != "processed" ] || [ "$(stato_ord "$OS")" != "pagato/-" ]; then
    esito11="incasso dell'ordine gia prenotato non applicato ($e11 $(stato_ord "$OS"))"
  fi
fi
if [ "$rb" = "0" ] && [ "$stp" = "sospeso" ] && [ "$stp2" = "revocato" ] && [ "$dopo_sosp" = "1" ] && [ "$dopo_rev" = "1" ] \
   && [ "$n11" -le 2 ] && [ "$esito11" = "ok" ] \
   && [ "$(q_n "select count(*) from private.cantina_accessori where id = '$CS' and quantita < 0")" = "0" ]; then
  esito "11 sospensione contro prenotazione e poi revoca: nessuna nuova prenotazione dopo sospensione/revoca ($n11 ordine/i), l'ordine gia prenotato si incassa (pagato), giacenza non negativa" ok
else esito "11 sospensione/revoca" "ra=$ra rb=$rb stp=$stp stp2=$stp2 dopo_sosp=$dopo_sosp dopo_rev=$dopo_rev n=$n11 esito=$esito11 sosp=[$(echo "$t_sosp" | tr '
' ' ' | head -c 220)]"; fi

# ---------------------------------------------------------------------------
# 12. Aliquote e vino invariati; invarianti finali.
CFG_DOPO="$(cfg)"
if [ "$CFG_PRIMA" = "$CFG_DOPO" ] && [ "$BASE_ORD" = "$(vino)" ] \
   && [ "$(q_n "select margine_obiettivo_bps from private.marketplace_margini_dominio where valida_fino is null and dominio = 'accessori_enologici' and classe_venditore = 'privato'")" = "1000" ] \
   && [ "$(q_n "select margine_obiettivo_bps from private.marketplace_margini_dominio where valida_fino is null and dominio = 'accessori_enologici' and classe_venditore = 'partner'")" = "1500" ] \
   && [ "$(q_n "select count(*) from private.cantina_accessori where owner_id in ('$U1', '$U6') and quantita < 0")" = "0" ] \
   && [ "$(q_n "select count(*) from (select 1 from private.accessori_pagamenti where buyer_id in ('$U3', '$U4', '$U5') group by ordine_id having count(*) > 1) x")" = "0" ] \
   && [ "$(q_n "select count(*) from private.accessori_pagamenti p join private.accessori_ordini o on o.id = p.ordine_id where o.seller_id in ('$U1', '$U6') and p.stato = 'paid' and o.stato <> 'pagato'")" = "0" ] \
   && [ "$(q_n "select count(*) from private.accessori_ordini o where o.seller_id in ('$U1', '$U6') and o.pagamento_modo = 'provider' and not exists (select 1 from private.accessori_pagamenti p where p.ordine_id = o.id and p.stato = 'paid')")" = "0" ] \
   && [ "$(q_n "select count(*) from (select 1 from private.accessori_rimborsi r join private.accessori_pagamenti p on p.id = r.pagamento_id where p.buyer_id in ('$U3', '$U4', '$U5') group by r.pagamento_id having count(*) > 1) x")" = "0" ]; then
  esito "12 aliquote invariate (vino 800/1500, accessori 1000/1500), vino non toccato, nessuna quantita negativa, un pagamento per ordine, pagato <-> paid, nessun doppio rimborso" ok
else esito "12 invarianti" "cfg=$CFG_PRIMA vs $CFG_DOPO base=$BASE_ORD vs $(vino)"; fi
