/**
 * Il percorso che porta ad aprire una bottiglia, deciso prima di chiamare la RPC.
 *
 * Fino a oggi premere «apri» su una bottiglia in vendita significava ricevere in
 * faccia l'eccezione di `public.bottiglia_apri`, senza che nessuno avesse
 * spiegato prima cosa stesse per succedere né offerto una via d'uscita. Questo
 * modulo non aggiunge un controllo di sicurezza — quello sta nella funzione SQL,
 * che verifica da sé e resta l'unica autorità — ma decide **quale conversazione**
 * avere con chi preme, e in particolare quando una via d'uscita esiste davvero.
 *
 * ## I due elenchi non coincidono, ed è il fatto che governa questo file
 *
 * `bottiglia_apri` rifiuta se la bottiglia ha un annuncio in **cinque** stati
 * (`bozza`, `in_revisione`, `modifiche_richieste`, `attivo`, `riservato`), letti
 * dal corpo vivo della funzione sul progetto reale il 18 agosto 2026 e non dedotti
 * dal file di migrazione. Ma `listing_sospendi` accetta di partire da **uno solo**:
 * `if v_stato <> 'attivo' then raise ... 'Si può sospendere solo un annuncio
 * attivo.'`. E non c'è una seconda uscita: `listing_scadi`, l'unico altro comando
 * che il venditore può eseguire su un annuncio, pretende `attivo` **e per giunta**
 * una scadenza già passata.
 *
 * Quindi per quattro dei cinque stati bloccanti **non esiste alcun comando** che
 * il venditore possa usare per liberare la bottiglia. Offrire lì il dialogo
 * «Confermi la rimozione dell'annuncio?» sarebbe peggio di com'è oggi: oggi si
 * riceve un errore onesto, mentre un pulsante che promette una rimozione e poi
 * fallisce spende la fiducia di chi l'ha premuto. Per questo il percorso
 * `bloccato` esiste e non ha un pulsante di conferma.
 */

import type { ListingStato } from "@/services/listing-service";

/**
 * Gli stati di un annuncio che impediscono di aprire la bottiglia.
 *
 * È la copia dell'elenco dentro `public.bottiglia_apri`. Vive qui perché la UI
 * deve sapere *prima* se parlare di rimozione, di attesa o di niente; la
 * decisione vera resta della funzione SQL, che rifiuta comunque. Se l'elenco
 * cambia nel database e non qui, un test protesta.
 */
export const STATI_BLOCCANTI_APERTURA: readonly ListingStato[] = [
  "bozza",
  "in_revisione",
  "modifiche_richieste",
  "attivo",
  "riservato",
];

/**
 * L'annuncio che occupa una bottiglia, ridotto a ciò che serve per decidere.
 *
 * `stato` è una stringa e non `ListingStato` di proposito: arriva da PostgREST,
 * cioè da fuori, e stringerlo qui sarebbe una promessa che questo modulo non è
 * in grado di mantenere. La verifica di appartenenza la fa `percorsoApertura`,
 * ed è quella a decidere — un valore che non riconosce cade su `diretto`, dove
 * `bottiglia_apri` resta comunque l'autorità che rifiuta.
 */
export type AnnuncioDellaBottiglia = {
  id: string;
  stato: string;
};

/**
 * Cosa succede premendo «apri».
 *
 * - `diretto`: nessun annuncio in mezzo. Resta comunque una conferma esplicita,
 *   perché aprire una bottiglia non si annulla.
 * - `rimuovi-poi-apri`: c'è un annuncio `attivo` e **una via d'uscita reale**.
 *   Due conferme distinte, mai una sola che faccia due cose.
 * - `bloccato`: c'è un annuncio in uno degli altri quattro stati e nessun
 *   comando per toglierlo. Si dice, non si finge.
 */
export type PercorsoApertura =
  | { tipo: "diretto" }
  | { tipo: "rimuovi-poi-apri"; listingId: string; stato: string }
  | { tipo: "bloccato"; stato: string; spiegazione: string };

/**
 * Perché la bottiglia non si può aprire, per ognuno dei quattro stati senza
 * uscita. Ogni riga dice **cosa** blocca e **cosa aspettarsi**, e nessuna
 * nomina un comando che non esiste: non c'è modo di eliminare una bozza, né di
 * ritirare un annuncio dalla revisione.
 */
const SPIEGAZIONE_BLOCCO: Record<string, string> = {
  bozza:
    "Questa bottiglia è impegnata in un annuncio ancora in bozza. Finché la bozza esiste la bottiglia resta legata, e oggi non c'è un comando per eliminarla: si libera pubblicando l'annuncio e poi rimuovendolo dalla vendita.",
  in_revisione:
    "L'annuncio di questa bottiglia è in revisione. Finché la moderazione non risponde non si può né rimuoverlo né aprire la bottiglia: l'attesa è l'unica cosa da fare.",
  modifiche_richieste:
    "La moderazione ha chiesto modifiche all'annuncio di questa bottiglia. Sistemalo e pubblicalo: da lì potrai rimuoverlo dalla vendita e aprire la bottiglia.",
  riservato:
    "Un compratore ha riservato questa bottiglia e c'è un ordine in corso. Non si può aprirla né togliere l'annuncio finché l'ordine non si conclude — la bottiglia non è più solo tua da decidere.",
};

/**
 * Decide il percorso a partire dall'annuncio che occupa la bottiglia.
 *
 * `null` e gli stati terminali (`sospeso`, `venduto`, `scaduto`, `rifiutato`)
 * cadono entrambi su `diretto`: sono esattamente i casi in cui `bottiglia_apri`
 * non trova nulla che la blocchi, perché il suo `exists` filtra sui cinque
 * stati qui sopra e non su «esiste un annuncio».
 */
export function percorsoApertura(
  annuncio: AnnuncioDellaBottiglia | null | undefined,
): PercorsoApertura {
  if (!annuncio || !(STATI_BLOCCANTI_APERTURA as readonly string[]).includes(annuncio.stato)) {
    return { tipo: "diretto" };
  }

  if (annuncio.stato === "attivo") {
    return { tipo: "rimuovi-poi-apri", listingId: annuncio.id, stato: annuncio.stato };
  }

  return {
    tipo: "bloccato",
    stato: annuncio.stato,
    spiegazione: SPIEGAZIONE_BLOCCO[annuncio.stato] ?? "",
  };
}

/**
 * La data da mostrare accanto a «Bottiglia degustata il …».
 *
 * Oggi non esiste una data di apertura reale: `bottle_units` ha
 * `apertura_pianificata`, che è una **data programmata** scrivibile dal client e
 * spesso nulla, e `updated_at`, che si muove a ogni modifica e quindi non
 * testimonia l'apertura. Finché la colonna `degustazione_at` proposta in
 * `supabase/queries/05_PROPOSTA_NON_ESEGUIRE_DEGUSTAZIONE.sql` non è autorizzata,
 * questa funzione dice la verità invece di inventare un giorno: se la data
 * programmata non c'è, non se ne mostra nessuna.
 */
export function dataDegustazione(input: {
  degustazioneAt?: string | null;
  aperturaPianificata?: string | null;
}): { testo: string; certa: boolean } {
  if (input.degustazioneAt) {
    return { testo: formattaData(input.degustazioneAt), certa: true };
  }
  if (input.aperturaPianificata) {
    return { testo: formattaData(input.aperturaPianificata), certa: false };
  }
  return { testo: "", certa: false };
}

function formattaData(valore: string): string {
  const data = new Date(valore);
  if (Number.isNaN(data.getTime())) return valore;
  return data.toLocaleDateString("it-IT", {
    day: "numeric",
    month: "long",
    year: "numeric",
  });
}
