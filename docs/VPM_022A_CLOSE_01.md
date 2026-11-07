# VPM-022A-CLOSE — verifica del rilascio del 5 novembre 2026

## Autorizzazione e perimetro

Il founder ha autorizzato con l'incarico VPM-022A-CLOSE + VPM-022B il merge
della sola PR #285, la distribuzione automatica della relativa migration e le
letture successive di ledger, funzione e metadati. Nessuna applicazione manuale,
configurazione remota o ulteriore migration Production autorizzata.

## Merge e controlli

- PR #285 aperta e MERGEABLE sull'head atteso
  `1e32ee622722eb166a1e503cb06ab0418478cb35`; origin/main iniziale
  `f38b40e69b2c4b4dac0981f71297b13f91c27a01`.
- Sei check obbligatori verdi sullo stesso head; anche CodeQL, Gitleaks,
  Supabase Preview e gate browser verdi. Nessuna suite rilanciata manualmente.
- Ruleset `main-protection` verificato; unico blocco Code Owner. Squash merge
  con `--admin` e confronto atomico dello SHA, come consentito dal punto 5
  dell'incarico e da CLAUDE.md. Primo comando respinto dalla revisione automatica
  per autorizzazione al bypass ritenuta insufficiente; secondo autorizzato dopo
  nuova raccolta delle prove e citazione della disposizione esplicita.
- Merge eseguito il 5 novembre 2026 alle 21:33:58 UTC:
  `d2cb03fad618558c539e1cc1701048f440338cb0`, verificato su origin/main.
- Workflow automatici su main: CI `42113803024`, DB `42113802725`, browser
  `42113802864`, sicurezza `42113802766`: tutti conclusi con successo.

## Supabase Production: distribuzione automatica verificata

Progetto `pijnmcllmfgjmgsvtcej`, main default Production, ACTIVE_HEALTHY.
Letture di catalogo prima e dopo; nessun record applicativo letto o modificato.

- Ledger prima: 108; dopo: 109, tutte le versioni e i nomi identici a origin/main.
  Nessuna versione mancante o estranea. Presente versione `20261105205413`, nome
  `vpm_022a_rpc_request_path`. Check integrazione Production concluso SUCCESS.
- Definizione effettiva: `like '/rpc/%' then 60 else 120`.
- Confronto integrale della definizione prima/dopo: unica differenza il prefisso.
  MD5 prosrc prima `e408426e01b33c5417c471c83381b3a1`, dopo
  `5ff7040482df83dba88398998fb07764`.
- Owner `postgres`, SECURITY DEFINER, search_path vuoto e ACL identici:
  `{postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,authenticator=X/postgres,service_role=X/postgres}`.
- Su authenticator invariato `pgrst.db_pre_request=private.vinea_check_request`.
- Soglie 60/120 e finestra 60 secondi invariate; nessun db push o SQL mutativo
  manuale, carico hosted o richiesta di scrittura. request.path attraverso il
  gateway hosted **NON VERIFICATO**.

## Netlify: requisito del nuovo SHA non confermato

Il tentativo Production `6aecf648da80a45b5f48305e` è associato esattamente al
merge `d2cb03f`, ma risulta `error`, `published_at=null`:

> Canceled build due to no content change

[Dettaglio del tentativo](https://app.netlify.com/projects/timely-lokum-43a12e/deploys/6aecf648da80a45b5f48305e).
Nessuna differenza in `frontend-next/` o `netlify.toml` rispetto a `f38b40e`.
Resta pubblicato il precedente deploy `6aecced3e3f6be94800e1016`, `ready`, commit
`f38b40e69b2c4b4dac0981f71297b13f91c27a01`. Non risulta un nuovo frontend
pubblicato sul merge SHA. Nessun retry/deploy manuale o modifica di configurazione
eseguiti. Questo annullamento non è prova di un guasto del sito pubblicato.

## Stato e limite della consegna

Correzione DB rilasciata e verificata. Il founder ha accettato esplicitamente lo
skip Netlify atteso e autorizzato il passaggio a VPM-022B dopo CI verde. La
chiusura è COMPLETATA con tutti i workflow pertinenti verdi su main.
VPM-022B è iniziato soltanto dopo questa verifica.
I file locali preesistenti VPM-020/021 e l'aggiunta locale al rapporto VPM-022A
sono preservati. Questa nota è inclusa nell'handoff della PR dedicata VPM-022B.
