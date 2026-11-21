# Registro delle fonti — Vinea Wine Database

Registro leggero delle fonti dati del catalogo vini. Non duplica
`docs/WINE_CATALOG_ARCHITECTURE.md` (modello) né `docs/WI_001A_WINE_CATALOG_FOUNDATION.md`
(rapporto). Ogni fonte nuova va registrata qui **prima** di qualunque import.

## LIVEX-LWIN7

| Campo | Valore |
|---|---|
| ID | `LIVEX-LWIN7` |
| Fonte | Liv-ex, database LWIN (Liv-ex Wine Identification Number), identificatori a 7 cifre (vino base) |
| Titolare | Liv-ex |
| URL fonte | https://www.liv-ex.com/lwin/ |
| Licenza | Creative Commons Attribution 4.0 International (CC BY 4.0) |
| URL licenza Liv-ex | https://www.liv-ex.com/lwin-creative-commons-licence/ |
| URL licenza ufficiale | https://creativecommons.org/licenses/by/4.0/ |
| Verifica | 17 novembre 2026, lettura delle pagine Liv-ex indicate. La pagina Liv-ex rinvia al testo CC BY 4.0 e dichiara il database libero da scaricare. Il testo CC completo non è stato riletto riga per riga: gli obblighi sotto sono quelli standard di CC BY 4.0. Il file reale è stato fornito localmente dal titolare |
| Stato | Licenza verificata. Fonte registrata come riga seme nella migration WI-001B (`catalog.sources`, codice `LIVEX-LWIN7`, `authorization_status = authorized`) — **al 21 novembre 2026 lo schema `catalog` di staging (WI-001B) è distribuito in Production, ma `catalog.source_records` è vuota: nessun import LWIN in Production** (da autorizzare a parte, dopo il gate disco del runbook). Import completo del file reale provato solo su database locale (212.894 record, V01–V09 OK); su Preview cloud fallito per disco esaurito. Le 4 migration del catalogo canonico sono nella PR #310, non ancora distribuite |
| Copertura | 212.894 record (Live 206.167, Combined 6.221, Deleted 506); 190.953 in ambito vino, 21.941 altri; 101 paesi, 370 regioni, 1.577 sottoregioni |
| Manifest | `docs/wine-intelligence/IMPORT_MANIFEST.json` |

### Obblighi di attribuzione (CC BY 4.0)

1. **Credito**: indicare Liv-ex come fonte dei dati LWIN.
2. **Link alla licenza**: https://creativecommons.org/licenses/by/4.0/
3. **Modifiche**: indicare che i dati sono stati modificati/normalizzati da Vinea.
4. Nessuna suggestione di approvazione da parte di Liv-ex.
5. Nessuna misura legale o tecnica che impedisca ad altri ciò che la licenza consente.

Testo proposto per le future schede pubbliche (da inserire in WI-001B o oltre, **non** in UI ora):
«Identificativo e dati di base: LWIN © Liv-ex, licenza CC BY 4.0
(creativecommons.org/licenses/by/4.0/). Dati normalizzati e integrati da Vinea.»
Il credito compare su ogni scheda che mostra campi derivati da LWIN, oppure in una nota
raggiungibile da ogni scheda; il registro delle provenienze per campo
(`attribute claims`, architettura §9) permette di sapere quali campi sono LWIN.

### Perimetro della licenza

- La licenza pubblicata da Liv-ex riguarda **il database LWIN**. La pagina non nomina immagini,
  prezzi o API: perciò **non va estesa** a fotografie, prezzi, dati di provider terzi o API separate.
  Ognuno richiede la propria verifica e il proprio record in questo registro.
- Le immagini seguono il contratto `catalog.media` (licenza e autore per immagine). Nessuna immagine
  è stata scaricata.
- I prezzi di mercato (es. Liv-ex Market Data) sono prodotti distinti: non coperti.
- Un'integrazione API Liv-ex non è valutata né autorizzata.

### Limitazioni

- La pagina non fissa una formula di attribuzione; quella sopra è una proposta di Vinea.
- Il dataset non ha licenza di marchio: «LWIN» e «Liv-ex» restano nomi del titolare.
- Qualità: 98,8% dei record Live in ambito vino senza `FIRST_VINTAGE`; 12.582 record senza regione;
  6 righe con `TYPE` anomalo; 73 gruppi di possibili duplicati non fusi. Dettagli in
  `docs/WI_001A_WINE_CATALOG_FOUNDATION.md`.
- I Combined non sono ancora confrontati con lo snapshot precedente (debito WI-001B).

## Fonti da valutare (non acquisite, nessuna ammissione)

Nessun contatto, scaricamento o import. Da valutare in task dedicati, ciascuno con verifica di licenza:
dati aperti sulle denominazioni (es. registri UE/eAmbrosia), Wikidata/Wikimedia Commons (CC0/CC BY-SA,
per territori e immagini), schede dei produttori con liberatoria, Open Food Facts per le etichette.
