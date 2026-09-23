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
- PR #139 integrata in `main` a `1dbdd0e`, CI post-merge `35846989974` verde;
- riapertura mirata del 23 settembre per il ritardo dello scheduler GitHub
  (da circa 2 ore a 5 ore e 35 minuti misurati): PR #148 a `c41102a`, backup
  `17 2,14 * * *` UTC con weekly/monthly una volta per giorno UTC, freshness
  watch orario e dopo ogni backup con issue `backup-freshness-alert` oltre 20
  ore; verificati con backup `35890425580`, watch PASS e prova d'allarme
  (issue #149 aperta e chiusa);
- obiettivi Beta: RTO 24 ore, RPO target 24 ore, non garantiti; da rifissare
  prima dei pagamenti reali.

La produzione non e stata modificata. Il ledger 60/60 della prova di restore
era preesistente nella branch derivata e non proveniva dall'archivio B2.

## Stato e residui

Il capitolo tecnico Backup/DR e chiuso e va riaperto soltanto per un guasto, un
incidente o un requisito nuovo. Backup e allarme dipendono entrambi da GitHub
Actions: nessun monitor esterno, e le schedule di un repository pubblico si
disattivano dopo 60 giorni senza attivita. Restano non bloccanti la rotazione least
privilege della key B2 principale, senza `bypassGovernance` e `deleteFiles`, e
la rimozione non ancora confermata dalla lista Backblaze della key temporanea
read-only gia scaduta. La chiave privata `age` resta offline.
