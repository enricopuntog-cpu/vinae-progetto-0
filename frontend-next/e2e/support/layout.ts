import { expect } from "./test";
import type { Locator } from "@playwright/test";

/**
 * Aspetta che un bersaglio sia FERMO prima di premerlo. Le schede dei vini usano `content-visibility: auto`
 * (`.cv-card`) con un'altezza stimata: quando una scheda entra in vista prende quella vera e ciò che sta sotto si
 * sposta di circa 43 px. Dopo uno scorrimento automatico WebKit lo applica un istante più tardi, fra `pointerdown` e
 * `pointerup`: il `click` finisce sul contenitore (o la pressione e il rilascio cadono su due pulsanti diversi) e il
 * comando non lo riceve. Una persona tocca il layout già fermo: qui si aspetta la stessa cosa, e il clic resta vero.
 * Da usare per i comandi sotto una scheda vino, subito dopo un caricamento o uno scorrimento.
 */
export async function fermo(bersaglio: Locator): Promise<Locator> {
  let precedente = "";
  await expect
    .poll(
      async () => {
        await bersaglio.scrollIntoViewIfNeeded();
        const attuale = JSON.stringify(await bersaglio.boundingBox());
        const uguale = attuale === precedente;
        precedente = attuale;
        return uguale;
      },
      { intervals: [250], timeout: 10_000 },
    )
    .toBe(true);
  return bersaglio;
}
