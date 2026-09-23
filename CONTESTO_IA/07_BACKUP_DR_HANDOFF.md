# Handoff Backup/Disaster Recovery B2

Aggiornato il 23 settembre 2026.

## Consolidato

- backup Supabase database/Auth e Storage cifrato con `age` su B2;
- Object Lock `GOVERNANCE`, retention e readback SHA-256 verificati;
- decrypt reale e restore isolato database/Auth/Storage riusciti, smoke 5/5;
- primo run schedulato `35833711496` riuscito con zero artifact GitHub;
- runbook per failover da zero separato tra backup B2, repository Git e
  configurazioni esterne;
- preflight non distruttivo in
  `.github/scripts/disaster-recovery-preflight.sh`;
- PR #139 integrata in `main` a `1dbdd0e`, CI post-merge `35846989974` verde.

La produzione non e stata modificata. Il ledger 60/60 della prova di restore
era preesistente nella branch derivata e non proveniva dall'archivio B2.

## Stato e residui

Il capitolo tecnico Backup/DR e chiuso e va riaperto soltanto per un guasto, un
incidente o un requisito nuovo. Restano non bloccanti la rotazione least
privilege della key B2 principale, senza `bypassGovernance` e `deleteFiles`, e
la rimozione non ancora confermata dalla lista Backblaze della key temporanea
read-only gia scaduta. La chiave privata `age` resta offline.
