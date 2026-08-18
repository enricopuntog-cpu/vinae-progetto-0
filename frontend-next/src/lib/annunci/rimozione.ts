/**
 * Le parole con cui si avverte che togliere un annuncio dalla vendita non si
 * disfa, in un posto solo.
 *
 * Da oggi i punti da cui parte `listing_sospendi` sono due — il pannello del
 * venditore sulla pagina dell'annuncio (Gruppo 1) e il percorso di apertura di
 * una bottiglia in Cantina — e la stessa azione irreversibile raccontata con due
 * frasi diverse è il modo più semplice per far credere che siano due azioni
 * diverse. Un test pretende che entrambi i punti importino questa costante
 * invece di riscriverla: stessa forma di `etichette-ia.ts`, e per la stessa
 * ragione, cioè che il testo cambi in un posto quando cambia.
 *
 * Il fatto che l'avviso riporta è misurato, non prudenziale: `sospeso` è
 * terminale. Non è coperto dall'indice `listings_un_solo_annuncio_non_terminale`,
 * `listing_pubblica` riparte solo da `bozza` e `modifiche_richieste`, e nessuna
 * funzione riporta un annuncio ad `attivo` partendo da `sospeso`.
 */
export const AVVISO_RIMOZIONE_IRREVERSIBILE =
  "Non potrai rimettere in vendita questo annuncio: per venderla di nuovo dovrai crearne uno nuovo dalla Cantina.";

/**
 * Cosa resta e cosa sparisce, detto prima di premere.
 *
 * Vale per entrambi i punti di partenza: i dati non si perdono, cambia solo chi
 * li vede. È la parte che toglie l'ansia, mentre la costante qui sopra è quella
 * che la mette dove serve.
 */
export const EFFETTO_RIMOZIONE =
  "Sparisce dalla ricerca e dalle schede di chi compra. Prezzo, fotografie e descrizione non vengono cancellati e restano visibili a te. La bottiglia torna libera in Cantina.";
