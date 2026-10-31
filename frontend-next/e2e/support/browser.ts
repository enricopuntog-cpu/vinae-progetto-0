import type { Browser, BrowserContext, BrowserContextOptions, TestInfo } from "@playwright/test";
import { createServerClient } from "@supabase/ssr";
import { EMAIL, passwordFixture, type Ruolo } from "./api";
import { risolviBersaglio, URL_APP } from "./stack";

interface CookieDaImpostare {
  name: string;
  value: string;
}

/**
 * Contesto di browser già autenticato come uno degli utenti della fixture.
 *
 * L'accesso usa la stessa libreria del frontend (`@supabase/ssr`) in Node: i
 * cookie di sessione hanno nome, formato e suddivisione in blocchi reali, e la
 * password non viene mai digitata nel browser, quindi non può finire in una
 * trace, in un video o in uno screenshot. Un contesto per utente: sessioni
 * isolate fra loro e dal resto della corsa.
 */
export const contestoAutenticato = async (
  browser: Browser,
  ruolo: Ruolo,
  opzioni: BrowserContextOptions = {},
): Promise<BrowserContext> => {
  const { apiUrl, anonKey } = risolviBersaglio();
  const catturati: CookieDaImpostare[] = [];
  const client = createServerClient(apiUrl, anonKey, {
    cookies: {
      getAll: () => [],
      setAll: (cookies) => {
        for (const { name, value } of cookies) catturati.push({ name, value });
      },
    },
  });
  const { error } = await client.auth.signInWithPassword({ email: EMAIL[ruolo], password: passwordFixture() });
  if (error || catturati.length === 0) throw new Error(`Accesso non riuscito per ${ruolo}.`);

  const contesto = await browser.newContext(opzioni);
  const host = new URL(URL_APP).hostname;
  await contesto.addCookies(
    catturati.map(({ name, value }) => ({ name, value, domain: host, path: "/", httpOnly: false, secure: false, sameSite: "Lax" as const })),
  );
  return contesto;
};

/** Opzioni del contesto del progetto corrente (viewport, user agent, locale). */
export const opzioniDelProgetto = (info: TestInfo): BrowserContextOptions => {
  const { viewport, userAgent, isMobile, hasTouch, deviceScaleFactor, locale, timezoneId } = info.project.use;
  return { viewport, userAgent, isMobile, hasTouch, deviceScaleFactor, locale, timezoneId, baseURL: URL_APP };
};
