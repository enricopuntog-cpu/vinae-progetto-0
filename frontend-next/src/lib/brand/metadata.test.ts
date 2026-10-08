import { describe, expect, it } from "bun:test";
import { createHash } from "node:crypto";
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join, resolve } from "node:path";
import sharp, { type Sharp } from "sharp";
import {
  anteprimaSocialVinea,
  VINEA_APPLE_TOUCH_ICON,
  VINEA_FAVICON,
  VINEA_ICON_192,
  VINEA_ICONS,
  VINEA_SITE_NAME,
  VINEA_SOCIAL_IMAGE,
} from "./metadata";

/**
 * Fino all'8 ottobre 2026 Safari su iPhone e le anteprime WhatsApp di
 * vineawineclub.com mostravano un cuore: public/favicon.ico era un'icona
 * estranea al marchio, e nessun og:image o apple-touch-icon ne prendeva il
 * posto. Accanto viveva src/app/favicon.ico, il triangolo di scaffold, che
 * Next dichiarava nell'HTML mentre Netlify serviva il cuore. Ora ogni icona
 * deriva da public/images/vinea-logo-scelto.png e ha una sola fonte.
 */

const progetto = resolve(import.meta.dir, "../../..");
const pubblico = join(progetto, "public");
const app = join(progetto, "src/app");
const leggi = (percorso: string) => readFileSync(join(progetto, percorso));
const sha256 = (dati: Buffer) => createHash("sha256").update(dati).digest("hex");
const filePubblico = (url: string) => join(pubblico, url.replace(/^\//, ""));

const LOGO_SCELTO = "public/images/vinea-logo-scelto.png";
const LOGO_SCELTO_SHA256 = "6023acc74cf55205e126599eea08f973f755f4cb67db86a16f91298e657598b3";
const CUORE_SHA256 = "dd821076a9b03adc2173c93956226aea3d92482d7578fc4339c5d3a2e9c24586";
const TRIANGOLO_SCAFFOLD_SHA256 = "2b8ad2d33455a8f736fc3a8ebf8f0bdea8848ad4c0db48a2833bd0f9cd775932";

function tuttiIFile(cartella: string): string[] {
  return readdirSync(cartella).flatMap((nome) => {
    const percorso = join(cartella, nome);
    return statSync(percorso).isDirectory() ? tuttiIFile(percorso) : [percorso];
  });
}

function vociIco(dati: Buffer) {
  expect(dati.readUInt16LE(0)).toBe(0);
  expect(dati.readUInt16LE(2)).toBe(1);
  return Array.from({ length: dati.readUInt16LE(4) }, (_, indice) => {
    const voce = 6 + indice * 16;
    return { larghezza: dati[voce] || 256, altezza: dati[voce + 1] || 256 };
  });
}

/** Differenza media per canale tra due immagini ridotte a 48×48. */
async function distanza(a: Sharp, b: Sharp) {
  const ridotta = (immagine: Sharp) =>
    immagine.resize(48, 48, { fit: "fill" }).flatten({ background: "#f4eee2" }).removeAlpha().raw().toBuffer();
  const [pa, pb] = await Promise.all([ridotta(a), ridotta(b)]);
  let somma = 0;
  for (let i = 0; i < pa.length; i++) somma += Math.abs(pa[i] - pb[i]);
  return somma / pa.length;
}

describe("logo Vinea come unica fonte del marchio", () => {
  it("il logo scelto resta byte per byte quello approvato", () => {
    expect(sha256(leggi(LOGO_SCELTO))).toBe(LOGO_SCELTO_SHA256);
  });

  it("né il cuore né il triangolo di scaffold esistono più tra gli asset", () => {
    for (const file of [...tuttiIFile(pubblico), ...tuttiIFile(app)]) {
      const impronta = sha256(readFileSync(file));
      expect({ file, impronta }).not.toEqual({ file, impronta: CUORE_SHA256 });
      expect({ file, impronta }).not.toEqual({ file, impronta: TRIANGOLO_SCAFFOLD_SHA256 });
    }
  });

  it("app/ non ha icone file-based che prevarrebbero su metadata.icons", () => {
    const concorrenti = readdirSync(app).filter((nome) =>
      /^(favicon|icon\d*|apple-icon\d*|opengraph-image|twitter-image)\./.test(nome),
    );
    expect(concorrenti).toEqual([]);
  });
});

describe("favicon e icone", () => {
  it("/favicon.ico contiene il sigillo a 16, 32 e 48 pixel", async () => {
    const ico = leggi("public/favicon.ico");
    expect(vociIco(ico)).toEqual([
      { larghezza: 16, altezza: 16 },
      { larghezza: 32, altezza: 32 },
      { larghezza: 48, altezza: 48 },
    ]);
  });

  it("ogni icona dichiarata esiste in public/ con le misure dichiarate", async () => {
    const dichiarate = [...VINEA_ICONS.icon, ...VINEA_ICONS.apple].filter(({ type }) => type === "image/png");
    expect(dichiarate.map(({ url }) => url)).toEqual([VINEA_ICON_192, VINEA_APPLE_TOUCH_ICON]);
    for (const { url, sizes } of dichiarate) {
      const { width, height, format } = await sharp(filePubblico(url)).metadata();
      expect(format).toBe("png");
      expect(`${width}x${height}`).toBe(sizes);
    }
    expect(existsSync(filePubblico(VINEA_FAVICON))).toBe(true);
    expect(VINEA_ICONS.shortcut).toBe(VINEA_FAVICON);
  });

  it("l'apple-touch-icon è opaca (iOS riempie di nero la trasparenza) e coincide con la copia alla radice", async () => {
    const versionata = readFileSync(filePubblico(VINEA_APPLE_TOUCH_ICON));
    expect(leggi("public/apple-touch-icon.png").equals(versionata)).toBe(true);
    const { hasAlpha } = await sharp(versionata).metadata();
    expect(hasAlpha).toBe(false);
  });

  it("le icone riproducono il sigillo del logo scelto, senza ridisegno", async () => {
    const sigillo = () => sharp(join(progetto, LOGO_SCELTO)).extract({ left: 280, top: 95, width: 472, height: 472 });
    expect(await distanza(sharp(filePubblico(VINEA_ICON_192)), sigillo())).toBeLessThan(6);
    const conFondo = () => sharp(join(progetto, LOGO_SCELTO)).extract({ left: 218, top: 33, width: 596, height: 596 });
    expect(await distanza(sharp(filePubblico(VINEA_APPLE_TOUCH_ICON)), conFondo())).toBeLessThan(6);
  });
});

describe("anteprima social", () => {
  it("l'immagine Open Graph è una 1200×630 leggera ritagliata dal logo scelto", async () => {
    const percorso = filePubblico(VINEA_SOCIAL_IMAGE.url);
    const { width, height, format } = await sharp(percorso).metadata();
    expect({ width, height, format }).toEqual({ width: 1200, height: 630, format: "jpeg" });
    expect([width, height]).toEqual([VINEA_SOCIAL_IMAGE.width as number, VINEA_SOCIAL_IMAGE.height as number]);
    // WhatsApp scarta in silenzio le anteprime troppo pesanti.
    expect(statSync(percorso).size).toBeLessThan(300_000);
    const ritaglio = sharp(join(progetto, LOGO_SCELTO)).extract({ left: 0, top: 62, width: 1024, height: 538 });
    expect(await distanza(sharp(percorso), ritaglio)).toBeLessThan(6);
  });

  it("Open Graph e Twitter portano nome, testi, URL e immagine di Vinea", () => {
    const { openGraph, twitter } = anteprimaSocialVinea({ title: "Prova Vinea", description: "Descrizione", path: "/beta-test" });
    expect(openGraph).toEqual({
      type: "website",
      locale: "it_IT",
      siteName: VINEA_SITE_NAME,
      url: "/beta-test",
      title: "Prova Vinea",
      description: "Descrizione",
      images: [VINEA_SOCIAL_IMAGE],
    });
    expect(twitter).toEqual({
      card: "summary_large_image",
      title: "Prova Vinea",
      description: "Descrizione",
      images: [VINEA_SOCIAL_IMAGE],
    });
    expect(VINEA_SITE_NAME).toBe("Vinea Wine Club");
  });

  it("il layout radice dichiara icone e anteprima Vinea senza toccare metadataBase e robots", () => {
    const layout = leggi("src/app/layout.tsx").toString("utf8");
    expect(layout).toContain('metadataBase: new URL(process.env.URL ?? "http://localhost:3000")');
    expect(layout).toContain("icons: VINEA_ICONS");
    expect(layout).toContain('...anteprimaSocialVinea({ title: VINEA_SITE_NAME, description: DESCRIZIONE, path: "/" })');
    expect(layout).toMatch(/robots: \{\s+index: false,\s+follow: false,/);
  });

  it("/ e /beta-test, che dichiarano un proprio openGraph, passano dall'anteprima Vinea", () => {
    const home = leggi("src/app/page.tsx").toString("utf8");
    expect(home).toMatch(/\.\.\.anteprimaSocialVinea\(\{[\s\S]*?path: "\/",\s+\}\)/);
    const beta = leggi("src/app/beta-test/page.tsx").toString("utf8");
    expect(beta).toContain('const TITOLO = "Prova Vinea";');
    expect(beta).toContain('...anteprimaSocialVinea({ title: TITOLO, description: DESCRIZIONE, path: "/beta-test" })');
    expect(beta).toContain("robots: { index: false, follow: false }");
    for (const sorgente of [home, beta]) expect(sorgente).not.toMatch(/^\s+openGraph:/m);
  });
});
