# VP-D — Classi economiche e vendita professionale Partner

Blocco D del filone «Vinea Partner + Quantità multiple» (vedi
[`ROADMAP_V1.md`](ROADMAP_V1.md#filone-vp--vinea-partner--quantità-multiple)).
Avviato dal titolare il 12 ottobre 2026: **due classi economiche autorevoli —
privati 8% (800 bps), Partner professionali 15% (1500 bps) — con lo stesso
algoritmo di margine obiettivo**, e predisposizione completa del commercio
professionale senza accenderlo.

Questo documento è il contratto tecnico del blocco. Lo stato di ogni parte è in
fondo; ciò che è solo predisposto è scritto come tale.

## 1. Decisioni vincolanti

- Margine obiettivo Vinea: **800 bps** per i privati, **1500 bps** per i
  Partner. Il 16% (1600 bps) della specifica del 14 settembre 2026
  ([`ALIQUOTA_PER_CLASSE_VENDITORE_SPEC.md`](ALIQUOTA_PER_CLASSE_VENDITORE_SPEC.md))
  è superato e non compare in nessuna riga.
- Il venditore indica **quanto vuole ricevere** per bottiglia. Il prezzo per
  l'acquirente è la piattaforma ad aggiungere la commissione che realizza il
  margine obiettivo **al netto della fee di pagamento di riferimento**: non si
  sottrae nulla dal prezzo del venditore e non si moltiplica per 1,15.
- **Una formula sola** per tutte le classi: `private.marketplace_totale_cents`
  (Fase 7b), invariata.
- La fonte di verità della commissione è il database; il frontend rappresenta
  un preventivo che il database gli dà.
- `vendita_partner = false`, `ordini_multi_unita = false`,
  `PAYMENTS_ENABLED=false`: invariati in produzione.

## 2. La formula e la sua dimostrazione

    totale = ceil( (subtotale × (10000 + margine) + fisso × 10000)
                   / (10000 − percentuale) )
    commissione = totale − subtotale
    subtotale   = prezzo per bottiglia × N

Parametri correnti (stessi per le due classi): percentuale di riferimento
**209 bps**, quota fissa **25 centesimi**, finestra di verifica **2 giorni**.
La quota fissa si applica **una volta per ordine**, sul subtotale.

| Prezzo venditore | Privati (800) | Partner (1500) |
| --- | --- | --- |
| 10,00 € | 11,29 € | 12,01 € |
| 45,00 € | 49,90 € | 53,11 € |
| 100,00 € | 110,57 € | 117,72 € |
| 2.500,00 € | 2.757,89 € | 2.936,63 € |
| 6 × 45,00 € = 270,00 € | 298,08 € | 317,39 € (non 6 × 53,11 = 318,66 €) |

Su 45 € Partner: 45 × 1,15 = 51,75; più 0,25 = 52,00; diviso 0,9791 =
53,1100… → **53,11 €**. Il pagamento di riferimento costa 53,11 × 2,09% + 0,25 =
1,36 €, e a Vinea restano 53,11 − 1,36 − 45,00 = 6,75 € ≥ 15% di 45 €.
L'arrotondamento è sempre per eccesso: un centesimo in meno porterebbe il
margine sotto l'obiettivo (provato su 6000 prezzi, griglia 12zb caso 6).

Per i Partner la differenza fra il prezzo che chiedono e quello pagato
dall'acquirente **non è «una commissione del 15%»**: è il margine Vinea del 15%
più il costo del pagamento di riferimento. L'interfaccia lo spiega così.

## 3. Configurazione versionata per classe

Migrazione `20261012200000_vp_d_classi_economiche.sql`. Strada A della
specifica storica (§3, §7), aggiornata a 1500 bps:

- tipo `public.classe_venditore` (`privato`, `partner`); una classe nuova è una
  label più una riga, il risolutore e la formula non cambiano;
- `marketplace_config.classe_venditore` **senza default**; l'indice
  `marketplace_config_una_corrente` (una riga aperta in tutto) è sostituito da
  `marketplace_config_una_corrente_per_classe` (una riga aperta **per
  classe**), la stessa forma di `packaging_options`;
- riga Partner a 1500 bps con fee e finestra **copiate dalla riga privata
  corrente**; regola operativa nel commento della tabella: una variazione dei
  parametri condivisi chiude e riapre tutte le righe correnti;
- `private.marketplace_config_corrente(classe)`; la versione a zero argomenti è
  **eliminata** (un overload che assume «privato» applicherebbe in silenzio
  l'8% a un Partner) e i suoi tre chiamanti sono ricreati: checkout (classe
  risolta), consegna (classe congelata sull'ordine) e preventivo logistico
  generico (classe `privato` dichiarata: non conosce un annuncio e il checkout
  non lo usa);
- classe senza riga corrente → nessun ripiego: checkout rifiutato
  (`configurazione_classe_mancante`), preventivo nullo con motivo.

`public_marketplace_config` restituisce una riga per classe con
`classe_venditore` in coda. Il servizio frontend che la leggeva con
`.maybeSingle()` non era usato da nessuna pagina.

## 4. Classe decisa dal database

`private.venditore_classe_di(annuncio)` (sola lettura) e
`private.venditore_classe_risolvi(annuncio, blocca)` (momento autorevole: prende
FOR SHARE le righe Partner del venditore, poi decide con lo stesso nucleo).
Fonti: annuncio, unità offerte, Partner delle unità, titolare, stato
dell'account, interruttore. Nessun argomento del chiamante.

| Caso | Classe | Vendibile |
| --- | --- | --- |
| Annuncio personale di un privato (anche con qualifiche, sommelier, certificazioni) | `privato` | sì |
| Annuncio personale di un Partner **invitato** o **in verifica** | `privato` | sì |
| Annuncio personale di un Partner **attivo** o **sospeso** | `partner` | **no** (`partner_annuncio_personale`) |
| Prodotto commerciale, Partner attivo, titolare attivo, interruttore acceso | `partner` | sì |
| Prodotto commerciale, interruttore spento | `partner` | no (`partner_vendita_non_disponibile`) |
| Prodotto commerciale, Partner sospeso | `partner` | no (`partner_sospeso`) |
| Prodotto commerciale, Partner revocato o non attivo | `partner` | no (`partner_non_attivo`) |
| Prodotto commerciale con unità di un altro Partner o di un Partner non del venditore | `partner` | no (`partner_incoerente`) |

Un Partner non ottiene mai la tariffa dei privati: le sue unità commerciali
non entrano in un annuncio personale (classe d'inventario immutabile, VP-C), e
i suoi annunci personali non sono acquistabili finché il Partner è attivo o
sospeso. La revoca è solo amministrativa (`partner_admin_decidi`): il titolare
non può revocarsi per tornare all'8%.

### 4.1 Decisione aperta: Partner revocato

**Nessuna politica nuova è stata introdotta.** Comportamento corrente,
preservato: un Partner revocato conserva lo storico; i suoi prodotti
commerciali restano `partner` e non vendibili per sempre (non esiste un
percorso per declassarli); i suoi annunci personali tornano ai percorsi dei
privati, come prima di VP-D. Alternative per il titolare, da decidere **prima
dell'accensione di `vendita_partner`**:

1. mantenere il comportamento corrente;
2. estendere il blocco degli annunci personali anche al revocato (per sempre o
   per un periodo);
3. applicare la tariffa Partner agli annunci personali di chi è o è stato
   Partner.

Ognuna è una modifica locale a `private.venditore_classe_di` e alla vista
`public_listings` (stessa regola, inline).

## 5. Congelamento e coerenza degli ordini

- `orders.venditore_classe` (non nulla, nessun default sulla colonna): scritta
  dal checkout con la classe risolta; gli ordini esistenti sono `privato`
  (in produzione zero ordini al 12 ottobre 2026).
- Restano congelati come prima: quantità, prezzo unitario, subtotale
  (`prezzo_cents`), commissione, totale, margine e parametri di riferimento.
  Il payload `checkout_reserved` e la risposta del checkout portano la classe.
- Trigger `orders_partner_checkout_gate` (stesso nome dei blocchi A-C, corpo
  nuovo), vincola **ogni writer**, anche `postgres`/`service_role`:
  vendibilità dal risolutore (`partner_checkout_non_disponibile`), classe
  dichiarata = classe risolta (`classe_incoerente`), e per un ordine `partner`
  parametri uguali alla riga Partner corrente e commissione = formula
  (`economia_incoerente`). Un annuncio inesistente risponde ancora per
  venditore come nei blocchi A/B (poi fallisce la chiave esterna).
- Trigger `orders_economia_immutabile`: classe, margine, parametri,
  commissione, prezzi, quantità, annuncio e venditore non cambiano dopo la
  creazione (`ordine_economia_immutabile`).
- Liquidazione, saldo, payout, contestazioni, rimborsi e riconciliazione non
  leggono la classe né lo stato del Partner: un pagamento avvenuto si liquida
  anche se il Partner viene sospeso. `order_margine_riconciliazione` ha
  `venditore_classe` in coda.

### 5.1 Semantica transazionale dei cambi di stato

Il checkout prende il lock dell'annuncio, poi FOR SHARE le righe Partner del
venditore; `partner_admin_decidi` le prende FOR UPDATE. Quindi:

- checkout in corso e sospensione concorrente → la sospensione attende il
  commit; l'ordine nasce `partner` a 1500 bps; i checkout successivi sono
  rifiutati;
- sospensione in corso e checkout concorrente → il checkout attende, legge
  «sospeso» e non crea ordine né prenotazione;
- approvazione in corso di un Partner in verifica e checkout di un suo
  annuncio personale → il checkout attende e lo rifiuta: nessun ordine all'8%.

Provato su sessioni PostgreSQL separate (`12zb_vp_d_concorrenza.sh`); senza il
blocco FOR SHARE tre prove su quattro falliscono.

## 6. Gate

| Porta | Regola VP-D |
| --- | --- |
| `order_checkout_reserve[_saldo]` | classe e vendibilità dal risolutore sotto lock; riga della classe; classe congelata |
| trigger ordini | vedi §5 |
| trigger proposte (`proposals_partner_gate`) | stesso risolutore; le proposte esistenti verso un Partner poi sospeso non diventano ordini perché il checkout rivalida |
| `listing_pubblica` | un prodotto commerciale si pubblica solo se vendibile (interruttore, Partner attivo, titolare, unità coerenti) |
| `public_listings` | prodotto commerciale visibile solo con interruttore acceso, Partner attivo, venditore titolare e account attivo (prima bastava l'interruttore); colonna `venditore_classe` in coda |
| `vetrina_partner_catalogo` | invariata: legge `public_listings` |

Con `vendita_partner = false` (produzione) tutto ciò che è commerciale resta
in bozza e non acquistabile, come in VP-C, con gli stessi codici d'errore.

## 7. Preventivi autorevoli e catalogo

- `listing_preventivo(annuncio, quantità = 1, prezzo_unitario = null)` —
  `anon` e `authenticated`; solo annunci pubblici o propri. Restituisce
  classe, `acquistabile`, motivo, disponibili, imballaggio corrente e
  `preventivo` (subtotale, commissione, totale, parametri) calcolato con la
  stessa riga e la stessa formula del checkout. Il prezzo unitario facoltativo
  serve a proposte e controproposte; la classe non è un parametro. Preventivo
  nullo se la classe non è vendibile (salvo il titolare con l'interruttore
  spento, che vede il preventivo del suo prodotto) o se manca la
  configurazione.
- `preventivo_vendita(prezzo, quantità, inventario)` — `authenticated`: il
  preventivo con la classe che il database attribuisce al chiamante per quella
  classe d'inventario; un Partner che prepara un annuncio personale riceve
  «non vendibile» senza prezzo.
- `prodotti_partner_miei()` — `authenticated`: i prodotti commerciali del
  titolare (tutti gli stati) con conteggi per unità, vendibilità e preventivo
  per una bottiglia alla tariffa Partner.

### 7.1 Interfacce (parte 2)

Il browser non sceglie mai un'aliquota: `frontend-next/src/services/preventivo-service.ts`
legge le tre porte con parser che rifiutano una risposta incoerente
(subtotale ≠ prezzo × quantità, totale ≠ subtotale + commissione) e la
trasformano in «prezzo non disponibile».

- **Scheda annuncio**: scomposizione «prezzo per bottiglia · servizio Vinea ·
  totale stimato» con l'etichetta della classe, solo quando il preventivo è
  acquistabile o per il venditore (vista «Ricevi / l'acquirente paga»).
  Nessun pulsante d'acquisto o di proposta dove il database rifiuterebbe.
- **Proposta**: stima del totale per il prezzo proposto da
  `listing_preventivo(…, prezzo_unitario)`.
- **Checkout**: prezzo e quantità di una proposta accettata letti dal server
  (`proposals`), riepilogo da `riepilogoCheckout`; rimossa la stima locale
  con parametri fissi. Importi al centesimo.
- **Ordini**: «N bottiglie × prezzo» e la classe congelata (`venditore_classe`).
- **Area Partner (`/cantina` commerciale)**: «Crea prodotto» dalle unità
  commerciali libere (quantità, «Vuoi ricevere, per bottiglia», condizione,
  conservazione, descrizione) con anteprima `preventivo_vendita`; il prodotto
  nasce in bozza (`listing_crea_lotto`). Fotografie e testi si curano dalla
  scheda con «Modifica» (stesse policy Storage del titolare). Catalogo
  `prodotti_partner_miei` con stato, conteggi e «Ricevi … · l'acquirente
  paga …». Pubblicazione dalla scheda solo quando il preventivo lo permette;
  con `vendita_partner` spento una nota spiega che la pubblicazione non è
  aperta.

### 7.2 Nota operativa sull'interruttore

Spegnere `vendita_partner` dopo averlo acceso lascia i prodotti commerciali
già `attivo` nascosti agli acquirenti e non modificabili dal titolare
(`partner_vendita_non_disponibile` in `listings_bottiglia_idonea`). Prima di
spegnerlo, se il titolare deve poter modificare i prodotti, vanno sospesi.

## 8. Prove

Griglia `supabase/tests/12zb_vp_d_classi_economiche.sql` (33 casi, nel gate
`Supabase DB regression`) e `supabase/tests/12zb_vp_d_concorrenza.sh` (4 prove
su sessioni separate, residui 0, interruttore ripristinato e verificato).
Le griglie 12o, 12q, 12x, 12y, 12z e 12za asserivano «una riga corrente a
800 bps»: ora filtrano la classe `privato`, che resta l'invariante che
intendevano.

## 9. Stato

| Parte | Contenuto | Stato |
| --- | --- | --- |
| 1 | Configurazione per classe, risolutore, checkout e gate, congelamento, preventivi, catalogo, griglie | In produzione: PR #216, merge `8349d46`; ledger 86 = 86 file su `origin/main`; righe correnti 800/1500 bps con fee 209 bps + 25 c, interruttori `false/false`, verifiche del 12 ottobre 2026 |
| 2 | Interfacce: preventivo autorevole su scheda, checkout, proposte e vendita; catalogo e prodotti nell'area Partner; classe negli ordini | In produzione: PR #217, merge `f1f4ca6`; E2E locale nel browser (interruttore acceso solo in locale e ripristinato); bundle di produzione verificato il 12 ottobre 2026 |
| 3 | Verifica finale, documentazione e handoff | Fatto il 12 ottobre 2026. `vendita_partner` spento: nessuna vendita Partner operativa |
