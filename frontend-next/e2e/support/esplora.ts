import type { Page, TestInfo } from "@playwright/test";

export interface DescrizionePagina {
  url: string;
  testo: string;
  controlli: string[];
  campi: string[];
  link: string[];
}

/**
 * Esplorazione: descrive una pagina (testo principale, controlli, campi, link) e
 * ne salva lo screenshot. Serve a scoprire come è fatta una schermata prima di
 * scrivere un caso, oppure a cercare problemi non previsti dai casi esistenti.
 * Si usa da uno spec TEMPORANEO `e2e/esplora*.e2e.ts`, che `.gitignore` esclude:
 * non finisce mai in un commit.
 */
export const descriviPagina = async (page: Page, nome: string, info?: TestInfo): Promise<DescrizionePagina> => {
  await page
    .waitForFunction(() => !/Carico |Caricamento|Verifica dell|Verifica della/.test(document.body.innerText), undefined, {
      timeout: 20_000,
    })
    .catch(() => undefined);
  const descrizione = await page.evaluate((): DescrizionePagina => {
    const nomeDi = (e: Element) => (e.getAttribute("aria-label") || e.textContent || "").trim().replace(/\s+/g, " ").slice(0, 80);
    return {
      url: location.pathname + location.search,
      testo: (document.querySelector("main") ?? document.body).innerText.replace(/\n+/g, " | ").slice(0, 2500),
      controlli: [...document.querySelectorAll("button, [role=tab], [role=switch], [role=combobox]")].map(nomeDi).filter(Boolean),
      campi: [...document.querySelectorAll("input, textarea, select")].map(
        (c) => `${c.tagName.toLowerCase()}:${(c as HTMLInputElement).type ?? ""}#${c.id} ${c.getAttribute("aria-label") ?? ""}`.trim(),
      ),
      link: [...document.querySelectorAll("a[href]")].map((a) => `${nomeDi(a)} -> ${a.getAttribute("href")}`),
    };
  });
  const immagine = await page.screenshot({ fullPage: true });
  if (info) await info.attach(`esplora-${nome}.png`, { body: immagine, contentType: "image/png" });
  console.log(`\n===== ${nome} =====\n${JSON.stringify(descrizione, null, 1)}`);
  return descrizione;
};
