import { contestoAutenticato, opzioniDelProgetto } from "./browser";
import { attendiCaricamento } from "./pagina";
import { expect } from "./test";
import type { Browser, Page, TestInfo } from "@playwright/test";

/**
 * Passi comuni del wizard `/vendi` per le prove della ricerca dei vini (WI-006A, WI-007): dal login al passo
 * Identificazione (nuova bottiglia, senza scrivere nulla) e la ricerca dal pulsante, sugli stessi campi del wizard.
 */

export type RuoloRicerca = "venditore" | "altro";

/** Dal wizard fino al passo Identificazione (nuova bottiglia), senza scrivere nulla. */
export async function apriIdentificazione(
  browser: Browser,
  ruolo: RuoloRicerca,
  info: TestInfo,
  diagnostica: { osserva: (p: Page, n: string) => void },
) {
  const contesto = await contestoAutenticato(browser, ruolo, opzioniDelProgetto(info));
  const page = await contesto.newPage();
  diagnostica.osserva(page, ruolo);
  const richieste: { metodo: string; url: string }[] = [];
  page.on("request", (r) => richieste.push({ metodo: r.method(), url: r.url() }));
  await page.goto("/vendi");
  await attendiCaricamento(page);
  await page.getByRole("button", { name: /Aggiungi alla cantina privata/ }).click();
  const continua = page.getByRole("button", { name: /Continua/ });
  await continua.click();
  await continua.click();
  await expect(page.getByRole("heading", { name: "Identificazione", exact: true })).toBeVisible();
  return { contesto, page, richieste };
}

/** Compila produttore e nome e preme «Cerca»: la ricerca parte solo da questo gesto. */
export async function cerca(page: Page, produttore: string, nome: string) {
  await page.getByLabel("Produttore", { exact: true }).fill(produttore);
  await page.getByLabel("Nome / Etichetta", { exact: true }).fill(nome);
  await page.getByTestId("ricerca-manuale-cerca-btn").click();
}
