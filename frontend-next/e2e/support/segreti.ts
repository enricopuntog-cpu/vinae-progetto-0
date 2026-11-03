import type { Locator } from "@playwright/test";

/**
 * Scrive un segreto (password) in un campo SENZA che il valore finisca nel
 * report. `fill`, `type`, `pressSequentially` e `keyboard.*` intitolano il passo
 * con il valore (`Fill "…"`) e il reporter HTML lo conserva anche con trace,
 * screenshot e video spenti (VPM-018-E2E-CRIT-01, R-PASS-01). Qui il passo è un
 * `Evaluate` senza argomenti nel titolo: il valore passa con il setter nativo e
 * un evento `input`, che è ciò che ascolta un campo controllato di React.
 */
export const scriviSegreto = async (campo: Locator, valore: string): Promise<void> => {
  await campo.evaluate((elemento, segreto) => {
    const input = elemento as HTMLInputElement;
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")?.set?.call(input, segreto);
    input.dispatchEvent(new Event("input", { bubbles: true }));
  }, valore);
};

/**
 * Righe di uno spec che digiterebbero una password con un'azione che la mette nel
 * titolo del passo. Puro, per il test statico (`segreti.test.ts`).
 */
export const digitazioniDiPassword = (sorgente: string): string[] =>
  sorgente
    .split(/\r?\n/)
    .filter((riga) => /\.(fill|type|pressSequentially|insertText)\s*\([^)]*password/i.test(riga));
