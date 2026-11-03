import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

/**
 * UX-B1 (VPM-018-UX-FIX-02): in `/registrati` i requisiti della password
 * stavano dopo «Data di nascita», a 375 px lontani dal campo che descrivono.
 * L'ordine nel DOM è anche l'ordine di lettura e di tabulazione, quindi si
 * prova sul sorgente: requisiti subito dopo il campo, prima della data, con lo
 * stesso `id` dell'`aria-describedby`.
 */
const sorgente = readFileSync(
  join(import.meta.dir, "../../app/registrati/page-client.tsx"),
  "utf8",
).replace(/\/\*[\s\S]*?\*\//g, "");

describe("registrazione — requisiti password adiacenti al campo", () => {
  const iPassword = sorgente.indexOf('id="password"');
  const iRequisiti = sorgente.indexOf("<RequisitiPassword");
  const iDob = sorgente.indexOf('id="dob"');

  it("i requisiti stanno fra il campo password e la data di nascita", () => {
    expect(iPassword).toBeGreaterThan(-1);
    expect(iRequisiti).toBeGreaterThan(iPassword);
    expect(iDob).toBeGreaterThan(iRequisiti);
  });

  it("sono nello stesso blocco del campo, senza altri campi in mezzo", () => {
    const fra = sorgente.slice(iPassword, iRequisiti);
    expect(fra).not.toMatch(/<Input\b|<Label\b/);
    expect(sorgente.match(/<RequisitiPassword/g)).toHaveLength(1);
  });

  it("collegano il campo con lo stesso id stabile di aria-describedby", () => {
    expect(sorgente).toInclude('attributiPasswordNuova("requisiti-password-registrazione")');
    expect(sorgente).toMatch(/<RequisitiPassword[^>]*id="requisiti-password-registrazione"/);
  });

  it("il blocco password occupa la riga intera della griglia", () => {
    expect(sorgente.slice(0, iPassword)).toMatch(/<div className="sm:col-span-2">\s*<Label htmlFor="password">/);
  });
});
