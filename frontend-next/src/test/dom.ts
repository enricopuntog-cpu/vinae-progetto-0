import { GlobalRegistrator } from "@happy-dom/global-registrator";

/**
 * DOM simulato per i test di comportamento dei componenti (VPM-018-UI-TEST-01).
 *
 * La suite gira con `bun test --isolate` (script `test`): ogni file ha i propri moduli e
 * i propri `mock.module`. Senza, Radix caricato da un test in ambiente server valuta
 * `useLayoutEffect` come funzione vuota una volta per tutte e i dialoghi non si montano.
 *
 * Il DOM si apre all'inizio del file e si chiude in `afterAll`, mai in un preload: il
 * resto della suite si aspetta un ambiente server, senza `window`. Gli import che leggono
 * `document` al caricamento (`@testing-library/*`, `react-dom/client`) vanno fatti con
 * `await import` dopo `apriDom()`: gli import statici verrebbero sollevati prima.
 */
export const apriDom = (): void => {
  if (GlobalRegistrator.isRegistered) return;
  GlobalRegistrator.register({ url: "https://vinea.test/", width: 1280, height: 800 });
};

export const chiudiDom = async (): Promise<void> => {
  // React può avere effetti in coda dopo l'ultimo `cleanup`, e leggono `window`.
  await new Promise((risolvi) => setTimeout(risolvi, 50));
  if (GlobalRegistrator.isRegistered) await GlobalRegistrator.unregister();
};
