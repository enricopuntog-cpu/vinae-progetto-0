# VPM-015B4 — Logistica completa degli Accessori

Contratto del sotto-blocco 015B4 (1 novembre 2026), costruito su
[VPM-015A](VPM_015A_ACCESSORI.md), [VPM-015B1](VPM_015B1_CANTINA_ACCESSORI.md),
[VPM-015B2](VPM_015B2_ANNUNCI_ACCESSORI.md), [VPM-015B3](VPM_015B3_PUBBLICAZIONE_ACCESSORI.md)
e sul motore logistico già distribuito ([VP-E](VP_E_LOGISTICA_MULTI_COLLO.md), WP6A/WP6B/WP6C).
Prepara il checkout successivo (B5), che **non** è avviato.

**Che cosa NON è.** Nessun ordine, checkout, pagamento, payout, spedizione, etichetta o
chiamata a un vettore. Nessuna tariffa è stata inventata, copiata o adattata dalle bottiglie:
la tabella delle tariffe Accessori nasce **vuota** e, finché non esiste una tariffa
`active` con una fonte commerciale, ogni stima risponde «non disponibile» con i motivi.
Visibile e stimabile non vuol dire acquistabile.

## 1. Che cosa riusa e che cosa aggiunge

| Riusato (nessun sistema parallelo) | Aggiunto (mancava) |
| --- | --- |
| `logistics_service_definitions` (provider, servizio, limiti operativi, idoneità), `logistics_service_capabilities` (capability esatta della rotta), reti PUDO e `logistica_servizio_reti_ok` | tariffe **per collo di Accessori**, per servizio × capability × classe di collo (le tariffe commerciali esistenti sono per *formato di bottiglia* con un `CHECK` sui formati: non descrivono un collo di accessori e non si toccano) |
| `preventivo_dominio('accessori_enologici', classe, …)` per commissione, margine, copertura della fee di pagamento | assicurazione contrattuale (vuota), pezzi per collo, pianificatore, preventivo congelato |
| guardie di rilascio (`accessori_rilascio_richiesto`, marcatore `vinae.accessori_rilascio`), `accessori_registro`, `rate_limit_consume`, visibilità `annuncio_accessorio_visibile` | interruttore `logistica_attiva` |

Nessuna tabella condivisa con le bottiglie è modificata (verificato dalla griglia 12zm, caso 39,
e dal test di contratto).

## 2. Modello dati (schema `private`, RLS, nessun grant client)

- `accessori_logistica_impostazioni` — singleton: `logistica_attiva` (**false**), `validita_preventivo_min`
  (15), `max_colli` (10), `versione` (cresce a ogni modifica). L'accensione richiede il ruolo
  `accessori_release` **anche per i writer privilegiati**; spegnere è di ogni admin.
- `accessori_logistica_tariffe` — versionata: `provider_code`, `service_code`, `capability`,
  `classe_codice`, ingombro massimo del collo (peso, tre lati in ordine decrescente),
  `fragile_ammesso`, `prezzo_cents` (finale, IVA inclusa, per collo), `fonte` (**obbligatoria per
  `active`**), `stato` (`planning → preactivation → active → retired`, a senso unico), finestra
  `effective_from/to`. Una riga non si modifica né si cancella: si chiude e se ne scrive una nuova
  (trigger valido per ogni writer). Una sola versione corrente per servizio × rotta × classe.
- `accessori_logistica_assicurazioni` — stesso versionamento; costo = `max(minimo, ceil(valore ×
  percentuale))`, con `valore_max_cents`. **Vuota**: nessun contratto la prevede.
- `annunci_accessori_logistica` — pezzi per collo dichiarati dal venditore (assente = 1),
  modificabili solo finché l'annuncio è `bozza` o `modifiche_richieste`.
- `accessori_logistica_preventivi` — preventivo **congelato** (§5).

Peso, tre misure e fragilità restano sull'annuncio (colonne B2, già dichiarate dal venditore).

## 3. Pianificatore e regole (fail-closed)

`private.accessori_logistica_piano(annuncio, quantità, capability, assicurazione)`:

1. quantità 1 – 120 e entro l'offerta; capability esatta (`PUDO_TO_PUDO` per il punto di ritiro,
   `PUDO_TO_HOME` per il domicilio); peso e misure presenti;
2. pezzi per collo `k` = dichiarazione del venditore, **1 se l'articolo è fragile**; colli =
   `⌈quantità / k⌉` (pieni + un eventuale collo di resto); oltre `max_colli` → `troppi_colli`;
3. un collo di `p` pezzi pesa `p × peso` e impila i pezzi sul **lato più corto** (regola
   dichiarata); i lati si confrontano ordinati, l'orientamento è libero;
4. servizi candidati: attivi, idonei, con tutti i limiti noti, la capability e le reti PUDO
   richieste; il collo deve stare nei limiti del servizio **e** in una classe di tariffa `active`
   (fragile solo se la classe lo ammette); **un solo servizio per ordine**, il più economico che
   regge tutti i colli;
5. assicurazione (solo se richiesta): servizio con contratto `active` e valore dichiarato entro il
   massimo; altrimenti **fallisce** (`assicurazione_non_prevista`), mai omessa in silenzio.

Motivi di rifiuto: `peso_mancante`, `misure_mancanti`, `quantita_non_valida`, `rotta_non_valida`,
`troppi_colli`, `servizio_per_rotta`, `tariffa_accessori_non_configurata`,
`tariffa_accessori_non_attiva`, `nessuna_classe_compatibile`, `fragile_non_ammesso`,
`assicurazione_non_prevista`, `preventivo_economico_non_disponibile`, `annuncio_non_disponibile`,
`destinazione_non_valida`. Con un rifiuto la risposta non contiene alcun importo.

## 4. Separazione di prezzo, commissione, pagamento e logistica

`private.accessori_logistica_preventivo` compone voci distinte, mai un numero unico:
`prezzo` (unitario × quantità, quello del venditore), `commissione` (da `preventivo_dominio`,
**non si applica alla logistica**), `pagamento.coperturaSuLogistica` (la copertura incrementale
della fee di pagamento già definita da `preventivo_dominio`, una sola quota fissa per ordine),
`logistica` (trasporto + assicurazione, colli) e `totaleAcquirenteCents` = somma esatta delle
voci. Il browser non invia mai un importo: il parser del frontend rifiuta una risposta le cui
somme non tornano al centesimo.

Modalità: il **punto di ritiro** è ordinabile; il **domicilio** si preventiva se un servizio lo
dichiara ma ha `ordinabile = false` (`domicilio_non_ordinabile`): l'indirizzo di consegna degli
Accessori appartiene all'ordine (B5).

## 5. Preventivo congelato

`accessori_logistica_preventivo_congela` (solo `authenticated`, solo punto di ritiro, mai il
proprio annuncio, 20 richieste/ora): scrive un preventivo **immutabile** (anche per un writer
privilegiato) con scadenza (15 minuti), impronta dei fatti che lo determinano (prezzo, versione
dell'annuncio, peso, misure, fragilità, pezzi per collo, quantità, destinazione, assicurazione) e
dettaglio interno (servizio e tariffe, mai esposti al browser). Una richiesta identica ancora
valida restituisce **lo stesso** preventivo (lock consultivo per acquirente e annuncio). Un
preventivo non riuscito non scrive nulla.

Per il checkout B5 esistono due funzioni **private** (nessuna porta client):
`accessori_logistica_preventivo_verifica` (valido / `scaduto` / `consumato` / `richiesta_diversa` /
`annuncio_cambiato` / `non_disponibile` / `non_trovato`) e `accessori_logistica_preventivo_consuma`
(uso unico, sotto lock di riga, marcatore transazionale). Spegnere la logistica invalida i preventivi
già emessi; se l'annuncio cambia (prezzo, misure, versione) il preventivo decade.

## 6. Porte

Pubbliche: `annuncio_accessorio_logistica_preventivo` (**anon + authenticated**, stima non
persistita, `stable`). Authenticated: `accessori_logistica_preventivo_congela`,
`accessori_logistica_preventivo_leggi` (solo il proprio), `annunci_accessori_logistica_imposta`
(venditore). Admin: `accessori_logistica_admin_stato`, `_imposta` (accendere = rilascio, motivo
registrato), `_tariffe_elenca`, `_tariffa_salva` (nuova versione che chiude la corrente; `active`
richiede il rilascio, il servizio deve esistere tra quelli logistici correnti). Tutte `SECURITY
DEFINER`, `search_path` vuoto, **nessuna esecuzione a `service_role`**; le funzioni private non
sono eseguibili da nessun ruolo client.

## 7. Frontend

`frontend-next`: `lib/accessori-spedizione/stima.ts` (parser rigido e messaggi italiani),
`services/accessori-spedizione-service.ts` (tre sole RPC, nessun argomento economico),
`StimaSpedizioneAccessorio` sulla scheda `/accessori/annunci/[id]`, **solo** con
`ACCESSORI_LOGISTICA_ENABLED=true` (server, spenta di default, documentata in `docs/ENVIRONMENT.md`
e `.env.example`). La scheda dichiara che gli acquisti non sono disponibili e non ha alcun comando
d'acquisto. Nessuna interfaccia admin per tariffe e interruttore: le porte esistono, la UI è
differita.

## 8. Prove

- Griglia `supabase/tests/12zm_vpm_015b4_logistica_accessori.sql` (**41 casi**, nel gate `Supabase DB
  regression`): stato iniziale e privilegi; accensione e rilascio; fail-closed uno per uno;
  accessorio singolo con totale calcolato indipendentemente; quantità multiple; pezzi per collo e
  multi-collo; fragile; peso/misure mancanti; fuori misura; troppi colli; domicilio; servizi
  incompatibili; assicurazione; congelamento, idempotenza, immutabilità, lettura, verifica, scadenza,
  impronta, uso unico, interruttore di emergenza; manipolazioni; versionamento; privilegi; nessun
  ordine/tariffa delle bottiglie toccati.
- **Mutazioni di controllo** sul database locale (ognuna rende rosso almeno un caso): tariffa non
  attiva accettata (8, 24), fragile ignorato (17, 24), proprio annuncio ammesso (29), marcatore di
  consumo rimosso (30–33), impronta senza versione/prezzo (33), interruttore ignorato (2, 3, 35),
  scadenza ignorata (32), assicurazione omessa (25, 27). Il solo prezzo fuori dall'impronta non
  rende rosso nulla perché la versione dell'annuncio lo copre già (difesa doppia).
- `frontend-next`: parser, servizio con client finto, viste, contratto statico (nessun import di
  checkout/ordini/pagamenti, nessun vettore, nessuna tariffa nel codice, forma della migrazione).
- Esecuzione locale: migrazione + griglia in **un'unica transazione con ROLLBACK** sullo stack
  condiviso (ledger identico a `origin/main`: 98 = 98), quindi senza alterarlo.

## 9. Configurazione mancante (commerciale e operativa)

Per accendere la logistica degli Accessori servono, tutti **non decisi né forniti**:

1. un servizio logistico reale attivo, idoneo, con i cinque limiti operativi e la capability
   `PUDO_TO_PUDO` (e `PUDO_TO_HOME` se si vuole il preventivo a domicilio), con reti PUDO e rubrica
   dei punti (i «lucchetti» WP6C già esistenti);
2. una tariffa commerciale **per collo di Accessori** per ciascuna classe (peso, ingombro, fragile sì/no)
   con la fonte contrattuale (offerta o contratto del vettore);
3. se si vuole l'assicurazione: il contratto che la prevede (percentuale, minimo, massimale);
4. la decisione del titolare sull'accensione (`accessori_release`: `logistica_attiva`, poi
   `ACCESSORI_LOGISTICA_ENABLED`) e sulle regole ancora aperte: pezzi per collo e impilamento oltre
   la regola prudente del lato più corto, domicilio ordinabile, IVA e condizioni di vendita dei
   beni non-vino (LEG/FIN/OPS).

## 10. Limiti dichiarati

- Nessuna prova di concorrenza su sessioni separate per `congela` e `consuma` (la serializzazione è per
  progetto — lock consultivo e `FOR UPDATE` — ma non misurata come in 12zk/12zc): debito aperto.
- `annunci_accessori_preventivo` (B2, lato venditore) continua a dire che la spedizione non è disponibile;
  la stima per annuncio è la nuova porta. Allineare la vista del venditore è lavoro di B5.
- Il dialogo del venditore non ha ancora il campo «pezzi per collo»: la porta esiste, senza valore vale 1.
- Nessuna UI admin per interruttore e tariffe. Le assicurazioni si configurano solo da SQL di
  produzione (nessuna porta admin): oggi non c'è nessun contratto.
- Il preventivo congelato non è collegato a un ordine: il consumo è predisposto per B5.
