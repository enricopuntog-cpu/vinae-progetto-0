#!/usr/bin/env node
// Test unitari per claude-agent-guard.mjs
// VPM-LAB-002: profili `qa` e `release`.

import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { valuta, valutaEvento } from "./claude-agent-guard.mjs";

test("qa: git status ammesso", () => {
  assert.equal(valuta("qa", "git status"), null);
});

test("qa: git diff ammesso", () => {
  assert.equal(valuta("qa", "git diff"), null);
});

test("qa: git log ammesso", () => {
  assert.equal(valuta("qa", "git log --oneline -10"), null);
});

test("qa: git show ammesso", () => {
  assert.equal(valuta("qa", "git show HEAD"), null);
});

test("qa: git rev-parse ammesso", () => {
  assert.equal(valuta("qa", "git rev-parse HEAD"), null);
});

test("qa: git fetch origin ammesso", () => {
  assert.equal(valuta("qa", "git fetch origin"), null);
});

test("qa: git fetch origin main ammesso", () => {
  assert.equal(valuta("qa", "git fetch origin main"), null);
});

test("qa: git checkout --detach <sha> ammesso", () => {
  assert.equal(valuta("qa", "git checkout --detach abc1234"), null);
});

test("qa: git checkout --detach origin/main ammesso", () => {
  assert.equal(valuta("qa", "git checkout --detach origin/main"), null);
});

test("qa: git push rifiutato", () => {
  assert.notEqual(valuta("qa", "git push"), null);
});

test("qa: git commit rifiutato", () => {
  assert.notEqual(valuta("qa", "git commit -m test"), null);
});

test("qa: bun install --frozen-lockfile ammesso", () => {
  assert.equal(valuta("qa", "bun --cwd frontend install --frozen-lockfile"), null);
});

test("qa: bun run lint ammesso", () => {
  assert.equal(valuta("qa", "bun --cwd frontend-next run lint"), null);
});

test("qa: bun run typecheck ammesso", () => {
  assert.equal(valuta("qa", "bun --cwd frontend-next run typecheck"), null);
});

test("qa: bun run test ammesso", () => {
  assert.equal(valuta("qa", "bun --cwd frontend run test"), null);
});

test("qa: bun run build ammesso", () => {
  assert.equal(valuta("qa", "bun --cwd frontend-next run build"), null);
});

test("qa: bun --cwd backend rifiutato", () => {
  assert.notEqual(valuta("qa", "bun --cwd backend install"), null);
});

test("qa: python -m pytest ammesso", () => {
  assert.equal(valuta("qa", "python -m pytest -q tests/"), null);
});

test("qa: pytest fuori da tests/ rifiutato", () => {
  assert.notEqual(valuta("qa", "python -m pytest tests/../../x"), null);
  assert.notEqual(valuta("qa", "python -m pytest --rootdir=/"), null);
});

test("qa: canarino bloccato", () => {
  assert.notEqual(valuta("qa", "git push --dry-run vinea-guard-canary"), null);
  assert.notEqual(valuta("release", "git push --dry-run vinea-guard-canary"), null);
});

test("qa: opzioni globali e prefissi d'ambiente rifiutati", () => {
  assert.notEqual(valuta("qa", "git -C . push"), null);
  assert.notEqual(valuta("qa", "GIT_DIR=x git status"), null);
  assert.notEqual(valuta("qa", "git log -p --ext-diff"), null);
  assert.notEqual(valuta("qa", "git fetch origin --upload-pack=x"), null);
});

test("qa: python -m ruff check ammesso", () => {
  assert.equal(valuta("qa", "python -m ruff check ."), null);
});

test("qa: python -m compileall ammesso", () => {
  assert.equal(valuta("qa", "python -m compileall -q ."), null);
});

test("qa: python -c rifiuto", () => {
  assert.notEqual(valuta("qa", "python -c \"print(1)\""), null);
});

test("qa: node --test ammesso", () => {
  assert.equal(valuta("qa", "node --test .github/scripts/foo.test.mjs"), null);
});

test("qa: node --test multi ammesso", () => {
  assert.equal(valuta("qa", "node --test .github/scripts/a.test.mjs .github/scripts/b.test.mjs"), null);
});

test("qa: node altri rifiuto", () => {
  assert.notEqual(valuta("qa", "node script.js"), null);
});

test("qa: cd ammesso", () => {
  assert.equal(valuta("qa", "cd frontend"), null);
  assert.equal(valuta("qa", "cd frontend-next"), null);
  assert.equal(valuta("qa", "cd backend"), null);
  assert.equal(valuta("qa", "cd .."), null);
});

test("qa: cd altro rifiutato", () => {
  assert.notEqual(valuta("qa", "cd /tmp"), null);
});

test("qa: metacaratteri rifiutati", () => {
  assert.notEqual(valuta("qa", "git status; rm -rf /"), null);
  assert.notEqual(valuta("qa", "git status && ls"), null);
  assert.notEqual(valuta("qa", "git status | cat"), null);
  assert.notEqual(valuta("qa", "git status $(echo)"), null);
  assert.notEqual(valuta("qa", "git status `echo`"), null);
  assert.notEqual(valuta("qa", "git status > out"), null);
  assert.notEqual(valuta("qa", "git status < in"), null);
});

test("qa: profilo sconosciuto", () => {
  assert.notEqual(valuta("altro", "git status"), null);
});

test("qa: comando vuoto", () => {
  assert.notEqual(valuta("qa", ""), null);
});

test("release: git ammesso", () => {
  assert.equal(valuta("release", "git status"), null);
  assert.equal(valuta("release", "git fetch origin"), null);
  assert.equal(valuta("release", "git checkout --detach origin/main"), null);
});

test("release: gh pr view/checks/diff/list ammessi", () => {
  assert.equal(valuta("release", "gh pr view 123"), null);
  assert.equal(valuta("release", "gh pr checks 123"), null);
  assert.equal(valuta("release", "gh pr diff 123"), null);
  assert.equal(valuta("release", "gh pr list"), null);
});

test("release: gh run view/list ammessi", () => {
  assert.equal(valuta("release", "gh run view 123"), null);
  assert.equal(valuta("release", "gh run list"), null);
});

test("release: gh api GET ammesso", () => {
  assert.equal(valuta("release", "gh api repos/owner/repo"), null);
  assert.equal(valuta("release", "gh api /repos/owner/repo/pulls/123"), null);
});

test("release: gh api POST rifiutato", () => {
  assert.notEqual(valuta("release", "gh api repos/owner/repo -X POST"), null);
  assert.notEqual(valuta("release", "gh api repos/owner/repo --method POST"), null);
  assert.notEqual(valuta("release", "gh api repos/owner/repo -f a=b"), null);
  assert.notEqual(valuta("release", "gh api repos/owner/repo -F file=@f"), null);
  assert.notEqual(valuta("release", "gh api repos/owner/repo --input @f"), null);
});

test("release: gh pr merge/checkout/close rifiutati", () => {
  assert.notEqual(valuta("release", "gh pr merge 123"), null);
  assert.notEqual(valuta("release", "gh pr checkout 123"), null);
  assert.notEqual(valuta("release", "gh pr close 123"), null);
});

test("release: metacaratteri rifiutati", () => {
  assert.notEqual(valuta("release", "gh pr view 123; ls"), null);
});

test("evento PreToolUse: qa con Bash ammesso", () => {
  const ev = { tool_name: "Bash", tool_input: { command: "git status" } };
  assert.equal(valutaEvento("qa", ev), null);
});

test("evento PreToolUse: qa con PowerShell rifiutato", () => {
  const ev = { tool_name: "PowerShell", tool_input: { command: "git status" } };
  assert.notEqual(valutaEvento("qa", ev), null);
});

test("evento PreToolUse: release con gh api POST rifiutato", () => {
  const ev = { tool_name: "Bash", tool_input: { command: "gh api repos/x/y -X POST" } };
  assert.notEqual(valutaEvento("release", ev), null);
});

test("evento PreToolUse: json illeggibile", () => {
  assert.notEqual(valutaEvento("qa", null), null);
  assert.notEqual(valutaEvento("qa", "not an object"), null);
});
// Processo reale, come lo lancia l'hook: stdin JSON, codice 2 e prefisso.
const SCRIPT = fileURLToPath(new URL("./claude-agent-guard.mjs", import.meta.url));

function lancia(argv, input) {
  return spawnSync(process.execPath, [SCRIPT, ...argv], { input, encoding: "utf8" });
}

test("cli: canarino bloccato con codice 2 e VINEA-GUARD", () => {
  const r = lancia(
    ["--profile", "qa"],
    JSON.stringify({ tool_name: "Bash", tool_input: { command: "git push --dry-run vinea-guard-canary" } }),
  );
  assert.equal(r.status, 2);
  assert.match(r.stderr, /^VINEA-GUARD: bloccato/);
});

test("cli: comando ammesso esce con 0", () => {
  const r = lancia(["--profile", "release"], JSON.stringify({ tool_name: "Bash", tool_input: { command: "git status" } }));
  assert.equal(r.status, 0);
});

test("cli: stdin illeggibile o profilo assente esce con 2", () => {
  assert.equal(lancia(["--profile", "qa"], "{rotto").status, 2);
  assert.equal(lancia([], JSON.stringify({ tool_name: "Bash", tool_input: { command: "git status" } })).status, 2);
});
