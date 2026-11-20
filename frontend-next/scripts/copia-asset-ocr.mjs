#!/usr/bin/env node
// WI-002 — copia in `public/ocr/` gli asset dell'OCR locale (tesseract.js), così
// il browser li scarica da Vinea e non da una CDN. Idempotente e senza rete:
// legge solo da `node_modules`. Gli asset NON sono nel repository (≈12 MB): si
// rigenerano a ogni `bun install` e a ogni build.
import { copyFileSync, existsSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const radice = join(dirname(fileURLToPath(import.meta.url)), "..");
const nm = join(radice, "node_modules");
const destinazione = join(radice, "public", "ocr");

const file = [
  ["tesseract.js/dist/worker.min.js", "worker.min.js"],
  ["tesseract.js-core/tesseract-core-lstm.wasm.js", "core/tesseract-core-lstm.wasm.js"],
  ["tesseract.js-core/tesseract-core-simd-lstm.wasm.js", "core/tesseract-core-simd-lstm.wasm.js"],
  ["tesseract.js-core/tesseract-core-relaxedsimd-lstm.wasm.js", "core/tesseract-core-relaxedsimd-lstm.wasm.js"],
  ["@tesseract.js-data/ita/4.0.0_best_int/ita.traineddata.gz", "lang/ita.traineddata.gz"],
];

const mancanti = file.filter(([da]) => !existsSync(join(nm, da)));
if (mancanti.length > 0) {
  console.error("[ocr] asset non trovati in node_modules:", mancanti.map(([da]) => da).join(", "));
  console.error("[ocr] esegui `bun install` nella cartella frontend-next.");
  process.exit(1);
}

for (const [da, a] of file) {
  mkdirSync(dirname(join(destinazione, a)), { recursive: true });
  copyFileSync(join(nm, da), join(destinazione, a));
}
writeFileSync(
  join(destinazione, "LICENSES.txt"),
  [
    "Asset dell'OCR locale di Vinea.",
    "tesseract.js e tesseract.js-core: Apache License 2.0 (https://github.com/naptha/tesseract.js).",
    "Dati lingua ita (tessdata_best, @tesseract.js-data/ita): Apache License 2.0 / MIT (https://github.com/tesseract-ocr/tessdata_best).",
    "",
  ].join("\n"),
);
console.log(`[ocr] ${file.length} asset copiati in public/ocr/`);
