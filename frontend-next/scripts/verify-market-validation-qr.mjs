#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import jsQR from "jsqr";
import sharp from "sharp";
import {
  MARKET_VALIDATION_URL,
  pngOutput,
  renderMarketValidationQr,
  svgOutput,
} from "./generate-market-validation-qr.mjs";

const MINIMUM_PRINT_SIZE = 1000;

async function decodeQr(input, label) {
  const { data, info } = await sharp(input)
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  const decoded = jsQR(new Uint8ClampedArray(data), info.width, info.height, {
    inversionAttempts: "dontInvert",
  });
  if (!decoded) throw new Error(`${label}: QR non decodificabile.`);
  if (decoded.data !== MARKET_VALIDATION_URL) {
    throw new Error(`${label}: payload inatteso ${JSON.stringify(decoded.data)}.`);
  }
  return info;
}

export async function verifyMarketValidationQr() {
  const [storedPng, storedSvg, expected] = await Promise.all([
    readFile(pngOutput),
    readFile(svgOutput, "utf8"),
    renderMarketValidationQr(),
  ]);

  if (!storedPng.equals(expected.png)) {
    throw new Error("PNG non deterministico o non rigenerato dallo script versionato.");
  }
  if (storedSvg !== expected.svg) {
    throw new Error("SVG non deterministico o non rigenerato dallo script versionato.");
  }

  const pngInfo = await decodeQr(storedPng, "PNG");
  if (pngInfo.width < MINIMUM_PRINT_SIZE || pngInfo.height < MINIMUM_PRINT_SIZE) {
    throw new Error(
      `PNG troppo piccolo: ${pngInfo.width}x${pngInfo.height}; minimo ${MINIMUM_PRINT_SIZE}x${MINIMUM_PRINT_SIZE}.`,
    );
  }

  const svgRaster = await sharp(Buffer.from(storedSvg)).png().toBuffer();
  await decodeQr(svgRaster, "SVG");

  return { width: pngInfo.width, height: pngInfo.height };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  verifyMarketValidationQr()
    .then(({ width, height }) => {
      console.log(
        `QR Market Validation verificati: PNG ${width}x${height}, SVG e PNG decodificano ${MARKET_VALIDATION_URL}`,
      );
    })
    .catch((error) => {
      console.error(error);
      process.exitCode = 1;
    });
}
