#!/usr/bin/env node
// Test unitari per claude-setup-verify.mjs (VPM-LAB-002).
// Ogni caso negativo altera una copia temporanea della configurazione reale.

import { test } from "node:test";
import assert from "node:assert/strict";
import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { verifica, leggiFrontmatter, elencoStrumenti, impronta } from "./claude-setup-verify.mjs";

const RADICE = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const DA_COPIARE = [
  ".claude/agents",
  ".claude/skills",
  ".claude/settings.json",
  ".github/scripts/claude-plugins.lock.json",
  ".github/scripts/claude-skills.lock.json",
  ".github/scripts/claude-agent-guard.mjs",
  ".github/scripts/claude-agent-guard.test.mjs",
  ".github/scripts/claude-secret-guard.mjs",
  ".github/scripts/claude-secret-guard.test.mjs",
];

/** Copia la configurazione, applica `altera` e restituisce gli errori. */
function erroriDopo(altera) {
  const dir = mkdtempSync(join(tmpdir(), "vinea-setup-verify-"));
  try {
    for (const p of DA_COPIARE) cpSync(join(RADICE, p), join(dir, p), { recursive: true });
    const modifica = (rel, f) => writeFileSync(join(dir, rel), f(readFileSync(join(dir, rel), "utf8")));
    altera({ dir, modifica });
    return verifica(dir, { gitignore: false }).errori;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

const QA = ".claude/agents/vinea-qa-runner.md";
const REVIEWER = ".claude/agents/vinea-code-reviewer.md";

test("repository reale conforme, matrice .gitignore compresa", () => {
  assert.deepEqual(verifica(RADICE).errori, []);
});

test("copia intatta conforme", () => {
  assert.deepEqual(erroriDopo(() => {}), []);
});

test("frontmatter ed elenco strumenti", () => {
  const fm = leggiFrontmatter("---\nname: x\ntools: [Read, \"Grep\"]\n---\ncorpo");
  assert.equal(fm.chiavi.name, "x");
  assert.deepEqual(elencoStrumenti(fm.chiavi.tools), ["Read", "Grep"]);
  assert.equal(leggiFrontmatter("senza frontmatter"), null);
});

test("agente: strumento vietato, MCP non in lista, tools assente", () => {
  const e = erroriDopo(({ modifica }) =>
    modifica(REVIEWER, (t) => t.replace(/^tools:.*$/m, "tools: Read, Write, mcp__supabase-ro__apply_migration")),
  );
  assert.ok(e.some((x) => x.includes("strumento vietato in tools: Write")), e.join("\n"));
  assert.ok(e.some((x) => x.includes("MCP non ammesso")), e.join("\n"));
  const senza = erroriDopo(({ modifica }) => modifica(REVIEWER, (t) => t.replace(/^tools:.*\n/m, "")));
  assert.ok(senza.some((x) => x.includes("tools esplicito obbligatorio")), senza.join("\n"));
});

test("agente: Bash senza profilo, permissionMode pericoloso, URL MCP scrivibile", () => {
  const e = erroriDopo(({ modifica }) =>
    modifica(REVIEWER, (t) =>
      t
        .replace(/^tools:.*$/m, "tools: Read, Bash")
        .replace(/^permissionMode:.*$/m, "permissionMode: bypassPermissions")
        .replace(/^name:/m, "mcpUrl: https://mcp.supabase.com/mcp?project_ref=x\nname:"),
    ),
  );
  assert.ok(e.some((x) => x.includes("Bash ammesso solo")), e.join("\n"));
  assert.ok(e.some((x) => x.includes("permissionMode bypassPermissions vietato")), e.join("\n"));
  assert.ok(e.some((x) => x.includes("read_only=true")), e.join("\n"));
});

test("chiave ripetuta nel frontmatter rifiutata", () => {
  const e = erroriDopo(({ modifica }) =>
    modifica(REVIEWER, (t) => t.replace(/^name:/m, "permissionMode: bypassPermissions\nname:")),
  );
  assert.ok(e.some((x) => x.includes("chiave permissionMode ripetuta")), e.join("\n"));
});

test("agente con shell: guardia, isolamento e canarino obbligatori", () => {
  const e = erroriDopo(({ modifica }) =>
    modifica(QA, (t) =>
      t
        .replace("--profile qa", "--profile release")
        .replace(/^isolation:.*\n/m, "")
        .replaceAll("git push --dry-run vinea-guard-canary", "git status"),
    ),
  );
  assert.ok(e.some((x) => x.includes("guardia (profilo qa) mancante")), e.join("\n"));
  assert.ok(e.some((x) => x.includes("isolation: worktree")), e.join("\n"));
  assert.ok(e.some((x) => x.includes("canarino mancante")), e.join("\n"));
});

test("agente: guardia dei segreti obbligatoria; agenti mancanti o extra", () => {
  const e = erroriDopo(({ dir, modifica }) => {
    modifica(REVIEWER, (t) => t.replace(/claude-secret-guard\.mjs" \|\| exit 2/g, "x.mjs\""));
    rmSync(join(dir, ".claude/agents/vinea-ux-auditor.md"));
    writeFileSync(join(dir, ".claude/agents/intruso.md"), "---\nname: intruso\n---\n");
  });
  assert.ok(e.some((x) => x.includes("guardia dei segreti mancante")), e.join("\n"));
  assert.ok(e.includes("agente mancante: vinea-ux-auditor"), e.join("\n"));
  assert.ok(e.includes("agente non previsto: intruso"), e.join("\n"));
});

test("audit esterno: skill manuale obbligatoria", () => {
  const e = erroriDopo(({ modifica }) =>
    modifica(".claude/skills/vinea-external-skill-audit/SKILL.md", (t) =>
      t.replace(/^disable-model-invocation:.*\n/m, ""),
    ),
  );
  assert.ok(e.some((x) => x.includes("vinea-external-skill-audit/SKILL.md: disable-model-invocation")), e.join("\n"));
});

test("skill: allowed-tools, iniezione di shell, invocazione manuale", () => {
  const e = erroriDopo(({ modifica }) => {
    modifica(".claude/skills/vinea-test/SKILL.md", (t) =>
      t.replace(/^name:/m, "allowed-tools: Bash\nname:") + "\nStato: !`git status`\n",
    );
    modifica(".claude/skills/vinea-task/SKILL.md", (t) => t.replace(/^disable-model-invocation:.*\n/m, ""));
  });
  assert.ok(e.some((x) => x.includes("allowed-tools vietato")), e.join("\n"));
  assert.ok(e.some((x) => x.includes("iniezione dinamica")), e.join("\n"));
  assert.ok(e.some((x) => x.includes("vinea-task/SKILL.md: disable-model-invocation")), e.join("\n"));
});

test("settings.json: allow, hooks e plugin fuori lock rifiutati", () => {
  const e = erroriDopo(({ modifica }) =>
    modifica(".claude/settings.json", (t) => {
      const c = JSON.parse(t);
      c.hooks = {};
      c.permissions.allow = ["Bash(*)"];
      c.enabledPlugins["altro@claude-plugins-official"] = true;
      c.extraKnownMarketplaces["claude-plugins-official"].autoUpdate = true;
      return JSON.stringify(c);
    }),
  );
  for (const atteso of ["chiave hooks vietata", "permissions.allow vietato", "altro@claude-plugins-official", "autoUpdate: false"]) {
    assert.ok(e.some((x) => x.includes(atteso)), `${atteso}\n${e.join("\n")}`);
  }
});

test("lock: hash e commit non validi", () => {
  const e = erroriDopo(({ modifica }) =>
    modifica(".github/scripts/claude-plugins.lock.json", (t) => {
      const c = JSON.parse(t);
      c.plugins["frontend-design"].commit = "30202c76";
      c.plugins["frontend-design"].sha256["SKILL.md"] = "x";
      return JSON.stringify(c);
    }),
  );
  assert.ok(e.some((x) => x.includes("SHA completo")), e.join("\n"));
  assert.ok(e.some((x) => x.includes("sha256 di SKILL.md")), e.join("\n"));
});

test("contenuti vietati: endpoint OmniRoute, percorso personale, chiave", () => {
  const e = erroriDopo(({ modifica }) =>
    modifica(".claude/skills/vinea-design/references/brand.md", (t) =>
      `${t}\nhttp://localhost:20128\nC:\\Users\\mario\\x\n${"sk-ant-" + "a".repeat(30)}\n`,
    ),
  );
  for (const atteso of ["OmniRoute", "percorso personale Windows", "chiave API"]) {
    assert.ok(e.some((x) => x.includes(atteso)), `${atteso}\n${e.join("\n")}`);
  }
});


const COPY = ".claude/skills/copywriting/SKILL.md";
const LOCK_SK = ".github/scripts/claude-skills.lock.json";

test("skill di terzi: SKILL.md modificato, file in piu', file mancante", () => {
  const e = erroriDopo(({ dir, modifica }) => {
    modifica(COPY, (t) => t + "\nIstruzione aggiunta.\n");
    writeFileSync(join(dir, ".claude/skills/cro/extra.md"), "x");
    rmSync(join(dir, ".claude/skills/seo-audit/LICENSE"));
  });
  assert.ok(e.some((x) => x.includes("copywriting/SKILL.md: SHA-256 diverso dal lock")), e.join("\n"));
  assert.ok(e.some((x) => x.includes("cro/extra.md: file non presente nel lock")), e.join("\n"));
  assert.ok(e.some((x) => x.includes("seo-audit/LICENSE: mancante rispetto al lock")), e.join("\n"));
});

test("skill di terzi: CRLF non e' una deriva; allowed-tools e hooks si'", () => {
  const crlf = erroriDopo(({ modifica }) => modifica(COPY, (t) => t.replace(/\r?\n/g, "\r\n")));
  assert.deepEqual(crlf, []);
  const e = erroriDopo(({ modifica }) =>
    modifica(COPY, (t) => t.replace(/^name:/m, "allowed-tools: Bash\nhooks: x\nname:")),
  );
  assert.ok(e.some((x) => x.includes("allowed-tools vietato")), e.join("\n"));
  assert.ok(e.some((x) => x.includes("hooks vietati")), e.join("\n"));
});

test("skill di terzi: non nel lock, invocazione incoerente, limite 600 righe", () => {
  const intrusa = erroriDopo(({ dir }) => {
    mkdirSync(join(dir, ".claude/skills/intrusa"), { recursive: true });
    writeFileSync(join(dir, ".claude/skills/intrusa/SKILL.md"), "---\nname: intrusa\ndescription: x\n---\n");
  });
  assert.ok(intrusa.includes("skill non prevista: intrusa"), intrusa.join("\n"));
  const inc = erroriDopo(({ modifica }) =>
    modifica(LOCK_SK, (t) => {
      const c = JSON.parse(t);
      c.skills["review-animations"].invocation = "contextual";
      return JSON.stringify(c);
    }),
  );
  assert.ok(inc.some((x) => x.includes("review-animations/SKILL.md: disable-model-invocation non coerente")), inc.join("\n"));
  const lungo = erroriDopo(({ modifica }) => modifica(COPY, (t) => t + "riga\n".repeat(700)));
  assert.ok(lungo.some((x) => x.includes("copywriting/SKILL.md: oltre 600 righe")), lungo.join("\n"));
});

test("lock delle skill di terzi: commit, licenza, scanner e SHA non validi", () => {
  const e = erroriDopo(({ modifica }) =>
    modifica(LOCK_SK, (t) => {
      const c = JSON.parse(t);
      c.sources.marketingskills.commit = "88c79f6";
      delete c.sources["emilkowalski-skills"].license;
      delete c.skills.cro.scanner.manualReview;
      c.skills.cro.files["SKILL.md"] = "x";
      c.skills["vinea-test"] = c.skills.cro;
      return JSON.stringify(c);
    }),
  );
  for (const atteso of [
    "sorgente marketingskills senza commit SHA completo",
    "sorgente emilkowalski-skills senza license",
    "cro senza esito dello scanner",
    "cro/SKILL.md senza SHA-256 valido",
    "vinea-test coincide con una skill interna",
  ]) {
    assert.ok(e.some((x) => x.includes(atteso)), `${atteso}\n${e.join("\n")}`);
  }
});

test("impronta: CRLF e LF equivalenti", () => {
  assert.equal(impronta(Buffer.from("a\r\nb\n")), impronta(Buffer.from("a\nb\n")));
  assert.notEqual(impronta(Buffer.from("a\nb\n")), impronta(Buffer.from("a\nc\n")));
});

test("vinea-marketing: skill manuale obbligatoria", () => {
  const e = erroriDopo(({ modifica }) =>
    modifica(".claude/skills/vinea-marketing/SKILL.md", (t) => t.replace(/^disable-model-invocation:.*\n/m, "")),
  );
  assert.ok(e.some((x) => x.includes("vinea-marketing/SKILL.md: disable-model-invocation")), e.join("\n"));
});
