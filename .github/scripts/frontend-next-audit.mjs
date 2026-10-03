#!/usr/bin/env node
// Audit gate for `frontend-next`. `bun audit` stays a hard gate: this wrapper
// admits exactly one finding, by name, and blocks everything else.
//
// The admitted exception is GHSA-vfj7-8cjw-p6xm on `braces` 3.0.3, decided on
// 3 October 2026: the advisory covers `<=3.0.3`, 3.0.3 is the newest version
// ever published, so no upgrade exists, and the package is reachable only
// through dev tooling (`shadcn` and `eslint-config-next` via `fast-glob` and
// `micromatch`), never from the application runtime graph.
//
// The exception is fail-closed outside that exact case. It stops holding, and
// the gate goes red again, as soon as any of these is true: a second advisory
// appears; the same advisory hits another package; the vulnerable range widens;
// the installed version is no longer exactly 3.0.3, or more than one is
// installed; `braces` becomes reachable from the runtime dependency closure;
// `braces` becomes a direct dependency of the workspace; `bun` exits
// unexpectedly or prints output that cannot be interpreted.
//
// Usage: node .github/scripts/frontend-next-audit.mjs
import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import { fileURLToPath, pathToFileURL } from "node:url";

/** The one admitted finding. Any drift from these values re-blocks the gate. */
export const ECCEZIONE = {
  advisory: "GHSA-vfj7-8cjw-p6xm",
  pacchetto: "braces",
  versione: "3.0.3",
  intervallo: "<=3.0.3",
  motivazione:
    "nessuna versione corretta e' pubblicata (3.0.3 e' l'ultima) e il pacchetto arriva solo da tooling di sviluppo",
};

// Edges followed when deciding whether a package is reachable at runtime. Peer
// and optional edges are included on purpose: counting a package as runtime by
// mistake closes the gate, missing one would open it.
const CAMPI_DIPENDENZE = ["dependencies", "optionalDependencies", "peerDependencies"];
const GHSA = /\/(GHSA-[0-9a-z-]+)$/;

/** Parses `bun.lock`, which is JSON with trailing commas. Fails closed. */
export const leggiLockfile = (testo) => {
  if (typeof testo !== "string" || testo.trim() === "") {
    throw new Error("bun.lock vuoto o illeggibile.");
  }
  try {
    return JSON.parse(testo.replace(/,(\s*[}\]])/g, "$1"));
  } catch (errore) {
    throw new Error(`bun.lock non interpretabile: ${errore.message}`);
  }
};

/** Splits a `name@version` lockfile spec; null when it is not one. */
export const nomeVersione = (spec) => {
  if (typeof spec !== "string") return null;
  const taglio = spec.lastIndexOf("@");
  if (taglio <= 0) return null;
  return { nome: spec.slice(0, taglio), versione: spec.slice(taglio + 1) };
};

const voceLock = (lock) => {
  const pacchetti = lock?.packages;
  if (pacchetti === null || typeof pacchetti !== "object" || Array.isArray(pacchetti)) {
    throw new Error("bun.lock senza mappa `packages`.");
  }
  return pacchetti;
};

/** Every version of `nome` present in the lockfile, deduplicated and sorted. */
export const versioniInstallate = (lock, nome) => {
  const versioni = new Set();
  for (const voce of Object.values(voceLock(lock))) {
    const spec = nomeVersione(Array.isArray(voce) ? voce[0] : null);
    if (spec?.nome === nome) versioni.add(spec.versione);
  }
  return [...versioni].sort();
};

/** Resolves the lockfile key a dependency edge points to, nearest scope first. */
const risolviChiave = (pacchetti, contesto, nome) => {
  let base = contesto;
  for (;;) {
    const chiave = base === "" ? nome : `${base}/${nome}`;
    if (Object.hasOwn(pacchetti, chiave)) return chiave;
    if (base === "") return null;
    const taglio = base.lastIndexOf("/");
    base = taglio === -1 ? "" : base.slice(0, taglio);
  }
};

/**
 * Names reachable from the workspace runtime `dependencies`. An edge that
 * cannot be resolved counts as reachable: an unreadable graph must not be the
 * reason an exception survives.
 */
export const chiusuraRuntime = (lock) => {
  const pacchetti = voceLock(lock);
  const radice = lock?.workspaces?.[""];
  if (radice === null || typeof radice !== "object" || Array.isArray(radice)) {
    throw new Error("bun.lock senza workspace radice.");
  }
  const nomi = new Set();
  const viste = new Set();
  const coda = Object.keys(radice.dependencies ?? {}).map((nome) => ({ nome, contesto: "" }));
  while (coda.length > 0) {
    const { nome, contesto } = coda.pop();
    const chiave = risolviChiave(pacchetti, contesto, nome);
    if (chiave === null) {
      nomi.add(nome);
      continue;
    }
    if (viste.has(chiave)) continue;
    viste.add(chiave);
    const voce = pacchetti[chiave];
    nomi.add(nomeVersione(Array.isArray(voce) ? voce[0] : null)?.nome ?? nome);
    const dipendenze = Array.isArray(voce) ? voce[2] : null;
    if (dipendenze === null || typeof dipendenze !== "object") continue;
    for (const campo of CAMPI_DIPENDENZE) {
      for (const dep of Object.keys(dipendenze[campo] ?? {})) coda.push({ nome: dep, contesto: chiave });
    }
  }
  return nomi;
};

/** Reads the advisory id out of the GitHub advisory URL `bun audit` reports. */
export const advisoryDaUrl = (url) => {
  if (typeof url !== "string") return null;
  return GHSA.exec(url)?.[1] ?? null;
};

const controllaAvviso = (pacchetto, avviso) => {
  if (avviso === null || typeof avviso !== "object" || Array.isArray(avviso)) {
    throw new Error(`Avviso non interpretabile per \`${pacchetto}\`: atteso un oggetto.`);
  }
  for (const campo of ["url", "title", "severity", "vulnerable_versions"]) {
    if (typeof avviso[campo] !== "string" || avviso[campo] === "") {
      throw new Error(`Avviso non interpretabile per \`${pacchetto}\`: campo \`${campo}\` mancante.`);
    }
  }
};

/** Why this finding is not the admitted exception. Empty means it is. */
const motiviDiBlocco = (pacchetto, avviso, { lock, manifest, runtime }) => {
  const motivi = [];
  const advisory = advisoryDaUrl(avviso.url);
  if (pacchetto !== ECCEZIONE.pacchetto) {
    motivi.push(`nessuna eccezione e' ammessa per \`${pacchetto}\``);
  }
  if (advisory !== ECCEZIONE.advisory) {
    motivi.push(`advisory ${advisory ?? avviso.url} diversa da ${ECCEZIONE.advisory}`);
  }
  if (avviso.vulnerable_versions !== ECCEZIONE.intervallo) {
    motivi.push(
      `intervallo vulnerabile \`${avviso.vulnerable_versions}\`, l'eccezione vale solo per \`${ECCEZIONE.intervallo}\``,
    );
  }
  if (motivi.length > 0) return motivi;

  const versioni = versioniInstallate(lock, pacchetto);
  if (versioni.length !== 1 || versioni[0] !== ECCEZIONE.versione) {
    motivi.push(
      `versione installata ${versioni.join(", ") || "assente"}, l'eccezione vale solo per la ${ECCEZIONE.versione}`,
    );
  }
  if (runtime.has(pacchetto)) {
    motivi.push("raggiungibile dalle dipendenze di runtime dell'applicazione");
  }
  const diretta = ["dependencies", "devDependencies", "optionalDependencies", "peerDependencies"].find(
    (campo) => Object.hasOwn(manifest?.[campo] ?? {}, pacchetto),
  );
  if (diretta !== undefined) {
    motivi.push(`dichiarata in \`${diretta}\` di package.json: l'eccezione vale solo per una transitiva di tooling`);
  }
  return motivi;
};

/**
 * Applies the policy to a parsed `bun audit --json` payload. Throws when the
 * payload, the lockfile or the manifest cannot be interpreted.
 */
export const valutaAudit = ({ audit, lock, manifest }) => {
  if (audit === null || typeof audit !== "object" || Array.isArray(audit)) {
    throw new Error("Output di `bun audit --json` non interpretabile: atteso un oggetto.");
  }
  const runtime = chiusuraRuntime(lock);
  const ammesse = [];
  const bloccanti = [];
  for (const [pacchetto, avvisi] of Object.entries(audit)) {
    if (!Array.isArray(avvisi) || avvisi.length === 0) {
      throw new Error(`Avvisi non interpretabili per \`${pacchetto}\`: atteso un elenco non vuoto.`);
    }
    for (const avviso of avvisi) {
      controllaAvviso(pacchetto, avviso);
      const motivi = motiviDiBlocco(pacchetto, avviso, { lock, manifest, runtime });
      if (motivi.length === 0) ammesse.push({ pacchetto, avviso });
      else bloccanti.push({ pacchetto, avviso, motivi });
    }
  }
  return { ok: bloccanti.length === 0, ammesse, bloccanti };
};

/** Runs `bun audit --json`. Only exit code 0 or 1 is a real audit answer. */
const eseguiAudit = (cartella) =>
  new Promise((risolvi, rifiuta) => {
    execFile(
      process.platform === "win32" ? "bun.exe" : "bun",
      ["audit", "--json"],
      { cwd: cartella, maxBuffer: 16 * 1024 * 1024 },
      (errore, stdout) => {
        const codice = errore?.code ?? 0;
        if (errore !== null && codice !== 1) {
          rifiuta(new Error(`\`bun audit --json\` non eseguibile o uscito con ${codice}: ${errore.message}`));
          return;
        }
        risolvi(stdout);
      },
    );
  });

export const main = async (cartella) => {
  const [lockTesto, manifestTesto, stdout] = await Promise.all([
    readFile(new URL("bun.lock", cartella), "utf8"),
    readFile(new URL("package.json", cartella), "utf8"),
    eseguiAudit(fileURLToPath(cartella)),
  ]);
  let audit;
  try {
    audit = JSON.parse(stdout.trim());
  } catch (errore) {
    throw new Error(`Output di \`bun audit --json\` non interpretabile: ${errore.message}`);
  }
  const esito = valutaAudit({ audit, lock: leggiLockfile(lockTesto), manifest: JSON.parse(manifestTesto) });

  for (const { pacchetto, avviso } of esito.ammesse) {
    console.log(
      `AMMESSA ${advisoryDaUrl(avviso.url)} su \`${pacchetto}\` ${ECCEZIONE.versione} (${avviso.severity}): ` +
        `${ECCEZIONE.motivazione}. Nessuna altra vulnerabilita' e' ammessa.`,
    );
  }
  for (const { pacchetto, avviso, motivi } of esito.bloccanti) {
    console.error(
      `::error::BLOCCANTE ${advisoryDaUrl(avviso.url) ?? avviso.url} su \`${pacchetto}\` ` +
        `(${avviso.severity}): ${motivi.join("; ")}.`,
    );
  }
  if (!esito.ok) {
    throw new Error(`${esito.bloccanti.length} vulnerabilita' bloccanti.`);
  }
  console.log(
    esito.ammesse.length === 0
      ? "Nessuna vulnerabilita'."
      : `${esito.ammesse.length} vulnerabilita' ammessa per nome, 0 bloccanti.`,
  );
};

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const cartella = new URL("../../frontend-next/", import.meta.url);
  main(cartella).catch((errore) => {
    console.error(`::error::${errore.message}`);
    process.exitCode = 1;
  });
}
