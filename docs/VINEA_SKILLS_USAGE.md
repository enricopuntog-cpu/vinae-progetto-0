# Uso delle skill — Ciclo 2

31 ottobre 2026. Usare skill e tool solo nel perimetro del task ammesso; leggere prima `CLAUDE.md` e `CHANGES.log`. Questa guida non concede nuovi permessi né accesso a dati, reti o ambienti di produzione. Il registro `VINEA_SKILLS_REGISTRY.md` distingue prove runtime, analisi statiche e installazioni.

## Profilo e contesto

`frontend-design` v1.1.1 è il solo plugin già installato, project-scope nel profilo `vinea-coding` e nel worktree di Ciclo 1. Verificarne la presenza nel **worktree/profilo effettivi** prima di contare sul caricamento; il task isolato di design e il benchmark sono stati verificati, non ogni nuovo ambiente. `/vinea-external-skill-audit` è una skill di progetto manuale di triage preinstallazione; l'invocazione runtime della sua definizione versionata resta NON VERIFICATA. Le tre skill Marketing sono state copiate solo in progetti temporanei per i demo: non invocarle nel progetto corrente finché non siano deliberate e installate con review. SkillSpector è stato testato solo nel laboratorio, senza credenziali e senza LLM; non è un sigillo di sicurezza.

## Prompt modello (adattare al task reale)

- **Design:** «Per la pagina già ammessa, usa `frontend-design` per una variante isolata; rispetta palette, tipografia, accessibilità e feature flag correnti. Non cambiare il prodotto. Confronta desktop 1280 e mobile 375, registra screenshot e asserzioni, poi raccomanda adozione o scarto.»
- **Audit esterno:** «Valuta questa candidata con `/vinea-external-skill-audit` prima di qualsiasi installazione: fissa commit e licenza, inventaria script, hook, network, credenziali e costi; distingui osservazioni statiche da test runtime, non eseguire installer.» Se la skill non è caricata, segnare NON VERIFICATO e svolgere solo il triage autorizzato, senza fingere un'invocazione.
- **Copywriting, laboratorio isolato:** «Rivedi headline e CTA solo sui file copiati, indica ogni claim non supportato e proponi al massimo tre varianti non pubblicate. Non leggere dati utenti o pubblicare contenuti.»
- **SEO, laboratorio isolato:** «Confronta metadata e robots nei file copiati, separa analisi statica da crawl/indicizzazione non misurati; non suggerire di indicizzare route dietro gate.»
- **CRO, laboratorio isolato:** «Formula un'ipotesi e una metrica senza attribuire conversioni misurate; segnala baseline e verifica della sessione reale come prerequisiti.»
- **QA:** «Usa i test Playwright già mantenuti per la regressione pertinente; valuta CLI solo se serve un flusso diverso. Non duplicare una suite E2E o un owner già assegnato.»

## Regole operative

Un audit statico non autorizza installazione. Fissare versione e licenza, leggere sorgenti e dipendenze, eseguire soltanto in ambiente isolato dopo review, registrare copertura ed esito. Non installare automaticamente strumenti con licenze non chiarite, hook rischiosi, accessi a credenziali o nuovi costi. Non importare export Instagram privati, account o DM; non pubblicare le demo. Non modificare routing, fallback, modelli, compressione o TTL sulla base del solo audit cache. Nessuna modifica a Supabase/Netlify Production o dati reali per questo ciclo. Per il catalogo storico usare gli ID e le sintesi sanificate nel registro; gli URL originali restano fuori Git.
