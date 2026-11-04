# VPM-018-DB-GRID-01 — Superfici anonime: rate limit e capability (4 novembre 2026)

Chiude GAP-009 sul piano della prova. Nessuna migrazione e nessuna funzione modificata;
Production non letta né scritta. Tutte le prove girano su stack locali dedicati.

## 1. Cosa copriva già il repository

Lettura delle griglie `12r`…`12w`, tutte già nel gate `Supabase DB regression`:

| Controllo | Prima | Dove |
|---|---|---|
| Capability errata su `event_record` e completamento MV1 | **coperto** | `12r` casi 11-13 |
| Capability non trasferibile su `session_start` | **coperto** | `12r` caso 8 |
| Capability isolata tra sessioni QV2 (lettura e risposta) | **coperto** | `12t` caso 14, `12v` caso 11 |
| Evento con capability diversa | **coperto** | `12w` caso 3 |
| Helper private chiuse ai client | **coperto** | `12r` caso 33 |
| Capability errata su `finish_pre` e `finish_post` | **ASSENTE** | le griglie le chiamano solo con la capability giusta |
| **Superamento di un limite su qualunque porta anonima** | **ASSENTE** | nessuna griglia nomina `rate_limit` |

Il codice dei limiti esisteva già in tutte le porte. Mancava ogni prova che funzionasse.

## 2. Griglia aggiunta: `12zu_vpm_018_superfici_anonime.sql`

Agganciata a `12g_ci_run.sh`, con transazione chiusa da `ROLLBACK` e guard sugli utenti.

| Casi | Cosa prova |
|---|---|
| 1 | Elenco chiuso delle 7 porte anonime che scrivono, tutte con limitatore: una porta nuova fa fallire la griglia |
| 2-8 | Oltre soglia ciascuna delle 7 porte risponde 429 `rate_limit_exceeded` con il proprio scope e limite, senza scrivere |
| 9-10 | Conteggio reale senza semina: 12 passano e la 13ª è rifiutata; 120 e la 121ª |
| 11-12 | Il limite di una capability non blocca le altre; i bucket conservano solo l'impronta |
| 13-18 | Capability errata o malformata su ogni porta legata alla sessione, senza scritture |
| 19 | Una capability MV1 non apre una sessione QV2 |
| 20 | Limitatore, bucket e sessioni chiusi ad `anon` e `authenticated` |
| 21 | Tetto globale per IP della richiesta PostgREST |
| 22-24 | **Limiti noti** (§ 3): descrivono lo stato attuale e diventano rossi quando vengono corretti |

Le altre funzioni eseguibili da `anon` sono `stable`, quindi di sola lettura: 21 funzioni
elencate dalla stessa interrogazione del caso 1, fuori da questa griglia.

## 3. Rischi verificati, non corretti

**R-MV-01 — P3 — Le sessioni anonime del Beta Test non hanno un tetto complessivo.**
Il limite è per capability, e la capability è un UUID scelto dal client: cambiandola il
limite riparte (caso 22). `beta_validation_qv2_start` assegna ogni volta il primo codice
libero fra V001 e V999, e a codici esauriti rifiuta tutti.

- **Impatto**: un anonimo può inquinare i dati della validazione e, esaurendo i codici,
  impedire il Beta Test ai tester veri. Nessun dato personale, denaro o dominio commerciale
  coinvolti (griglie `12r`).
- **Quanto è facile**: il solo freno è il tetto globale di 60 POST al minuto per IP, quindi
  circa 17 minuti da un solo indirizzo (stima dal codice, non misurata).
- **Non verificato**: se la funzione è raggiungibile così in Production e se il proxy
  riscrive `x-forwarded-for`. Sul percorso locale l'intestazione è accettata com'è (caso 23).
  Se anche in Production lo fosse, il tetto globale per IP non frenerebbe un attaccante.
- **Correzione possibile, non applicata**: serve una migrazione e una scelta di prodotto,
  fuori dal perimetro «solo test». Opzioni: tetto globale di nuove sessioni per ora nel
  database; codici di invito; chiudere le porte a fine campagna.

**Caso 24 — nota, nessuna azione.** Una risposta rifiutata annulla anche l'incremento del
contatore perché è nella stessa transazione. Le richieste invalide non consumano il limite;
non scrivono nulla e la capability a 122 bit non è indovinabile.

## 4. Prove

Stack dedicato `vinea_e2e`, Postgres dello stack locale, 108 migrazioni, `ROLLBACK`.

| Prova | Esito |
|---|---|
| Griglia sul codice attuale | **24/24** |
| Residui dopo la corsa | `rate_limit_buckets` 0, `beta_validation_sessions` 0 |
| M1 `qv2_start` senza limite | rossi casi 1, 2 |
| M2 `qv2_answer` senza limite | rossi casi 1, 4 |
| M3 `session_start` senza limite | rossi casi 1, 8, 9 |
| M4 nuova porta anonima di scrittura | rosso caso 1 |
| M5 limitatore aperto ad `anon` | rosso caso 20 |
| M6 capability ignorata in QV2 | rossi casi 13, 14, 15, 16 |
| M7 tetto globale spento | rosso caso 21 |

Limite: i casi usano SQL con `set local role anon`, quindi non passano da PostgREST. In
particolare il tetto globale è chiamato direttamente con le impostazioni della richiesta.
Il gate CI esegue la griglia sullo stack effimero costruito dalle migrazioni del commit.
