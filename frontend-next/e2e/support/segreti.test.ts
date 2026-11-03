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
    expect(digitazioniDiPassword("await campo.fill(\n  pwd,\n);")).toHaveLength(1);
    expect(digitazioniDiPassword("await page.keyboard.insertText(segreto);")).toHaveLength(1);
    expect(digitazioniDiPassword('await page.getByLabel("Password", { exact: true }).fill(valore);')).toHaveLength(1);
    expect(digitazioniDiPassword("await page.locator('input[type=password]').type(x);")).toHaveLength(1);
    expect(digitazioniDiPassword("await scriviSegreto(page.getByLabel('Password'), password);")).toEqual([]);
    expect(digitazioniDiPassword('await page.getByLabel("Email").fill(email);')).toEqual([]);
  });

  test("nessuno spec della suite digita una password con fill/type", () => {
    const cartelle = [path.resolve(__dirname, ".."), __dirname];
    const violazioni = cartelle.flatMap((cartella) =>
      readdirSync(cartella)
        .filter((nome) => nome.endsWith(".e2e.ts") || (cartella === __dirname && nome.endsWith(".ts") && !nome.endsWith(".test.ts") && nome !== "segreti.ts"))
        .flatMap((nome) => digitazioniDiPassword(readFileSync(path.join(cartella, nome), "utf8")).map((r) => `${nome}: ${r.trim()}`)),
    );
    expect(violazioni).toEqual([]);
  });
});
