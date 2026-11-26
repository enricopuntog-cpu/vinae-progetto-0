#!/usr/bin/env bash
# Prova di RIPRISTINO dello schema `catalog` popolato (audit WI-008, F-08), sullo stack Supabase effimero lasciato da
# concorrenza.sh. Domanda precisa: dopo un popolamento, un dump dei soli dati fatto con lo STESSO strumento del backup
# offsite si ricarica sopra le migration del commit, nonostante guardie di inserimento, vincoli circolari, regola
# approvata immutabile e righe già seminate dalle migration? E la promozione riprende (sequenze comprese)?
# NON prova il backup B2 reale (cifrato, chiave offline), Auth, Storage né un progetto gestito.
set -euo pipefail

cd "$(dirname "$0")/../../../.."
: "${E2E_DB_URL:?serve E2E_DB_URL}"
case "$E2E_DB_URL" in
  *@127.0.0.1:* | *@localhost:* | *"@[::1]:"*) ;;
  *) echo "Rifiuto: la prova accetta solo un database locale/effimero." >&2; exit 2 ;;
esac

LAVORO="$(mktemp -d)"
trap 'rm -rf "$LAVORO"' EXIT
q() { psql "$E2E_DB_URL" -X -q -A -t -v ON_ERROR_STOP=1 "$@"; }
sql() { q -c "$1"; }
fallisci() { echo "::error title=Ripristino catalogo::$1" >&2; exit 1; }
atteso() { [ "$2" = "$3" ] || fallisci "$1: ottenuto «$2», atteso «$3»"; echo "  ok  $1"; }

# Una riga per tabella: nome, righe, impronta del contenuto indipendente dall'ordine fisico.
fotografia() {
  local t
  for t in $(sql "select tablename from pg_tables where schemaname = 'catalog' order by 1"); do
    printf '%s %s\n' "$t" "$(sql "select count(*) || ' ' || coalesce(md5(string_agg(h, '' order by h)), '-') from (select md5(to_jsonb(x)::text) as h from catalog.\"$t\" x) s")"
  done
}
stato_regola() { sql "select status || ' ' || coalesce(approved_fingerprint, '-') || ' ' || coalesce(approved_view_digest, '-') from catalog.promotion_rules where version = 'lwin-conservative-v1'"; }

echo "== 1. Fotografia del catalogo popolato"
VINI="$(sql 'select count(*) from catalog.wines')"
[ "$VINI" -gt 0 ] || fallisci "il catalogo è vuoto: eseguire prima concorrenza.sh sullo stesso stack"
fotografia > "$LAVORO/prima.txt"
REGOLA_PRIMA="$(stato_regola)"
IMPRONTA_PRIMA="$(sql "select catalog.promotion_logic_fingerprint('lwin-conservative-v1')")"
echo "  vini promossi: $VINI; tabelle: $(wc -l < "$LAVORO/prima.txt")"

echo "== 2. Dump dei dati dello schema catalog (stesso comando del backup offsite)"
supabase db dump --db-url "$E2E_DB_URL" --data-only --use-copy --schema catalog -f "$LAVORO/catalog.sql" > /dev/null 2>&1 \
  || fallisci "dump non riuscito"
grep -q 'COPY "catalog"."wines"' "$LAVORO/catalog.sql" || fallisci "il dump non contiene catalog.wines"
atteso "il dump disattiva i trigger solo per la sessione di ripristino" \
  "$(grep -c "session_replication_role = replica" "$LAVORO/catalog.sql" | sed 's/^[1-9].*/si/')" si

echo "== 3. Ambiente nuovo dalle sole migration del commit"
supabase db reset --local > "$LAVORO/reset.log" 2>&1 || { tail -n 20 "$LAVORO/reset.log"; fallisci "reset non riuscito"; }
atteso "ambiente nuovo: nessun vino" "$(sql 'select count(*) from catalog.wines')" 0
atteso "ambiente nuovo: regola in bozza" "$(sql "select status from catalog.promotion_rules where version = 'lwin-conservative-v1'")" draft

echo "== 4. Ripristino in UNA transazione"
TABELLE="$(grep -oE '^COPY "catalog"\."[a-z_0-9]+"' "$LAVORO/catalog.sql" | sed -E 's/^COPY //' | sort -u | paste -sd, -)"
[ -n "$TABELLE" ] || fallisci "nessuna tabella nel dump"
{
  echo "set session_replication_role = replica;"
  # Le migration seminano fonte, regola in bozza e interruttori: vanno sostituite dai dati del backup, non sommate.
  echo "truncate $TABELLE cascade;"
  cat "$LAVORO/catalog.sql"
} > "$LAVORO/ripristino.sql"
q --single-transaction -f "$LAVORO/ripristino.sql" > "$LAVORO/ripristino.log" 2>&1 \
  || { grep -m 5 -i error "$LAVORO/ripristino.log"; fallisci "il ripristino dei dati non riesce"; }

echo "== 5. Confronto"
fotografia > "$LAVORO/dopo.txt"
diff "$LAVORO/prima.txt" "$LAVORO/dopo.txt" > "$LAVORO/diff.txt" || { cat "$LAVORO/diff.txt"; fallisci "il contenuto ripristinato differisce"; }
echo "  ok  tutte le tabelle di catalog hanno stesse righe e stesso contenuto"
atteso "regola approvata e impronte registrate conservate" "$(stato_regola)" "$REGOLA_PRIMA"
atteso "impronta della logica uguale sull'ambiente nuovo" "$(sql "select catalog.promotion_logic_fingerprint('lwin-conservative-v1')")" "$IMPRONTA_PRIMA"
atteso "interruttori dopo il ripristino" "$(sql "select (select enabled from catalog.promotion_settings)::text || ' ' || (select enabled from catalog.public_projection_settings)::text")" "false false"
atteso "violazioni di superficie" "$(sql 'select count(*) from catalog.surface_audit() where not ok')" 0

echo "== 6. La promozione riprende dopo il ripristino (sequenze e guardie di nuovo attive)"
RUN="$(sql "select cv.complete_run_id from catalog.complete_versions cv join catalog.sources s on s.id = cv.source_id where s.code = 'LIVEX-LWIN7'")"
sed -e "s|{{FINESTRA}}|ripristino|g" -e "s|{{NUMERO}}|1|g" -e "s|{{LIMITE}}|100|g" -e "s|{{MAX_BATCH_AUTORIZZATO}}|1000|g" \
  -e "s|{{CANDIDATI_ATTESI}}|159614|g" -e "s|{{RUN_COMPLETO}}|$RUN|g" -e "s|{{TETTO_DB_BYTE}}|100000000000|g" -e "s|{{TIMEOUT}}|900s|g" \
  tools/wine-catalog/promozione/03_lotto.sql > "$LAVORO/lotto.sql"
ESITO="$(q -f "$LAVORO/lotto.sql" | grep '^{' | tail -n 1 | jq -r .esito)"
atteso "lotto dopo il ripristino" "$ESITO" confermato
atteso "vini dopo il lotto" "$(sql 'select count(*) from catalog.wines')" "$(( VINI + 100 ))"

echo "RIPRISTINO CATALOGO: OK"
[ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "Ripristino dello schema catalog popolato ($VINI vini) sopra le migration del commit: OK." >> "$GITHUB_STEP_SUMMARY"
exit 0
