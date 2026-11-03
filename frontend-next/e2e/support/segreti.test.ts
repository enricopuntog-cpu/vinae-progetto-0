import { describe, expect, test } from "bun:test";
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";
import { digitazioniDiPassword } from "./segreti";

/**
 * VPM-018-E2E-CRIT-01 (R-PASS-01): nessuno spec digita una password con
 * un'azione che ne mette il valore nel titolo del passo, e quindi nel report
 * HTML caricato dalla CI. Le password si scrivono con `scriviSegreto`.
 */
describe("password nel browser senza tracce nel report", () => {
  test("il rilevatore riconosce fill, type e pressSequentially su una password", () => {
    expect(digitazioniDiPassword('await page.getByLabel("Password").fill(password);')).toHaveLength(1);
    expect(digitazioniDiPassword("await campo.type(passwordNuova());")).toHaveLength(1);
    expect(digitazioniDiPassword("await campo.pressSequentially(sbagliata_password)")).toHaveLength(1);
    expect(digitazioniDiPassword("await scriviSegreto(page.getByLabel('Password'), password);")).toEqual([]);
    expect(digitazioniDiPassword('await page.getByLabel("Email").fill(email);')).toEqual([]);
  });

  test("nessuno spec della suite digita una password con fill/type", () => {
    const cartella = path.resolve(__dirname, "..");
    const violazioni = readdirSync(cartella)
      .filter((nome) => nome.endsWith(".e2e.ts"))
      .flatMap((nome) => digitazioniDiPassword(readFileSync(path.join(cartella, nome), "utf8")).map((r) => `${nome}: ${r.trim()}`));
    expect(violazioni).toEqual([]);
  });
});
