# VPM-015C — Accessori nuovi dei Vinea Partner

Contratto del 2 novembre 2026, costruito su B1–B5C. **Integra, non riscrive**:
nessun sistema ordini, pagamenti, saldo, vetrina o inventario parallelo.
Nessun interruttore viene acceso; nessun pagamento, spedizione o payout reale.

## 1. Modello

Una scorta commerciale è una riga di `private.cantina_accessori` (stessa
tabella di foto, categoria, catalogo, annuncio, checkout B5A, pagamenti B5B,
post-vendita B5C) con due colonne in più: `inventario` (`personale` |
`commerciale`) e `partner_id`. `bottle_units` non si usa (sono bottiglie).

- **Immutabili** anche per i writer privilegiati (trigger
  `cantina_accessori_inventario_guard`). Una scorta commerciale nasce solo dalla
  porta Partner (marcatore transazionale legato a titolare e id); il Partner è
  quello ATTIVO del titolare, ricavato dal database.
- **Vincoli di tabella**: commerciale ⇒ `partner_id` presente, condizione
  `nuovo`, visibilità `privata` (mai nella Cantina pubblica personale).
- **Scorte aumentabili solo con Partner attivo** (un sospeso/revocato conserva
  ciò che ha, non ne aggiunge).
- **Storico** `private.accessori_partner_movimenti`: append-only, senza grant,
  scritto da trigger per ogni variazione di quantità (`carico`, `rettifica`,
  `vendita`, `rimozione`). La vendita è marcata dal nucleo B5B.

## 2. Classe del venditore per articolo

`private.annuncio_accessorio_venditore(uuid)` (privati) resta invariata. Un
overload `(uuid, uuid)` decide per l'articolo: personale ⇒ come prima (un
Partner attivo/sospeso non vende accessori personali, un revocato è bloccato);
commerciale ⇒ solo il Partner proprietario, **attivo**, con account attivo ⇒
classe `partner`. `vendibile` aggiunge l'interruttore esistente
`vendita_partner` (spento): senza, l'annuncio si prepara ma non è visibile né
acquistabile. Sei funzioni sono state ricreate con una sostituzione puntuale
(asserzione: ogni sostituzione deve avvenire una volta sola, altrimenti la
migrazione si ferma): guardia annunci, visibilità, salva, preventivo, logistica,
checkout; più il nucleo di vendita (marcatore dello storico) e l'elenco della
Cantina personale (solo `personale`).

Economia: formula unica `preventivo_dominio`, riga 1500 bps già presente in
`marketplace_margini_dominio` (20,00 € ⇒ 23,75 €; privato 22,73 €; 3 × 20,00 €
con quota fissa una sola volta). Spedizione fuori dalla base commissionale.
Aliquote del vino invariate.

## 3. Porte (tutte `authenticated`, tranne l'ultima anche `anon`; nessuna a `service_role`)

`accessori_partner_stato`, `accessori_partner_scorte_elenca`,
`accessori_partner_scorta_salva` (riusa `cantina_accessori_salva`: categoria,
catalogo, foto, quantità; condizione forzata `nuovo`),
`accessori_partner_scorta_archivia`, `accessori_partner_movimenti_elenca`,
`accessori_venditore_pubblico` (classe `partner`/`privato` di un annuncio
visibile; per un privato mai l'identità).

Un Partner sospeso o revocato consulta soltanto: la porta Partner rifiuta ogni modifica (`partner_non_attivo`); `titolare_id` nel venditore pubblico è l'id della vetrina Partner già pubblica (`/profilo/<id>`), mai quello di un privato.

Catalogo: una scheda pubblicata si collega con `catalogo_slug`; una scheda in
bozza è rifiutata; un prodotto non in catalogo è una **proposta libera** (nessuna
scheda creata: la curatela resta dell'admin, rinviata).

## 4. Frontend

Stessa schermata della Cantina Accessori con `modalita="partner"` in
`/partner/accessori`; servizio `creaPartnerAccessoriService` (stessa interfaccia,
tre metodi sulle porte Partner). Scheda annuncio: avviso «Articolo nuovo ·
Venditore professionale Vinea Partner» con link alla vetrina, o «Articolo
personale di un privato». Vendita, prezzo/margine, foto e ordini riusano
`VenditaAccessorio`, `/ordini-accessori` e il post-vendita esistenti.

## 5. Guardia della concorrenza 12zp

Un indirizzo privato (172.16/12), `CI=true` o l'assenza di utenti reali non
provano che il database sia lo stack effimero. Ora `12g_ci_run.sh`, superati i
propri controlli (loopback, ledger = file, nessun utente estraneo), scrive un
nonce casuale nel **commento del database** (`vinea-ephemeral-stack:<nonce>`) e
lo passa in `E2E_STACK_NONCE`; `12zp` lo esige uguale (uscita 3 altrimenti) e il
runner lo toglie in uscita. Prova negativa nel gate: senza nonce, nonce errato,
marcatore assente, URL con `?host=` ⇒ quattro rifiuti con uscita 3. La logica
finanziaria B5C non è toccata.

## 6. Prove

Griglia `12zr` (24 casi) in transazione con ROLLBACK; controlli per mutazione
(vendibile sempre vero e guardia dell'inventario rimossa: la griglia si ferma
sulla fixture; storico rimosso: 7 casi rossi). Frontend-next 3262 test (+6).
Concorrenza 12zp 8/8 sul clone locale con nonce corretto.

## 7. Prerequisiti di lancio (non decisi qui)

LEG/OPS: condizioni del venditore professionale, IVA/fatturazione, regole di
reso e recesso dei beni nuovi, tariffe logistiche commerciali verificate,
accensione di `vendita_partner`, `accessori_release` e dei flag server. NON
VERIFICATO: E2E Playwright dei percorsi Partner (richiede lo stack Supabase
completo), curatela del catalogo per le proposte dei Partner.
