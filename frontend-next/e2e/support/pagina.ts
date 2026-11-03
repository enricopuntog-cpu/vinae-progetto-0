import type { Page } from "@playwright/test";

/**
 * Le pagine client mostrano «Carico…», «Caricamento…» o «Verifica dell'accesso…»
 * finché sessione e dati non arrivano. Un'asserzione di assenza ("non c'è la
 * sezione Accessori") prima di questo momento sarebbe un falso verde: si
 * attende sempre che il caricamento sia finito.
 */
export const attendiCaricamento = async (page: Page): Promise<void> => {
  await page.waitForFunction(() => !/Carico |Caricamento|Verifica dell|Verifica della/.test(document.body.innerText), undefined, {
    timeout: 20_000,
  });
};

/** Nessuna barra di scorrimento orizzontale: il contenuto sta nella larghezza del viewport. */
export const senzaScorrimentoOrizzontale = (page: Page): Promise<boolean> =>
  page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);

/**
 * Controlli minimi di accessibilità sul DOM (nessuna dipendenza aggiuntiva).
 * Contano solo gli elementi esposti: non quelli `hidden`, sotto `aria-hidden` o
 * non resi (`display: none`, come il campo file nascosto o la copia nativa dei
 * selettori Radix), che un lettore di schermo non incontra.
 */
export const problemiAccessibilita = (page: Page): Promise<string[]> =>
  page.evaluate(() => {
    const problemi: string[] = [];
    const esposto = (e: Element): boolean =>
      !e.closest("[hidden], [aria-hidden='true']") && (e as HTMLElement).checkVisibility?.() !== false;
    const nomeAccessibile = (e: Element): string =>
      (
        e.getAttribute("aria-label") ||
        e.getAttribute("aria-labelledby") ||
        e.textContent ||
        e.getAttribute("title") ||
        // un `<label for>` dà il nome anche a un pulsante (interruttori Radix)
        ((e as HTMLButtonElement).labels?.length ? "etichetta" : "")
      ).trim();
    const titoli = [...document.querySelectorAll("h1")].filter(esposto).length;
    if (titoli !== 1) problemi.push(`h1 presenti: ${titoli} (atteso 1)`);
    if (!document.documentElement.lang) problemi.push("lang mancante su <html>");
    for (const img of document.querySelectorAll("img")) {
      if (!img.hasAttribute("alt")) problemi.push(`img senza alt: ${img.getAttribute("src")?.slice(0, 60)}`);
    }
    for (const e of document.querySelectorAll("button, a[href]")) {
      if (!esposto(e)) continue;
      if (!nomeAccessibile(e) && !e.querySelector("img[alt]:not([alt=''])")) problemi.push(`<${e.tagName.toLowerCase()}> senza nome accessibile`);
    }
    for (const campo of document.querySelectorAll("input:not([type=hidden]), textarea, select")) {
      if (!esposto(campo)) continue;
      const id = campo.getAttribute("id");
      const etichettato =
        campo.getAttribute("aria-label") ||
        campo.getAttribute("aria-labelledby") ||
        (id && document.querySelector(`label[for="${CSS.escape(id)}"]`)) ||
        campo.closest("label");
      if (!etichettato) problemi.push(`campo senza etichetta: ${campo.tagName.toLowerCase()}#${id ?? ""}`);
    }
    return problemi;
  });
