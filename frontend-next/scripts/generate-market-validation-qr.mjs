#!/usr/bin/env node

import { mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import QRCode from "qrcode";

export const MARKET_VALIDATION_URL = "https://vineawineclub.com/beta-test";
export const QR_OPTIONS = Object.freeze({
  errorCorrectionLevel: "M",
  margin: 4,
  width: 1200,
  color: Object.freeze({ dark: "#000000ff", light: "#ffffffff" }),
});

export const repositoryRoot = new URL("../../", import.meta.url);
export const outputDirectory = new URL("docs/market-validation/", repositoryRoot);
export const pngOutput = new URL("vinea-beta-test-qr.png", outputDirectory);
export const svgOutput = new URL("vinea-beta-test-qr.svg", outputDirectory);

export async function renderMarketValidationQr() {
  const [png, svg] = await Promise.all([
    QRCode.toBuffer(MARKET_VALIDATION_URL, {
      ...QR_OPTIONS,
      type: "png",
    }),
    QRCode.toString(MARKET_VALIDATION_URL, {
      ...QR_OPTIONS,
      type: "svg",
    }),
  ]);

  return { png, svg };
}

export async function generateMarketValidationQr() {
  const { png, svg } = await renderMarketValidationQr();
  await mkdir(outputDirectory, { recursive: true });
  await Promise.all([writeFile(pngOutput, png), writeFile(svgOutput, svg, "utf8")]);
  return { png, svg };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  generateMarketValidationQr()
    .then(() => {
      console.log(`QR Market Validation generato per ${MARKET_VALIDATION_URL}`);
    })
    .catch((error) => {
      console.error(error);
      process.exitCode = 1;
    });
}
