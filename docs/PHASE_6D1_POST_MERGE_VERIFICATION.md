# Fase 6d-1 — verifica post-merge

Data: 30 luglio 2026

## Perimetro

Questa verifica chiude esclusivamente il gate remoto rimasto aperto dopo il
merge della PR #14. Non riesegue audit o test delle Fasi 1–6c e non avvia la
Fase 6d-2a.

Progetto Supabase verificato:

- nome: `vinea wine club`;
- project ref: `pijnmcllmfgjmgsvtcej`;
- regione: `eu-west-1`;
- stato rilevato: `ACTIVE_HEALTHY`.

Il verifier read-only della repair resta quello già documentato:
**13/13 `PASSA`**. Non è stato rieseguito perché non è emersa deriva di schema
o di privilegi.

## Autorizzazioni

Nella sessione corrente sono state ottenute autorizzazioni esplicite e
separate per:

1. eseguire le griglie remote che creano e cancellano fixture;
2. applicare la migrazione additiva che corregge la codifica dei messaggi;
3. rieseguire la griglia follow-up dopo la correzione.

## Anomalia rilevata e correzione

La prima esecuzione della griglia follow-up ha restituito:

| Passa | Fallisce | Totale |
| ---: | ---: | ---: |
| 9 | 2 | 11 |

I casi falliti erano:

| Caso | Invariante | Esito funzionale | Causa del fallimento |
| ---: | --- | --- | --- |
| 8 | una bottiglia ceduta non può essere aperta | rifiuto `P0001` corretto | messaggio remoto codificato come `Questa bottiglia Ã¨ giÃ  stata venduta...` |
| 9 | una bottiglia ceduta non può essere cancellata | rifiuto `P0001` corretto | stesso testo remoto corrotto |

Le definizioni locali contenevano il testo UTF-8 corretto. La deriva era
limitata ai corpi remoti di `bottiglia_apri(uuid,text)` e
`bottiglia_cancella(uuid)`.

La correzione è stata registrata come migrazione additiva:

```text
20260730162046 fix_6d1_bottle_message_encoding
```

La migrazione usa `CREATE OR REPLACE FUNCTION`, conserva firme e OID, non
modifica dati applicativi e riconferma `EXECUTE` al solo ruolo
`authenticated`.

File locale allineato alla versione assegnata dal server:

```text
supabase/migrations/20260730162046_fix_6d1_bottle_message_encoding.sql
```

## Risultati finali

### Griglia principale

Script:
`supabase/tests/6d-1_invarianti_sicurezza.sql`

| Passa | Fallisce | Totale |
| ---: | ---: | ---: |
| **33** | **0** | **33** |

Non è comparsa la riga 99 di errore fuori dai casi.

### Griglia follow-up

Script:
`supabase/tests/6d-1_followup_invarianti.sql`

| Passa | Fallisce | Totale |
| ---: | ---: | ---: |
| **11** | **0** | **11** |

Non è comparsa la riga 99 di errore fuori dai casi.

## Residui fixture

Il controllo read-only eseguito dopo le griglie ha restituito zero per tutte
le categorie:

| Categoria | Residui |
| --- | ---: |
| `auth.users` | 0 |
| `profiles` | 0 |
| `user_roles` | 0 |
| `wines` | 0 |
| `bottle_units` | 0 |
| `listings` | 0 |
| `cellar_environments` | 0 |
| `cellar_modules` | 0 |
| `cellar_slots` | 0 |

## Gate

Il gate tecnico post-merge della Fase 6d-1 è verde:

- griglia principale: **33/33**;
- griglia follow-up: **11/11**;
- verifier repair storico: **13/13**;
- residui fixture: **0**.

La Fase 6d-2a resta non iniziata. Può essere proposta soltanto dopo
l'integrazione della draft PR #16 in `main` e una nuova approvazione esplicita.
