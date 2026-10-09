#!/usr/bin/env node

// Genera favicon, icone e immagine social dal solo logo approvato
// (public/images/vinea-logo-scelto.png), che resta intatto: ogni asset è un
// ritaglio del sigillo ridimensionato, senza ridisegno né cambi di colore.
// Rieseguire dopo un cambio di logo e alzare il suffisso `-vN` dei nomi in
// public/brand/ (e in src/lib/brand/metadata.ts) per superare le cache.

import { mkdir, writeFile } from "node:fs/promises";
import { fileURLToPath, pathToFileURL } from "node:url";
import sharp from "sharp";

const publicDirectory = new URL("../public/", import.meta.url);
export const logoSource = fileURLToPath(new URL("images/vinea-logo-scelto.png", publicDirectory));

const LOGO = Object.freeze({ width: 1024, height: 662 });
// Sigillo bordeaux misurato sul logo 1024×662: centro (515.5, 331), diametro
// 477. Il raggio 236 esclude l'ombra morbida sul bordo del disco.
const SEAL = Object.freeze({ cx: 515.5, cy: 331, radius: 236 });
// Fondo crema del logo, per le superfici che non ammettono trasparenza.
const CREAM = Object.freeze({ r: 244, g: 238, b: 226, alpha: 1 });

export const FAVICON_SIZES = Object.freeze([16, 32, 48]);
export const outputs = Object.freeze({
  favicon: new URL("favicon.ico", publicDirectory),
  icon192: new URL("brand/vinea-icon-192-v1.png", publicDirectory),
  appleTouchIcon: new URL("brand/vinea-apple-touch-icon-180-v1.png", publicDirectory),
  appleTouchIconRoot: new URL("apple-touch-icon.png", publicDirectory),
  openGraph: new URL("brand/vinea-og-1200x630-v1.jpg", publicDirectory),
  emailLogo: new URL("brand/vinea-email-logo-240-v1.png", publicDirectory),
});

/** Il disco del sigillo su fondo trasparente, quadrato `size`×`size`. */
async function sealOnTransparent(size) {
  const side = SEAL.radius * 2;
  const left = Math.round(SEAL.cx - SEAL.radius);
  const top = Math.round(SEAL.cy - SEAL.radius);
  const mask = Buffer.from(
    `<svg xmlns="http://www.w3.org/2000/svg" width="${side}" height="${side}">` +
      `<circle cx="${SEAL.radius}" cy="${SEAL.radius}" r="${SEAL.radius}" fill="#fff"/></svg>`,
  );
  const disc = await sharp(logoSource)
    .extract({ left, top, width: side, height: side })
    .ensureAlpha()
    .composite([{ input: mask, blend: "dest-in" }])
    .png()
    .toBuffer();
  return sharp(disc).resize(size, size, { kernel: "lanczos3" });
}

/** Il logo così com'è, ritagliato attorno al sigillo con il suo fondo crema. */
function logoCrop({ width, height }) {
  const clamp = (start, length, total) => Math.min(Math.max(Math.round(start), 0), total - length);
  return sharp(logoSource)
    .extract({
      left: clamp(SEAL.cx - width / 2, width, LOGO.width),
      top: clamp(SEAL.cy - height / 2, height, LOGO.height),
      width,
      height,
    });
}

/** ICO con voci BMP 32 bit (BGRA dal basso + maschera AND), leggibili ovunque. */
async function encodeIco(sizes) {
  const images = [];
  for (const size of sizes) {
    const rgba = await (await sealOnTransparent(size)).raw().toBuffer();
    const header = Buffer.alloc(40);
    header.writeUInt32LE(40, 0);
    header.writeInt32LE(size, 4);
    header.writeInt32LE(size * 2, 8);
    header.writeUInt16LE(1, 12);
    header.writeUInt16LE(32, 14);
    header.writeUInt32LE(size * size * 4, 20);
    const pixels = Buffer.alloc(size * size * 4);
    for (let y = 0; y < size; y++) {
      for (let x = 0; x < size; x++) {
        const from = (y * size + x) * 4;
        const to = ((size - 1 - y) * size + x) * 4;
        pixels[to] = rgba[from + 2];
        pixels[to + 1] = rgba[from + 1];
        pixels[to + 2] = rgba[from];
        pixels[to + 3] = rgba[from + 3];
      }
    }
    // Maschera AND vuota: la trasparenza è già nel canale alfa.
    const maskStride = Math.ceil(size / 32) * 4;
    images.push({ size, data: Buffer.concat([header, pixels, Buffer.alloc(maskStride * size)]) });
  }

  const directory = Buffer.alloc(6 + images.length * 16);
  directory.writeUInt16LE(0, 0);
  directory.writeUInt16LE(1, 2);
  directory.writeUInt16LE(images.length, 4);
  let offset = directory.length;
  images.forEach(({ size, data }, index) => {
    const entry = 6 + index * 16;
    directory.writeUInt8(size, entry);
    directory.writeUInt8(size, entry + 1);
    directory.writeUInt16LE(1, entry + 4);
    directory.writeUInt16LE(32, entry + 6);
    directory.writeUInt32LE(data.length, entry + 8);
    directory.writeUInt32LE(offset, entry + 12);
    offset += data.length;
  });
  return Buffer.concat([directory, ...images.map(({ data }) => data)]);
}

export async function renderBrandIcons() {
  const favicon = await encodeIco(FAVICON_SIZES);
  const icon192 = await (await sealOnTransparent(192)).png({ compressionLevel: 9 }).toBuffer();
  // iOS non rispetta la trasparenza: sigillo al ~80% sul fondo crema del logo.
  const appleTouchIcon = await logoCrop({ width: 596, height: 596 })
    .resize(180, 180, { kernel: "lanczos3" })
    .flatten({ background: CREAM })
    .png({ compressionLevel: 9 })
    .toBuffer();
  // Tutta la larghezza del logo al rapporto 1200:630, sigillo al centro.
  const openGraph = await logoCrop({ width: 1024, height: 538 })
    .resize(1200, 630, { kernel: "lanczos3" })
    .jpeg({ quality: 88, mozjpeg: true })
    .toBuffer();
  // Email di Auth (supabase/templates/): sigillo sul fondo crema, 240 px per
  // una resa nitida a 120 px sugli schermi ad alta densità e un peso adatto
  // ai client di posta, che il logo sorgente da 600 KB non ha.
  const emailLogo = await logoCrop({ width: 596, height: 596 })
    .resize(240, 240, { kernel: "lanczos3" })
    .flatten({ background: CREAM })
    .png({ compressionLevel: 9, palette: true, quality: 90 })
    .toBuffer();
  return { favicon, icon192, appleTouchIcon, appleTouchIconRoot: appleTouchIcon, openGraph, emailLogo };
}

async function main() {
  const rendered = await renderBrandIcons();
  await mkdir(new URL("brand/", publicDirectory), { recursive: true });
  for (const [name, target] of Object.entries(outputs)) {
    await writeFile(target, rendered[name]);
    console.log(`${target.pathname} (${rendered[name].length} byte)`);
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  await main();
}
