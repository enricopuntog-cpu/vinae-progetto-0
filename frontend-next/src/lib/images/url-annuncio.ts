/**
 * Ricomposizione dell'URL pubblico di una fotografia di annuncio.
 *
 * Il corpo di queste tre dichiarazioni viveva dentro `@/services/listing-service`
 * ed e stato spostato qui senza cambiarne una riga di comportamento:
 * `listing-service` le riesporta, quindi ogni importazione esistente continua a
 * funzionare. Lo spostamento serve a un solo scopo: il fascicolo di
 * contestazione (moderazione) deve risolvere le stesse fotografie di annuncio, e
 * l'alternativa era ricomporre l'URL a mano in un secondo punto — cioe
 * duplicare la validazione e aprire la porta a una divergenza silenziosa fra i
 * due lettori. La regola resta una sola, scritta una volta sola.
 *
 * Il modulo non importa nulla: un adapter di moderazione puo prenderlo senza
 * trascinarsi dietro il catalogo pubblico e i suoi dati di prova.
 */

/**
 * Immagine mostrata quando un annuncio non ne ha nessuna.
 *
 * Esportata perche la Cantina pubblica del profilo ha lo stesso identico
 * problema e deve dargli la stessa identica risposta: le fotografie caricate in
 * Cantina stanno nel bucket privato `cantina` e non sono pubblicabili, quindi
 * una bottiglia senza annuncio attivo mostra questo segnaposto. Una seconda
 * costante con lo stesso percorso sarebbe una copia da tenere allineata.
 */
export const IMMAGINE_ASSENTE = "/images/vinea-bottle-1.jpg";

/** Bucket delle fotografie caricate dai venditori (Fase 6b). */
export const BUCKET_ANNUNCI = "annunci";

/**
 * `listings.immagini` contiene due specie diverse di stringa, e si distinguono
 * dalla prima lettera:
 *
 * - `/images/…` è un asset statico servito da frontend-next/public — sono le
 *   illustrazioni usate dai dati di prova della 6a, e restano dove sono;
 * - `<uid>/<uuid>.jpg` è un oggetto dentro il bucket `annunci`, caricato da un
 *   venditore in Fase 6b.
 *
 * Nel database si salva il percorso e non l'URL completo: l'URL contiene
 * l'indirizzo del progetto Supabase, e inciderlo in ogni riga legherebbe i
 * dati a un progetto specifico. L'URL si ricompone qui, dove l'indirizzo è
 * già una variabile d'ambiente.
 *
 * Vale per il bucket PUBBLICO `annunci` e per nessun altro. Le prove di una
 * contestazione stanno nel bucket privato `dispute-evidence` e si leggono solo
 * con un URL firmato a scadenza: passarle di qui produrrebbe un indirizzo
 * pubblico che il bucket rifiuta, che e il modo silenzioso di rompere una
 * riservatezza.
 */
export function urlImmagine(percorso: string): string {
  if (percorso.startsWith("/")) return percorso;

  const base = process.env.NEXT_PUBLIC_SUPABASE_URL;
  if (!base) return IMMAGINE_ASSENTE;

  return `${base}/storage/v1/object/public/${BUCKET_ANNUNCI}/${percorso}`;
}
