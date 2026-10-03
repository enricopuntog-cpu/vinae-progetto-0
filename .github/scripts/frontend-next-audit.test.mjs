// Proves the audit policy: one advisory admitted by name, everything else red.
// Usage: node --test .github/scripts/frontend-next-audit.test.mjs
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  ECCEZIONE,
  advisoryDaUrl,
  chiusuraRuntime,
  leggiLockfile,
  valutaAudit,
  versioniInstallate,
} from "./frontend-next-audit.mjs";

const voce = (spec, dipendenze = {}) => [spec, "", { dependencies: dipendenze }, "sha512-finta"];

/** A lockfile shaped like the real one: braces only under dev tooling. */
const lockDevOnly = () => ({
  workspaces: {
    "": {
      dependencies: { next: "16.3.6", react: "19.2.4" },
      devDependencies: { shadcn: "^4.16.0", "eslint-config-next": "16.3.6" },
    },
  },
  packages: {
    next: voce("next@16.3.6", { react: "19.2.4" }),
    react: voce("react@19.2.4"),
    shadcn: voce("shadcn@4.16.0", { "fast-glob": "^3.3.3" }),
    "eslint-config-next": voce("eslint-config-next@16.3.6", { "fast-glob": "^3.3.3" }),
    "fast-glob": voce("fast-glob@3.3.3", { micromatch: "^4.0.8" }),
    micromatch: voce("micromatch@4.0.8", { braces: "^3.0.3" }),
    braces: voce("braces@3.0.3", { "fill-range": "^7.1.1" }),
    "fill-range": voce("fill-range@7.1.1"),
  },
});

const manifestDevOnly = () => ({
  dependencies: { next: "16.3.6", react: "19.2.4" },
  devDependencies: { shadcn: "^4.16.0", "eslint-config-next": "16.3.6" },
});

const avvisoBraces = (sovrascritture = {}) => ({
  id: 1240992,
  url: "https://github.com/advisories/GHSA-vfj7-8cjw-p6xm",
  title: "braces vulnerable to stack-exhaustion denial of service through deeply nested patterns",
  severity: "high",
  vulnerable_versions: "<=3.0.3",
  cwe: ["CWE-674"],
  ...sovrascritture,
});

const valuta = (audit, { lock = lockDevOnly(), manifest = manifestDevOnly() } = {}) =>
  valutaAudit({ audit, lock, manifest });

test("A. solo GHSA-vfj7-8cjw-p6xm su braces 3.0.3 dev-only: passa", () => {
  const esito = valuta({ braces: [avvisoBraces()] });
  assert.equal(esito.ok, true);
  assert.equal(esito.ammesse.length, 1);
  assert.equal(esito.ammesse[0].pacchetto, "braces");
  assert.deepEqual(esito.bloccanti, []);
});

test("B. una seconda advisory qualsiasi: blocca", () => {
  const esito = valuta({
    braces: [avvisoBraces()],
    lodash: [
      {
        id: 999,
        url: "https://github.com/advisories/GHSA-aaaa-bbbb-cccc",
        title: "prototype pollution",
        severity: "critical",
        vulnerable_versions: "<4.17.21",
      },
    ],
  });
  assert.equal(esito.ok, false);
  assert.equal(esito.bloccanti.length, 1);
  assert.equal(esito.bloccanti[0].pacchetto, "lodash");
  assert.equal(esito.ammesse.length, 1);
});

test("B bis. una seconda advisory sullo stesso braces: blocca", () => {
  const esito = valuta({
    braces: [avvisoBraces(), avvisoBraces({ url: "https://github.com/advisories/GHSA-dddd-eeee-ffff" })],
  });
  assert.equal(esito.ok, false);
  assert.equal(esito.bloccanti.length, 1);
  assert.match(esito.bloccanti[0].motivi.join(" "), /diversa da GHSA-vfj7-8cjw-p6xm/);
});

test("C. advisory ammessa ma pacchetto diverso: blocca", () => {
  const esito = valuta({ micromatch: [avvisoBraces()] });
  assert.equal(esito.ok, false);
  assert.match(esito.bloccanti[0].motivi.join(" "), /nessuna eccezione e' ammessa per `micromatch`/);
});

test("D. braces vulnerabile ma raggiungibile dal runtime: blocca", () => {
  const lock = lockDevOnly();
  lock.packages.next = voce("next@16.3.6", { react: "19.2.4", micromatch: "^4.0.8" });
  const esito = valuta({ braces: [avvisoBraces()] }, { lock });
  assert.equal(esito.ok, false);
  assert.match(esito.bloccanti[0].motivi.join(" "), /dipendenze di runtime/);
});

test("D bis. braces dipendenza diretta: blocca anche se dichiarata fra le dev", () => {
  const manifest = manifestDevOnly();
  manifest.devDependencies.braces = "^3.0.3";
  const lock = lockDevOnly();
  lock.workspaces[""].devDependencies.braces = "^3.0.3";
  const esito = valuta({ braces: [avvisoBraces()] }, { lock, manifest });
  assert.equal(esito.ok, false);
  assert.match(esito.bloccanti[0].motivi.join(" "), /dichiarata in `devDependencies`/);
});

test("E. zero advisory: passa", () => {
  const esito = valuta({});
  assert.deepEqual(esito, { ok: true, ammesse: [], bloccanti: [] });
});

test("F. output malformato o non interpretabile: errore, mai un verde", () => {
  for (const audit of [null, [], "braces", 7, { braces: {} }, { braces: [] }, { braces: [null] }]) {
    assert.throws(() => valuta(audit), /non interpretabil/);
  }
  for (const campo of ["url", "title", "severity", "vulnerable_versions"]) {
    const avviso = avvisoBraces();
    delete avviso[campo];
    assert.throws(() => valuta({ braces: [avviso] }), new RegExp(`campo \`${campo}\` mancante`));
  }
  assert.throws(() => leggiLockfile(""), /vuoto o illeggibile/);
  assert.throws(() => leggiLockfile("{ non json"), /non interpretabile/);
  assert.throws(() => valuta({}, { lock: {} }), /senza mappa `packages`/);
  assert.throws(() => valuta({}, { lock: { packages: {} } }), /senza workspace radice/);
});

test("intervallo vulnerabile allargato: l'eccezione non vale piu'", () => {
  const esito = valuta({ braces: [avvisoBraces({ vulnerable_versions: "<=3.0.4" })] });
  assert.equal(esito.ok, false);
  assert.match(esito.bloccanti[0].motivi.join(" "), /intervallo vulnerabile `<=3\.0\.4`/);
});

test("versione installata diversa o doppia: l'eccezione non vale piu'", () => {
  const lock = lockDevOnly();
  lock.packages.braces = voce("braces@3.0.2");
  assert.equal(valuta({ braces: [avvisoBraces()] }, { lock }).ok, false);

  const doppia = lockDevOnly();
  doppia.packages["shadcn/braces"] = voce("braces@3.0.1");
  const esito = valuta({ braces: [avvisoBraces()] }, { lock: doppia });
  assert.equal(esito.ok, false);
  assert.match(esito.bloccanti[0].motivi.join(" "), /versione installata 3\.0\.1, 3\.0\.3/);
});

test("un ramo di dipendenze irrisolvibile conta come runtime", () => {
  const lock = lockDevOnly();
  lock.packages.next = voce("next@16.3.6", { braces: "^3.0.3" });
  delete lock.packages.braces;
  assert.ok(chiusuraRuntime(lock).has("braces"));
});

test("la chiusura runtime segue i soli rami dell'applicazione", () => {
  const nomi = chiusuraRuntime(lockDevOnly());
  assert.ok(nomi.has("next"));
  assert.ok(nomi.has("react"));
  assert.ok(!nomi.has("shadcn"));
  assert.ok(!nomi.has("micromatch"));
  assert.ok(!nomi.has("braces"));
});

test("il lockfile reale ha le virgole finali e si legge comunque", async () => {
  const testo = await readFile(new URL("../../frontend-next/bun.lock", import.meta.url), "utf8");
  assert.match(testo, /,\s*\}/);
  const lock = leggiLockfile(testo);
  assert.equal(lock.workspaces[""].name, "frontend-next");
});

// Guardia statica del confine dev-only: non assume, legge l'albero reale. Se un
// domani braces sparisce non c'e' nulla da sorvegliare; se resta, deve restare
// fuori dal runtime e alla versione esatta dell'eccezione.
test("confine dev-only del repository: braces fuori dal runtime, alla 3.0.3", async () => {
  const [lockTesto, manifestTesto] = await Promise.all([
    readFile(new URL("../../frontend-next/bun.lock", import.meta.url), "utf8"),
    readFile(new URL("../../frontend-next/package.json", import.meta.url), "utf8"),
  ]);
  const lock = leggiLockfile(lockTesto);
  const manifest = JSON.parse(manifestTesto);
  const versioni = versioniInstallate(lock, ECCEZIONE.pacchetto);
  if (versioni.length === 0) return;
  assert.deepEqual(versioni, [ECCEZIONE.versione]);
  assert.ok(!chiusuraRuntime(lock).has(ECCEZIONE.pacchetto));
  for (const campo of ["dependencies", "devDependencies", "optionalDependencies", "peerDependencies"]) {
    assert.ok(!Object.hasOwn(manifest[campo] ?? {}, ECCEZIONE.pacchetto));
  }
  assert.equal(advisoryDaUrl(`https://github.com/advisories/${ECCEZIONE.advisory}`), ECCEZIONE.advisory);
});
