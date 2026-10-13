# Resoconto di chiusura pre-lancio per il Business Plan (13 ottobre 2026)

Documento datato. Fotografa lo stato tecnico ed economico di Vinea alla
chiusura del perimetro di sviluppo pre-lancio (PR #228). Non sostituisce
`CHANGES.log` né le specifiche di dominio.

Legenda, applicata a ogni numero:

- **FATTO VERIFICATO** — misurato nel codice, nel database di produzione
  (`pijnmcllmfgjmgsvtcej`) o in un test eseguito.
- **SIMULAZIONE** — calcolato con le funzioni reali del database su valori
  ipotetici o su listini non attivi. Non è un ricavo, un costo né un preventivo.
- **OBIETTIVO** — valore deciso dal titolare, configurato come riferimento,
  mai bloccante.
- **REQUISITO DIFFERITO** — non implementato o non attivo per scelta; serve una
  decisione, un contratto o una nuova fase.

**Vinea non è pronta al lancio commerciale**: pagamenti reali e spedizioni
reali mancano dell'attivazione contrattuale e operativa. È chiuso il
perimetro di sviluppo pre-lancio concordato.

## 1. PR e migrazioni (FATTO VERIFICATO)

| Voce | Valore |
|---|---|
| Ultima PR del perimetro | #228 — rubrica indirizzi e scelta PUDO/domicilio nel checkout (solo interfaccia) |
| PR precedenti del filone | #209-#227 (VP-A … VP-F, fix fee #223, sicurezza Partner #225, indirizzi/logistica API #226) |
| Migrazioni in produzione | 92 = 92 file su `main`, ultima `20261013160000_logistica_indirizzi_api.sql` |
| Migrazioni nuove in #228 | 0 |
| Test `frontend-next` | 2701 (soglia CI 2701) |
| Griglie DB nel gate `Supabase DB regression` | 12e-12zg, 7c, concorrenza 12z/12zb/12zc (esiti in `CHANGES.log`) |
| Ordini, indirizzi, Partner in produzione | 0, 0, 0 |

## 2. Architettura e funzionalità completate (FATTO VERIFICATO)

- Frontend servito `frontend/` + backend FastAPI/MongoDB; `frontend-next/` +
  Supabase è la beta pubblica separata. Il cutover (Fase 13) **non** è avvenuto.
- Marketplace fra privati con classe economica per venditore (privato /
  Partner), quantità multiple per ordine (VP-C), vetrina Partner su invito
  (VP-A/B), classi economiche (VP-D), logistica multi-collo (VP-E), registri
  Paese/valuta con serratura su IT/EUR (VP-F), copertura della fee di
  pagamento sugli accessori (#223), Partner revocato senza vendite fino a
  riabilitazione (#225), indirizzi strutturati, ritiro a domicilio/in sede,
  domicilio ordinabile, congelamento degli indirizzi sull'ordine, coda
  idempotente per gli adattatori dei corrieri (#226).
- PR #228: rubrica privata in `/account`; checkout con punto di ritiro
  predefinito o domicilio dalla rubrica; destinazione registrata con
  `checkout_consegna_imposta` prima della prenotazione; totale dalla
  destinazione scelta; conferma chiusa con il motivo se mancano servizio,
  tariffa, capability, indirizzo di consegna o di ritiro; indirizzo di ritiro
  del privato nel wizard di vendita; sede commerciale del Partner riusata in
  sola lettura.
- Riservatezza: la rubrica non ha grant client (solo porte del titolare); la
  controparte di un ordine vede solo tipo, città e provincia
  (`ordine_indirizzi_leggi`, griglia 12zg caso 8).

## 3. Commissioni e formula di pagamento (FATTO VERIFICATO)

Parametri attivi in `public.marketplace_config`:

| Classe | Margine obiettivo netto | Fee di riferimento | Finestra di verifica |
|---|---|---|---|
| Privato | 800 bps (8%) | 209 bps + 25 c | 2 giorni |
| Partner | 1500 bps (15%) | 209 bps + 25 c | 2 giorni |

209 bps = costo ponderato del pagamento (75% carte SEE standard, 20% SEE
premium, 5% internazionali, incluso lo 0,25% di Stripe Connect). Il margine e
la fee di riferimento si congelano sull'ordine.

Formula unica (centesimi, P = subtotale venditore, m = margine bps,
p = 209, F = 25, A = accessori):

```text
addebito = ceil( (P·(10000+m) + (F+A)·10000) / (10000−p) )
servizio Vinea = addebito_senza_accessori − P
copertura fee accessori = addebito − (P + servizio) − A
```

Un solo costo fisso per ordine, qualunque sia la quantità.

## 4. Esempi di prezzo (SIMULAZIONE con `private.preventivo_classe`)

Senza imballaggio né logistica. «Netto Vinea» = servizio − (2,09% ·
addebito + 0,25 €), in percentuale del prezzo venditore.

| Classe | Bottiglie × prezzo | Venditore incassa | Servizio Vinea | Acquirente paga | Netto Vinea |
|---|---|---|---|---|---|
| Privato | 1 × 10,00 € | 10,00 € | 1,29 € | 11,29 € | 8,04% |
| Privato | 1 × 25,00 € | 25,00 € | 2,84 € | 27,84 € | 8,03% |
| Privato | 1 × 45,00 € | 45,00 € | 4,90 € | 49,90 € | 8,02% |
| Privato | 1 × 49,00 € | 49,00 € | 5,31 € | 54,31 € | 8,01% |
| Privato | 1 × 100,00 € | 100,00 € | 10,57 € | 110,57 € | 8,01% |
| Privato | 3 × 10,00 € | 30,00 € | 3,35 € | 33,35 € | 8,01% |
| Privato | 2 × 45,00 € | 90,00 € | 9,54 € | 99,54 € | 8,01% |
| Privato | 6 × 45,00 € | 270,00 € | 28,08 € | 298,08 € | 8,00% |
| Privato | 8 × 40,00 € | 320,00 € | 33,24 € | 353,24 € | 8,00% |
| Partner | 1 × 10,00 € | 10,00 € | 2,01 € | 12,01 € | 15,09% |
| Partner | 1 × 25,00 € | 25,00 € | 4,62 € | 29,62 € | 15,00% |
| Partner | 1 × 45,00 € | 45,00 € | 8,11 € | 53,11 € | 15,00% |
| Partner | 1 × 49,00 € | 49,00 € | 8,81 € | 57,81 € | 15,00% |
| Partner | 1 × 100,00 € | 100,00 € | 17,72 € | 117,72 € | 15,01% |
| Partner | 2 × 45,00 € | 90,00 € | 15,97 € | 105,97 € | 15,01% |
| Partner | 6 × 45,00 € | 270,00 € | 47,39 € | 317,39 € | 15,00% |
| Partner | 8 × 40,00 € | 320,00 € | 56,12 € | 376,12 € | 15,00% |

Il «netto Vinea» presuppone che il costo reale del pagamento coincida con la
fee di riferimento: il costo reale per carta non è verificato (§9).

## 5. Copertura della fee di pagamento su imballaggio e logistica

FATTO VERIFICATO: imballaggio dell'annuncio e logistica sono accessori fuori
dalla commissione; la fee di pagamento che generano è coperta con la stessa
formula e mostrata come «Costi di pagamento sulla spedizione/sull'imballaggio».
Esempi della griglia 12ze (privati): 1 × 45 € + imballaggio 4,50 € → copertura
0,09 €, addebito 54,49 €; 3 × 10 € con logistica → 0,17 €, 41,53 €; 8 × 40 €
con logistica 18,22 € → 0,39 €, 371,85 € (Partner 0,38 €, 394,72 €).

SIMULAZIONE (accessori ipotetici dai listini in pre-attivazione del §7):

| Classe | Ordine | Accessori | Copertura | Addebito totale |
|---|---|---|---|---|
| Privato | 1 × 45 € | 7,34 € | 0,15 € | 57,39 € |
| Privato | 1 × 45 € | 9,13 € | 0,19 € | 59,22 € |
| Privato | 1 × 20 € | 7,34 € | 0,16 € | 29,82 € |
| Privato | 1 × 45 € | 15,00 € | 0,32 € | 65,22 € |
| Privato | 6 × 45 € | 10,31 € | 0,22 € | 308,61 € |
| Privato | 6 × 45 € | 14,42 € | 0,31 € | 312,81 € |
| Partner | 1 × 45 € | 7,34 € | 0,16 € | 60,61 € |
| Partner | 6 × 45 € | 10,31 € | 0,22 € | 327,92 € |

Regola di addebito (FATTO VERIFICATO): al punto di ritiro la logistica entra
nel totale solo per più bottiglie; a domicilio sempre, anche per una
bottiglia; con la consegna concordata mai.

## 6. Obiettivi logistici (OBIETTIVO)

| Voce | Valore configurato | Natura |
|---|---|---|
| Obiettivo per transazione | < 10,00 € IVA inclusa con bottiglie sotto 50,00 € | `logistics_obiettivo_transazione_config`, attivo, mai bloccante |
| Soglia storica | 15,00 € IVA inclusa per transazione | `logistics_unit_economics_config`, riferimento |
| Buffer logistico | 0 bps + 0 c | valore neutro, non commerciale |

## 7. Formati, colli, modalità e capability

FATTO VERIFICATO (codice e produzione):

- Formati d'imballaggio: `bottiglia_1`, `bottiglia_2`, `bottiglia_3`,
  `bottiglia_6`, `magnum_1_5l`, `bottiglia_12` (quest'ultimo senza contributo
  né tariffa: ignorato). Un ordine si divide in più colli dal pianificatore.
- Contributi d'imballaggio Beta attivi: 1 bott. 3,19 €; 2 bott. 3,69 €;
  3 bott. 3,79 €; 6 bott. 6,09 €; Magnum 5,09 €.
- Consegna alla rete del venditore: drop-off al punto o ritiro a domicilio
  (privato: indirizzo di ritiro predefinito; Partner: sede commerciale).
- Destinazione dell'acquirente: punto di ritiro (predefinita) o domicilio.
- Capability: `PUDO_TO_PUDO`, `PUDO_TO_HOME`, `HOME_TO_PUDO`, `HOME_TO_HOME`,
  `SEDE_TO_PUDO`, `SEDE_TO_HOME`. Il corriere lo sceglie il routing Vinea.

Listini in **pre-attivazione** (20 righe, «prezzi finali Beta approvati, IVA
inclusa», `logistics_commercial_rate_sources`): solo `PUDO_TO_PUDO` e
`HOME_TO_PUDO`. Non sono tariffe attive (`logistics_shipping_rates` = 0).
SIMULAZIONE del costo per transazione = trasporto + contributo d'imballaggio:

| Formato | Punto → punto (min–max fra fonti) | Domicilio venditore → punto (min–max) |
|---|---|---|
| 1 bottiglia | 4,15–5,13 € + 3,19 € = **7,34–8,32 €** | 5,94–6,21 € + 3,19 € = **9,13–9,40 €** |
| 2 bottiglie | 4,22–6,42 € + 3,69 € = 7,91–10,11 € | 6,21–7,96 € + 3,69 € = 9,90–11,65 € |
| 3 bottiglie | 4,22–6,42 € + 3,79 € = 8,01–10,21 € | 6,21–7,96 € + 3,79 € = 10,00–11,75 € |
| 6 bottiglie | 4,22–6,50 € + 6,09 € = 10,31–12,59 € | 8,33–11,29 € + 6,09 € = 14,42–17,38 € |
| Magnum | 4,22–5,13 € + 5,09 € = 9,31–10,22 € | 6,21–6,30 € + 5,09 € = 11,30–11,39 € |

Lettura: con i listini in pre-attivazione l'obiettivo < 10 € è raggiungibile
per una bottiglia (entrambe le modalità) e, al punto di ritiro, fino a 3
bottiglie con la fonte meno cara; non per 6 bottiglie né per il ritiro a
domicilio da 3 bottiglie in su. Nessun listino a domicilio dell'acquirente
né dalla sede Partner.

## 8. Stato reale della configurazione operativa (FATTO VERIFICATO, produzione)

| Voce | Stato |
|---|---|
| SKU d'imballaggio (`logistics_packaging_skus`) | 0 |
| Servizi logistici | 3 definiti (`standard_beta`), tutti `active=false`, `operational_eligibility=false` |
| Capability dei servizi | 4 (2 `PUDO_TO_PUDO`, 2 `HOME_TO_PUDO`); nessuna verso domicilio né `SEDE_*` |
| Tariffe attive | 0 |
| Reti e punti PUDO | 0 reti, 0 punti |
| Capacità API dei corrieri | 0 (tutte spente); coda operazioni 0 |
| Chiamate API esterne | nessuna nel codice |
| Interruttori | `ordini_multi_unita=false`, `vendita_partner=false`, `PAYMENTS_ENABLED=false` |
| Mercati | solo IT, solo EUR (serrature in migrazione) |

Effetto: oggi la spedizione è fail-closed. Una bottiglia con drop-off al
punto e la consegna concordata seguono il percorso storico fino al gate dei
pagamenti spenti; più bottiglie,
domicilio, ritiro senza indirizzo e prodotti Partner sono chiusi con il
motivo. I pagamenti rispondono 503 «Pagamenti non attivi».

## 9. Costi, tariffe e contratti non verificati

- Contratti con i corrieri (tariffe, limiti di peso e misura, vetro,
  responsabilità, ritiro a domicilio, consegna a domicilio, ritiro in sede).
- Costo reale del pagamento per carta (209 bps + 25 c è un riferimento).
- Costo d'acquisto reale degli imballaggi (i contributi sono voci di
  transazione, non costi del fornitore).
- Costo di eventuali API dei corrieri, etichette e tracking.
- Nessun costo, ricavo o fatturato reale: zero ordini in produzione.

## 10. Requisiti differiti e dipendenze

- Attivazione dei pagamenti reali (Stripe, webhook firmati in produzione).
- Configurazione operativa logistica dalle porte admin; adattatori reali dei
  corrieri (prenotazione ritiro, etichette, tracking) e relative Edge Function.
- Accensione di `ordini_multi_unita` e `vendita_partner`: autorizzazione
  esplicita del titolare.
- Vendite professionali: valutazione degli obblighi del Digital Services Act
  per venditori professionali.
- Messaggistica diretta Partner senza annuncio, traduzioni, mercati esteri,
  IVA/accise/dogane estere, valute diverse da EUR.
- Peso volumetrico, cartone da 12, prove e tracking per collo, deduzione del
  ritiro a domicilio trattenuta sul pagamento al venditore (WP7).
- Fase 13 (cutover da `frontend/` + `backend/`): separata, non avviata.
- Dipendenze legali/operative non valutate in questo perimetro: conformità
  della vendita a distanza di alcolici fra privati e da Partner (età,
  eventuali licenze), informativa privacy e termini per gli indirizzi,
  contratti di trasporto del vetro.
