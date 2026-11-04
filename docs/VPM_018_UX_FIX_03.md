# VPM-018-UX-FIX-03 — Coerenza UX residua (4 novembre 2026)

Correzioni piccole e indipendenti del backlog di `docs/VPM_018_UX_A11Y_01.md` § 4. Ogni difetto è
stato riprodotto nel browser sul codice originale, con la spec `e2e/ux-fix-03.e2e.ts` rossa prima
della correzione. Nessuna migrazione, flag, Stripe o Production toccati; i calcoli della Cantina
non cambiano.

## 1. Esiti

| Voce | Evidenza prima | Correzione | Esito |
|---|---|---|---|
| Requisiti in `completa-profilo` | sotto «Conferma password»: 88 px dal campo a 375 px, sulla colonna opposta da `sm` | requisiti subito sotto il campo e conferma dopo; nessun `aria-describedby` a vuoto se la password è già impostata | **CHIUSO** |
| Data di nascita in `/registrati` | sola nella metà sinistra da `sm`: 311 px meno della password | riga intera | **CHIUSO** |
| Copy performance parziale | «su dati parziali» non diceva cosa manca | «mancano costi, riferimenti o incassi di alcune bottiglie» nella voce della tabella; pillola breve invariata | **CHIUSO** (solo copy) |
| UX-B4 barra del wizard | a 375 px «Indietro» solo su una riga, 44 px sopra le altre azioni | griglia a 375 px, azione principale su riga propria; riga unica da `sm` | **CHIUSO** |
| UX-B5 404 annidati | titolo nudo, un solo link | annuncio, checkout, profilo e Club su `NotFoundState` con testo e ritorno propri; lo stato HTTP resta 404 | **CHIUSO** |
| UX-B6 stati vuoti dei messaggi | `h1` alto 1 px, solo per screen reader | stessa intestazione visibile in ogni stato | **CHIUSO** |
| UX-B7 segnaposto abbinamento | misura a 375 px: 400 px di testo in 289 px | «Cosa prepari? es. brasato, risotto»: 251 px | **CHIUSO** |
| TEST-B3 etichetta del selettore Radix | mai provata | caso nuovo: l'etichetta apre il selettore | **NESSUN DIFETTO**, ora coperto |
| UX-B3 contrasto dei testi piccoli | § 2 | nessuna | **DECISIONE DEL TITOLARE** |

## 2. UX-B3: misura e alternative

Misura reale nel browser (build di produzione, colori calcolati dagli elementi in pagina): `text-salvia` è
`rgb(116, 128, 108)`, con rapporto **4,16:1 su card bianca** (testo da 11 e 12 px) e **3,76:1 su crema**
(12 px, semibold), sotto la soglia WCAG AA di 4,5:1 per il testo piccolo. Lettura del sorgente: circa 30
usi con testo piccolo. Il colore da solo non basta come segnale di stato, e non è usato come tale in questi
casi: il difetto riguarda la leggibilità delle etichette.

| Alternativa | Colore | Crema / card / `secondary` | Effetto |
|---|---|---|---|
| **A, consigliata** | `--salvia-scuro` `#4a5344`, già nel design system, sui soli testi sotto 18 px | 7,27 / 8,04 / 6,65 | Nessun colore nuovo. Etichette visibilmente più scure, salvia resta per icone e bordi |
| B | Nuovo token intermedio `#626d5b` | 4,92 / 5,44 / 4,51 | Più vicino alla salvia attuale, ma è un colore nuovo della palette e passa appena |
| C | Nessuna modifica | 3,76 / 4,16 / 3,44 | Sotto WCAG AA (4,5:1) per il testo piccolo |

Non applicata: riguarda circa 30 etichette in tutta l'app e il colore è una decisione di marca.
A scelta fatta è una modifica meccanica, S.

## 3. Prove

Stack dedicato `vinea_e2e`, build di produzione, porta 3187 (la 3100 era occupata da un altro server,
non toccato).

| Prova | Esito |
|---|---|
| `ux-fix-03` sul codice originale | 22 rossi su 27: 18 per i difetti reali, 4 per errori della spec poi corretti (selettore su un percorso sbagliato, campo di ricerca doppio a 375 px) |
| `ux-fix-03`, `pagine-di-errore`, `ux-a11y`, `ux-fix-02`, `marketplace-vino`, `messaggi-critici` sul codice finale, tre progetti | **81/81**, pulizia `0 0 0 0 0 0 0 0 0 false false false false` |
| Suite completa, prima dei ritocchi dell'audit UX | 235/236: unico rosso WebKit `accessori-spenti`, «access control checks» su prefetch RSC annullati, classe già nota, spec non toccata, non silenziato |
| Unit, typecheck, lint | 3458/3458, nessun errore, 12 warning `<img>` già noti |
| Screenshot prima e dopo | letti a vista: barra, ultimo passo, `completa-profilo`, 404, messaggi. Artefatti locali non versionati |

## 4. Revisione

`vinea-ux-auditor` sul codice non ancora committato ha trovato due difetti introdotti da questa stessa
modifica, corretti prima della PR: l'etichetta lunga «Aggiungi alla cantina pubblica» usciva dal pulsante
a 375 px (ora caso E2E dedicato) e la nota lunga avrebbe rotto la pillola in testa alla card (ora la
pillola usa una nota breve). Accettato senza modifica: «Esplora la ricerca» nel 404 di root, testo già
presente e verificato da `pagine-di-errore`.

## 5. Limiti

- La nota della performance con dati parziali è provata da test unitari, non vista nel browser: lo stato
  richiede un riferimento di valore e non è predisposto dalle fixture.
- Il 404 del Club è coperto solo a livello di contratto: i Club sono spenti nella build di prova.
- Lettura reale con screen reader NON VERIFICATA.
