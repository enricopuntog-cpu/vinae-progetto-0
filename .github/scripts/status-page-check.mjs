#!/usr/bin/env node
// Validates the static status page in status-page/site before Cloudflare Pages
// publishes it. The page is edited by hand during incidents, so this guards the
// properties that make it useful when everything else is down: no runtime
// dependency, no external resource, one valid state, strict headers, no secret.
// Usage: node .github/scripts/status-page-check.mjs [site-dir]
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const dir = process.argv[2] ?? "status-page/site";
const STATES = {
  operativo: "Operativo",
  investigazione: "Investigazione in corso",
  identificato: "Problema identificato",
  aggiornamento: "Aggiornamento",
  risolto: "Risolto",
};
const ALLOWED_FILES = new Set(["index.html", "404.html", "_headers"]);
const errors = [];
const fail = (msg) => errors.push(msg);

let files = [];
try {
  files = readdirSync(dir);
} catch {
  console.error(`status-page-check: directory non leggibile: ${dir}`);
  process.exit(1);
}
for (const f of files) if (!ALLOWED_FILES.has(f)) fail(`file non ammesso nel sito pubblicato: ${f}`);
for (const f of ALLOWED_FILES) if (!files.includes(f)) fail(`file mancante: ${f}`);

const read = (f) => {
  try {
    return readFileSync(join(dir, f), "utf8");
  } catch {
    return "";
  }
};

const FORBIDDEN = [
  [/<script\b/i, "tag <script>"],
  [/<link\b/i, "tag <link>"],
  [/<(iframe|img|object|embed|form|video|audio|source)\b/i, "risorsa o form"],
  [/@import|url\(/i, "risorsa CSS esterna"],
  [/\s(src|srcset|action|formaction)\s*=/i, "attributo che carica risorse"],
  [/\son[a-z]+\s*=/i, "handler JavaScript inline"],
  [/http:\/\//i, "URL non HTTPS"],
  [/supabase|netlify\.app|\/api\//i, "riferimento a runtime applicativo"],
  [/eyJ[A-Za-z0-9_-]{10,}|sk_(live|test)_|service_role|BEGIN [A-Z ]*PRIVATE KEY/, "possibile secret"],
];

for (const f of ["index.html", "404.html"]) {
  const html = read(f);
  if (!html) continue;
  for (const [re, what] of FORBIDDEN) if (re.test(html)) fail(`${f}: ${what}`);
  for (const [, href] of html.matchAll(/\shref\s*=\s*"([^"]*)"/gi)) {
    if (!(href === "/" || href.startsWith("https://vineawineclub.com/") || href.startsWith("mailto:"))) {
      fail(`${f}: link non ammesso ${href}`);
    }
  }
}

const index = read("index.html");
const sections = [...index.matchAll(/<section class="status" data-state="([^"]*)"[^>]*>([\s\S]*?)<\/section>/g)];
if (sections.length !== 1) {
  fail(`index.html: attesa esattamente una sezione di stato corrente, trovate ${sections.length}`);
} else {
  const [, state, body] = sections[0];
  if (!(state in STATES)) {
    fail(`index.html: stato non ammesso "${state}" (ammessi: ${Object.keys(STATES).join(", ")})`);
  } else {
    const label = body.match(/<span class="label"[^>]*>([^<]*)<\/span>/)?.[1]?.trim();
    if (label !== STATES[state]) fail(`index.html: etichetta "${label}" non coerente con lo stato ${state}`);
  }
  const dt = body.match(/<time datetime="([^"]+)"/)?.[1];
  if (!dt || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?(Z|[+-]\d{2}:\d{2})$/.test(dt) || Number.isNaN(Date.parse(dt))) {
    fail("index.html: ultimo aggiornamento senza <time datetime> ISO con fuso orario");
  }
}
for (const [, s] of index.matchAll(/data-state="([^"]*)"/g)) {
  if (!(s in STATES)) fail(`index.html: data-state non ammesso "${s}"`);
}

const headers = read("_headers");
for (const needle of [
  "Content-Security-Policy: default-src 'none';",
  "frame-ancestors 'none'",
  "X-Content-Type-Options: nosniff",
  "Referrer-Policy: no-referrer",
]) {
  if (!headers.includes(needle)) fail(`_headers: manca ${needle}`);
}
if (/script-src|connect-src/.test(headers)) fail("_headers: la CSP non deve ammettere script o connessioni");

if (errors.length) {
  for (const e of errors) console.error(`status-page-check: ${e}`);
  process.exit(1);
}
console.log(`status-page-check: OK (${dir})`);
