# Fase 6d-2a — decisioni residue

## Provenienza del catalogo

- `wines.provenienza` distingue `staff` da `utente`; il client non può
  modificarla.
- Le otto righe del seed 6a sono `staff`. Le altre righe preesistenti sono
  `utente`; `creato_da` viene ricostruito dalla prima unità fisica quando il
  dato è verificabile.
- La tripletta produttore, nome e annata resta unica. Una descrizione utente
  che coincide con un vino curato riusa la riga `staff`; una riga utente non
  diventa curata implicitamente.
- La lettura diretta di `wines` espone il catalogo `staff` e, a un autenticato,
  le righe utente collegate alle proprie bottiglie. Gli annunci pubblici
  continuano a passare dalla vista a colonne chiuse.

## Tre percorsi distinti

- Aggiunta privata e aggiunta pubblica usano
  `cellar_bottiglia_aggiungi`: creano vino utente se necessario e una sola
  `bottle_unit`, senza creare annunci.
- La vendita usa `listing_crea_da_bottiglia` e richiede una `bottle_unit`
  esistente, chiusa e posseduta da chi chiama. La vecchia via che coniava vino,
  bottiglia e annuncio non è più eseguibile da ruoli client.
- Le foto della Cantina vivono nel bucket privato `cantina`; le foto di un
  annuncio restano nel bucket pubblico `annunci`.

## Inizializzazione e home

- `cellar_ambiente_crea` inserisce ambiente e modulo iniziale nella stessa
  transazione; gli insert diretti dei due oggetti non sono più una porta
  client.
- La home usa soltanto bottiglie e vini caricati dal `CellarService`; nessun
  riepilogo Cantina usa il catalogo mock.

Ordini, proposte, pagamenti, trasferimento di proprietà e moderazione della
provenienza restano fuori dalla fase.
