/**
 * Il contesto dell'annuncio dentro il caricamento dell'ordine.
 *
 * Una lettura in più nella stessa `Promise.all` dell'ordine è comoda e pericolosa
 * in parti uguali: se fallisce, e nessuno l'ha isolata, l'intera pagina risponde
 * «Ordine non disponibile» per un dato che serviva soltanto a scegliere quali
 * quattro frasi mostrare. Qui si prova che sia isolata, che la chieda solo chi
 * può leggerla, e che il suo esito non attraversi mai il confine verso ciò che
 * decide se una spedizione può partire.
 */

import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const RADICE = join(import.meta.dir, "../..");
const leggi = (percorso: string) => readFileSync(join(RADICE, percorso), "utf8");
const senzaCommenti = (sorgente: string) =>
  sorgente.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");

const HOOK = senzaCommenti(leggi("src/hooks/useOrderDetail.ts"));
const PAGINA = senzaCommenti(leggi("src/app/ordine/[id]/page-client.tsx"));
const ORDINI = senzaCommenti(leggi("src/services/phase7/order-service.ts"));

describe("la lettura del contesto", () => {
  it("la chiede solo il venditore", () => {
    // `listings_select_own` filtra su `seller_id = auth.uid()`: per il
    // compratore la riga non esiste, e chiederla sarebbe una lettura vuota a
    // ogni apertura dell'ordine.
    expect(HOOK).toMatch(/venditore\s*\?\s*annunci/);
    expect(HOOK).toMatch(/:\s*Promise\.resolve\(null\),/);
    expect(HOOK).toInclude("const venditore = ordine.seller_id === userId;");
  });

  it("passa da `mioAnnuncio`, che legge la tabella", () => {
    expect(HOOK).toInclude("mioAnnuncio(ordine.listing_id)");
    expect(HOOK).toInclude("annuncio?.logistica ?? null");
    // Non dal catalogo pubblico: l'annuncio dietro un ordine è venduto, e
    // `public_listings` filtra `stato = 'attivo'`.
    expect(HOOK).not.toInclude("public_listings");
    expect(HOOK).not.toInclude("annunci.dettaglio");
  });

  it("un contesto illeggibile non diventa un ordine illeggibile", () => {
    expect(HOOK).toInclude(".catch(() => null)");
    // Nessun nuovo ramo d'errore nella coda di `carica`: i tre esistenti stanno
    // tutti prima della `Promise.all`, e riguardano l'ordine stesso.
    const coda = HOOK.slice(
      HOOK.indexOf("await Promise.all"),
      HOOK.indexOf("const ricarica"),
    );
    expect(coda).not.toInclude('fase: "errore"');
    expect(coda).not.toInclude("throw");
    expect(coda).toInclude('fase: "pronto"');
  });

  it("entra nel dettaglio come terzo stato dichiarato", () => {
    expect(HOOK).toInclude("logisticaAnnuncio: LogisticaProprietario | null;");
    expect(HOOK).toInclude("logisticaAnnuncio,");
    expect(HOOK).toInclude(
      'import type { LogisticaProprietario } from "@/services/listing-service";',
    );
  });

  it("resta un attributo dell'annuncio: niente viene copiato sull'ordine", () => {
    // La confezione originale non è un fatto dell'ordine e non va congelata lì:
    // l'ordine ha già `listing_id`, e due sorgenti per lo stesso dato
    // divergerebbero alla prima modifica dell'annuncio.
    for (const scrittura of [
      "confezione_originale_tipo",
      "confezione_originale_foto",
      "handoff_venditore",
    ]) {
      expect(HOOK).not.toInclude(scrittura);
      expect(ORDINI).not.toInclude(scrittura);
    }
    expect(HOOK).not.toInclude("dichiaraLogistica");
  });

  it("arriva al solo pannello del venditore, e non tocca i suoi cancelli", () => {
    expect(PAGINA).toInclude("logistica={logisticaAnnuncio}");
    // Nessun altro consumatore, e nessuna condizione della pagina che ne
    // dipenda: il pannello compare per stato dell'ordine, come prima.
    expect([...PAGINA.matchAll(/logisticaAnnuncio/g)]).toHaveLength(2);
    expect(PAGINA).toInclude("venditore && puoPreparare(ordine.stato)");
    expect(PAGINA).not.toMatch(/logisticaAnnuncio\s*(&&|\?|!==|===)/);
    // E il servizio dell'ordine continua a non sapere che esista.
    expect(ORDINI).not.toInclude("logistica");
  });
});
