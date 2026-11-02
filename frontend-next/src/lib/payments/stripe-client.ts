// `/pure`: l import semplice inserirebbe lo script di Stripe in ogni pagina che importa il modulo.
import { loadStripe, type Stripe } from "@stripe/stripe-js/pure";

/**
 * Stripe.js nel browser (solo chiave publishable). Una sola istanza per chiave:
 * `loadStripe` inserisce lo script ufficiale e va chiamato fuori dal render.
 * Il segreto non passa mai di qui; l'SDK server-side resta nella Edge Function.
 */
const istanze = new Map<string, Promise<Stripe | null>>();

export function caricaStripeBrowser(chiavePublishable: string): Promise<Stripe | null> {
  let p = istanze.get(chiavePublishable);
  if (!p) {
    // Un caricamento fallito non resta in cache: il tentativo successivo riprova.
    p = loadStripe(chiavePublishable).catch((e: unknown) => {
      istanze.delete(chiavePublishable);
      throw e;
    });
    istanze.set(chiavePublishable, p);
  }
  return p;
}
