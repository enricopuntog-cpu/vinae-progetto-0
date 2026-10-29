---
name: vinea-design
description: Progettazione e implementazione frontend di Vinea secondo design system e brand, usando la skill frontend-design quando disponibile e confrontando con la versione servita. Usare per modifiche a componenti, pagine o stili in frontend/ o frontend-next/.
argument-hint: "[componente, pagina o richiesta]"
paths:
  - "frontend/**"
  - "frontend-next/**"
---

# /vinea-design

Supporto alla progettazione e implementazione di interfacce Vinea.

Argomenti ricevuti: $ARGUMENTS

## 1. Fonti

- Linee guida Vinea: [references/brand.md](references/brand.md).
- Skill `frontend-design` del plugin ufficiale Anthropic
  (`frontend-design@claude-plugins-official`, versione e hash bloccati in
  `.github/scripts/claude-plugins.lock.json`). Usala per la qualità visiva e la
  cura dei dettagli, **subordinata** al brand Vinea: mai font, palette o stili
  nuovi in contrasto con i token esistenti.
- Se `frontend-design` non è disponibile nella sessione, prosegui con le sole
  linee guida Vinea e dichiaralo nel report. Non installare plugin.

## 2. Procedura

1. Trova il componente equivalente nella versione servita `frontend/` e parti
   da lì (regola di parità di `CLAUDE.md`): adatta, non riscrivere.
2. Usa token e componenti `ui/` esistenti; nessun colore esadecimale nei
   componenti, nessun nome di brand scritto a mano (usa `brand`).
3. Testi in italiano; stati vuoti, di errore e di caricamento; layout a 375 px
   senza scroll orizzontale.
4. Nessuna funzionalità applicativa nuova fuori dallo scope del task.

## 3. Verifica

- Controlli di `/vinea-test` sul frontend toccato.
- Screenshot a 375 e 1280 px quando un browser è disponibile; altrimenti
  `NON VERIFICATO` (non bloccante).
- Revisione con il subagente `vinea-ux-auditor`, passandogli file e screenshot.

## Completamento

Completo quando la modifica usa i token Vinea, è allineata alla versione servita
e i controlli frontend sono verdi o dichiarati `NON VERIFICATO`.
