// Regole di sicurezza di tutti i workflow (VPM-018-SEC-CI-01). Gira nel job
// `Continuity scripts - syntax`, gia' richiesto dal ruleset di `main`: un'Action a
// tag mobile o un permesso largo blocca il merge anche se chi lo introduce non
// tocca i workflow di sicurezza.
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const radice = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const cartella = resolve(radice, ".github/workflows");
const workflow = readdirSync(cartella)
  .filter((f) => f.endsWith(".yml") || f.endsWith(".yaml"))
  .map((nome) => ({ nome, testo: readFileSync(resolve(cartella, nome), "utf8") }));

const righeSenzaCommenti = (testo) => testo.split(/\r?\n/).filter((r) => !r.trim().startsWith("#"));

// Pure, esportate per la prova inversa qui sotto.
export function usesNonFissati(testo) {
  return righeSenzaCommenti(testo)
    .map((r) => r.match(/^\s*(?:-\s*)?uses:\s*(\S+)/)?.[1])
    .filter(Boolean)
    .filter((u) => !u.startsWith("./") && !/@[0-9a-f]{40}$/.test(u));
}

export function checkoutSenzaPersistCredentialsFalse(testo) {
  const righe = righeSenzaCommenti(testo);
  const trovati = [];
  righe.forEach((r, i) => {
    if (!/^\s*(?:-\s*)?uses:\s*actions\/checkout@/.test(r)) return;
    const indent = r.search(/\S/);
    let ok = false;
    for (let j = i + 1; j < righe.length; j++) {
      const s = righe[j];
      if (s.trim() === "") continue;
      if (s.search(/\S/) <= indent && !s.trim().startsWith("with:")) break;
      if (/^\s*persist-credentials:\s*false\s*$/.test(s)) ok = true;
    }
    if (!ok) trovati.push(i);
  });
  return trovati;
}

export function haPermessiDiPrimoLivello(testo) {
  return /^permissions:\s*$/m.test(testo);
}

test("ci sono workflow da controllare", () => {
  assert.ok(workflow.length >= 7);
});

for (const { nome, testo } of workflow) {
  test(`${nome}: ogni Action e' fissata a uno SHA completo`, () => {
    assert.deepEqual(usesNonFissati(testo), []);
  });

  test(`${nome}: permessi espliciti al primo livello, mai larghi`, () => {
    assert.ok(haPermessiDiPrimoLivello(testo), "manca permissions al primo livello");
    assert.doesNotMatch(testo, /permissions:\s*write-all/);
    assert.doesNotMatch(testo, /^permissions:\s*\r?\n\s+contents:\s*write/m);
  });

  test(`${nome}: nessun trigger con codice di PR nel contesto di main`, () => {
    const righe = righeSenzaCommenti(testo);
    assert.ok(!righe.some((r) => /pull_request_target/.test(r)));
    // `workflow_run` gira nel contesto di main: ammesso solo dove non esegue codice
    // di una PR (il controllo di freschezza, legato al solo workflow di backup).
    if (nome !== "offsite-backup-freshness.yml") {
      assert.ok(!righe.some((r) => /^\s*workflow_run:/.test(r)));
    }
  });

  test(`${nome}: il checkout non lascia il token nel repository`, () => {
    assert.deepEqual(checkoutSenzaPersistCredentialsFalse(testo), []);
  });
}

test("solo il job CodeQL puo' scrivere gli eventi di sicurezza", () => {
  const conScrittura = workflow.filter((w) => /security-events:\s*write/.test(w.testo)).map((w) => w.nome);
  assert.deepEqual(conScrittura, ["security-scan.yml"]);
});

test("le regole rifiutano davvero le forme sbagliate", () => {
  assert.deepEqual(usesNonFissati("    - uses: actions/checkout@v7\n"), ["actions/checkout@v7"]);
  assert.deepEqual(usesNonFissati("    - uses: evil/action@main\n"), ["evil/action@main"]);
  assert.deepEqual(usesNonFissati(`    - uses: a/b@${"a".repeat(40)} # v1\n`), []);
  assert.deepEqual(usesNonFissati("    - uses: ./locale\n"), []);
  assert.equal(haPermessiDiPrimoLivello("on: push\njobs: {}\n"), false);
  const senza = "      - uses: actions/checkout@abc\n        with:\n          fetch-depth: 0\n      - run: x\n";
  assert.equal(checkoutSenzaPersistCredentialsFalse(senza).length, 1);
  const con = "      - uses: actions/checkout@abc\n        with:\n          persist-credentials: false\n";
  assert.equal(checkoutSenzaPersistCredentialsFalse(con).length, 0);
});
