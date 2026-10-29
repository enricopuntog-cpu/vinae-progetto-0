#!/usr/bin/env node
// Test unitari per claude-bootstrap.mjs (VPM-LAB-002).
// La CLI `claude` e' sostituita da un esecutore finto: nessuna rete, nessuna
// installazione, nessuna directory di configurazione reale.

import { test } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  MESSAGGIO_DERIVA,
  PERCORSO_LOCK,
  controlla,
  installa,
  leggiArgomenti,
  leggiVersione,
  versioneAlmeno,
} from "./claude-bootstrap.mjs";

const sha = (t) => createHash("sha256").update(t).digest("hex");
const SKILL = "contenuto della skill\n";
const LICENZA = "Apache License 2.0\n";
const LOCK = {
  plugins: {
    "frontend-design": {
      marketplace: "claude-plugins-official",
      repo: "anthropics/claude-plugins-official",
      path: "plugins/frontend-design",
      commit: "0".repeat(40),
      version: "1.1.1",
      sha256: { "SKILL.md": sha(SKILL), "LICENSE.txt": sha(LICENZA) },
    },
  },
};

function scriviPlugin(dir, { skill = SKILL, versione = "1.1.1" } = {}) {
  mkdirSync(join(dir, ".claude-plugin"), { recursive: true });
  mkdirSync(join(dir, "skills", "frontend-design"), { recursive: true });
  writeFileSync(join(dir, ".claude-plugin", "plugin.json"), JSON.stringify({ version: versione }));
  writeFileSync(join(dir, "skills", "frontend-design", "SKILL.md"), skill);
  writeFileSync(join(dir, "skills", "frontend-design", "LICENSE.txt"), LICENZA);
}

/** Directory di configurazione finta, con marketplace e plugin facoltativi. */
function ambiente(t, { marketplace = true, plugin = true, skill, versione, repo, cache } = {}) {
  const config = mkdtempSync(join(tmpdir(), "vinea-bootstrap-"));
  t.after(() => rmSync(config, { recursive: true, force: true }));
  const mkt = join(config, "plugins", "marketplaces", "claude-plugins-official");
  const stato = { marketplace, plugin, chiamate: [] };
  if (plugin) scriviPlugin(join(mkt, "plugins", "frontend-design"), { skill, versione });
  if (cache) scriviPlugin(join(config, "plugins", "cache", "claude-plugins-official", "frontend-design", "1.1.1"), cache);
  const esegui = (args, dir) => {
    assert.equal(dir, config);
    stato.chiamate.push(args.join(" "));
    const ok = (out) => ({ status: 0, stdout: JSON.stringify(out), stderr: "" });
    switch (args.join(" ")) {
      case "--version":
        return { status: 0, stdout: stato.versioneCli ?? "2.1.312 (Claude Code)\n", stderr: "" };
      case "plugin marketplace list --json":
        return ok(
          stato.marketplace
            ? [{ name: "claude-plugins-official", repo: repo ?? LOCK.plugins["frontend-design"].repo, installLocation: mkt }]
            : [],
        );
      case "plugin list --json":
        return ok([]);
      case "plugin marketplace add anthropics/claude-plugins-official":
        stato.marketplace = true;
        return ok({});
      case "plugin install frontend-design@claude-plugins-official --scope project":
        scriviPlugin(join(mkt, "plugins", "frontend-design"));
        return ok({});
      default:
        return { status: 1, stdout: "", stderr: `comando inatteso: ${args.join(" ")}` };
    }
  };
  return { config, esegui, stato };
}

const SCRITTURE = /marketplace add|plugin install/;

test("argomenti: default, ripetizione di --config-dir, errori", () => {
  const def = leggiArgomenti([], { CLAUDE_CONFIG_DIR: "/tmp/profilo" });
  assert.equal(def.modo, "check");
  assert.equal(def.dirs.length, 1);
  const due = leggiArgomenti(["--install", "--config-dir", "a", "--config-dir", "b"], {});
  assert.equal(due.modo, "install");
  assert.equal(due.dirs.length, 2);
  assert.throws(() => leggiArgomenti(["--config-dir"], {}), /richiede/);
  assert.throws(() => leggiArgomenti(["--yes"], {}), /sconosciuta/);
});

test("versione minima di Claude Code", () => {
  assert.deepEqual(leggiVersione("2.1.312 (Claude Code)"), [2, 1, 312]);
  assert.equal(leggiVersione("boh"), null);
  assert.equal(versioneAlmeno([2, 1, 277], "2.1.277"), true);
  assert.equal(versioneAlmeno([2, 1, 276], "2.1.277"), false);
  assert.equal(versioneAlmeno([3, 0, 0], "2.1.277"), true);
});

test("check conforme: OK, nessuna scrittura, ripetibile", (t) => {
  const { config, esegui, stato } = ambiente(t, { cache: {} });
  const a = controlla(config, LOCK, esegui);
  const b = controlla(config, LOCK, esegui);
  assert.equal(a.stato, "ok", a.messaggi.join("\n"));
  assert.deepEqual(a, b);
  assert.ok(a.messaggi.some((m) => m.includes("2 copie")));
  assert.ok(!stato.chiamate.some((c) => SCRITTURE.test(c)));
});

test("Claude Code troppo vecchio: errore prima di ogni altro controllo", (t) => {
  const { config, esegui, stato } = ambiente(t);
  stato.versioneCli = "2.1.276 (Claude Code)";
  const r = controlla(config, LOCK, esegui);
  assert.equal(r.stato, "errore");
  assert.deepEqual(stato.chiamate, ["--version"]);
});

test("deriva nel marketplace o nella cache: codice di deriva, nessuna installazione", (t) => {
  for (const opzioni of [{ skill: "alterata\n" }, { versione: "1.2.0" }, { cache: { skill: "alterata\n" } }]) {
    const { config, esegui, stato } = ambiente(t, opzioni);
    const r = installa(config, LOCK, esegui);
    assert.equal(r.stato, "deriva", JSON.stringify(opzioni));
    assert.ok(r.messaggi.includes(MESSAGGIO_DERIVA));
    assert.ok(!stato.chiamate.some((c) => SCRITTURE.test(c)));
  }
});

test("marketplace con lo stesso nome ma un altro repository: errore", (t) => {
  const { config, esegui, stato } = ambiente(t, { repo: "intruso/plugins" });
  assert.equal(installa(config, LOCK, esegui).stato, "errore");
  assert.ok(!stato.chiamate.some((c) => SCRITTURE.test(c)));
});

test("check con marketplace assente: mancante, nessuna scrittura", (t) => {
  const { config, esegui, stato } = ambiente(t, { marketplace: false, plugin: false });
  assert.equal(controlla(config, LOCK, esegui).stato, "mancante");
  assert.ok(!stato.chiamate.some((c) => SCRITTURE.test(c)));
});

test("install: aggiunge solo il marketplace ufficiale e il plugin, poi e' idempotente", (t) => {
  const { config, esegui, stato } = ambiente(t, { marketplace: false, plugin: false });
  const r = installa(config, LOCK, esegui);
  assert.equal(r.stato, "ok", r.messaggi.join("\n"));
  const scritture = stato.chiamate.filter((c) => SCRITTURE.test(c));
  assert.deepEqual(scritture, [
    "plugin marketplace add anthropics/claude-plugins-official",
    "plugin install frontend-design@claude-plugins-official --scope project",
  ]);
  assert.ok(!stato.chiamate.some((c) => c.includes("--yes")));
  stato.chiamate.length = 0;
  assert.equal(installa(config, LOCK, esegui).stato, "ok");
  assert.ok(!stato.chiamate.some((c) => SCRITTURE.test(c)));
});

test("il lock versionato ha la forma attesa dal bootstrap", () => {
  const lock = JSON.parse(readFileSync(PERCORSO_LOCK, "utf8"));
  const voce = lock.plugins["frontend-design"];
  assert.equal(voce.marketplace, "claude-plugins-official");
  assert.equal(voce.path, "plugins/frontend-design");
  assert.match(voce.sha256["SKILL.md"], /^[0-9a-f]{64}$/);
});
