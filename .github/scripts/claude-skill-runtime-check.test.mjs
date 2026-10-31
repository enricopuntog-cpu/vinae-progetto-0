// Test offline del classificatore di claude-skill-runtime-check.mjs: nessuna chiamata
// al modello, nessuna rete, nessuna credenziale. Verifica che un esito OK richieda
// una prova strutturale e che i fallimenti restino distinti.
import assert from "node:assert/strict";
import test from "node:test";
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { BUDGET_MAX_USD, COMANDO_SICURO, PROVE, argomenti, SKILL_MARKETING, classifica, eventi, espansioneComando, leggiTrascrizione, stessoNome } from "./claude-skill-runtime-check.mjs";

const init = (skills) => ({ type: "system", subtype: "init", skills });
const usoSkill = (skill) => ({ type: "assistant", message: { content: [{ type: "tool_use", name: "Skill", input: { skill } }] } });
const risultato = (extra = {}) => ({ type: "result", is_error: false, num_turns: 3, total_cost_usd: 0.2, usage: { output_tokens: 90 }, result: "fatto", ...extra });
const prova = (skill) => PROVE.find((p) => p.skill === skill);

test("OK: skill elencata e richiamata con nome esatto", () => {
  const r = classifica(prova("cro"), [init(["cro"]), usoSkill("cro"), risultato()]);
  assert.equal(r.esito, "OK");
});

test("OK: nome con prefisso di plugin", () => {
  assert.equal(stessoNome("miei-plugin:cro", "cro"), true);
  assert.equal(stessoNome("cro-extra", "cro"), false);
});

test("il solo nome nel testo non e' una invocazione", () => {
  const ev = [init(["cro"]), { type: "assistant", message: { content: [{ type: "text", text: "uso la skill cro" }] } }, risultato()];
  assert.equal(classifica(prova("cro"), ev).esito, "KO (non richiamata)");
});

test("una skill con nome simile non conta", () => {
  assert.equal(classifica(prova("cro"), [init(["cro"]), usoSkill("cro-extra"), risultato()]).esito, "KO (non richiamata)");
});

test("KO se la skill non e' nell'evento init", () => {
  assert.equal(classifica(prova("cro"), [init(["copywriting"]), usoSkill("cro"), risultato()]).esito, "KO (non elencata)");
});

test("scadenza OAuth e' NON VERIFICATO, mai OK ne' KO", () => {
  const ev = [init(["cro"]), risultato({ is_error: true, total_cost_usd: 0, usage: { output_tokens: 0 }, terminal_reason: "api_error", result: "Failed to authenticate: OAuth session expired" })];
  assert.equal(classifica(prova("cro"), ev).esito, "NON VERIFICATO (autenticazione)");
});

test("nessun evento con 401 su stderr e' NON VERIFICATO (autenticazione)", () => {
  assert.equal(classifica(prova("cro"), [], null, "API Error: 401 Unauthorized").esito, "NON VERIFICATO (autenticazione)");
});

test("nessun evento senza segni di autenticazione e' NON VERIFICATO (non avviata)", () => {
  assert.equal(classifica(prova("cro"), []).esito, "NON VERIFICATO (non avviata)");
});

test("errore API con costo e token e' KO, non autenticazione", () => {
  const ev = [init(["cro"]), risultato({ is_error: true, result: "overloaded" })];
  assert.equal(classifica(prova("cro"), ev).esito, "KO (errore API)");
});

test("errore API prima del primo token, senza segni di login, resta KO (errore API)", () => {
  const ev = [init(["cro"]), risultato({ is_error: true, total_cost_usd: 0, usage: { output_tokens: 0 }, terminal_reason: "api_error", result: "API Error: 529 overloaded_error" })];
  assert.equal(classifica(prova("cro"), ev).esito, "KO (errore API)");
});

test("tetto di spesa o di turni e' KO (limite), non errore API", () => {
  const ev = [init(["cro"]), usoSkill("cro"), risultato({ subtype: "error_max_budget_usd", is_error: true })];
  const r = classifica(prova("cro"), ev);
  assert.equal(r.esito, "KO (limite)");
  assert.equal(r.limite, "error_max_budget_usd");
  assert.deepEqual(r.skillRichiamate, ["cro"]);
});

test("skill manuale: un percorso nel risultato di uno strumento non e' una invocazione", () => {
  const glob = { type: "user", message: { content: [{ type: "tool_result", content: "C:/repo/.claude/skills/review-animations/SKILL.md" }] } };
  assert.equal(classifica(prova("review-animations"), [init(["review-animations"]), glob, risultato()]).esito, "KO (non richiamata)");
});

const SID = "0804dab3-c36a-4a6a-a13b-68a71c4d020f";

test("skill manuale: comando come argomento posizionale subito dopo -p, sessione con id noto", () => {
  const a = argomenti(prova("review-animations"), 0.5, SID);
  assert.equal(a[0], "-p");
  assert.equal(a[1], prova("review-animations").prompt);
  assert.equal(a[a.indexOf("--session-id") + 1], SID);
  assert.equal(a.includes("--no-session-persistence"), false);
  assert.throws(() => argomenti(prova("review-animations"), 0.5));
});

test("skill contestuale: nessun argomento posizionale (prompt su stdin) e nessuna sessione salvata", () => {
  const a = argomenti(prova("cro"), 0.5);
  assert.equal(a.includes(prova("cro").prompt), false);
  assert.equal(a[1], "--output-format");
  assert.ok(a.includes("--no-session-persistence"));
});

test("i comandi manuali sono nella forma ristretta, sicura per la shell", () => {
  for (const p of PROVE.filter((x) => x.manuale)) assert.match(p.prompt, COMANDO_SICURO);
  assert.doesNotMatch('/x "a" & del', COMANDO_SICURO);
  assert.throws(() => argomenti({ skill: "x", manuale: true, prompt: "/x a&b" }, 0.5, SID));
});

test("trascrizione: espansione letta dai messaggi utente, file cancellato", () => {
  const dir = mkdtempSync(join(tmpdir(), "vinea-trascr-"));
  try {
    const cartella = join(dir, "projects", "C--repo");
    mkdirSync(cartella, { recursive: true });
    const file = join(cartella, `${SID}.jsonl`);
    const righe = [
      { type: "user", message: { content: "<command-message>review-animations</command-message>\n<command-name>/review-animations</command-name>" } },
      { type: "user", isMeta: true, message: { content: [{ type: "text", text: "Base directory for this skill: C:\\repo\\.claude\\skills\\review-animations" }] } },
      { type: "assistant", message: { content: [{ type: "text", text: "risposta" }] } },
    ];
    writeFileSync(file, righe.map((r) => JSON.stringify(r)).join("\n"));
    const ev = leggiTrascrizione(SID, dir);
    assert.equal(ev.length, 2);
    assert.equal(existsSync(file), false);
    assert.equal(classifica(prova("review-animations"), [init(["review-animations"]), risultato(), ...ev]).esito, "OK");
    assert.deepEqual(leggiTrascrizione(SID, dir), []);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("trascrizione: prompt slash non espanso non e' una invocazione", () => {
  const nonEspanso = { type: "user", message: { content: "/review-animations frontend-next/src/components/ui/dialog.tsx" } };
  assert.equal(classifica(prova("review-animations"), [init(["review-animations"]), risultato(), nonEspanso]).esito, "KO (non richiamata)");
});

test("il tetto di spesa per prova non supera 0,50 USD", () => {
  assert.equal(BUDGET_MAX_USD, 0.5);
});

test("timeout forzato e' KO (timeout)", () => {
  assert.equal(classifica(prova("cro"), [init(["cro"])], "timeout").esito, "KO (timeout)");
});

test("skill manuale: serve l'espansione del comando con la cartella della skill", () => {
  const espanso = { type: "user", message: { content: [{ type: "text", text: "Base directory for this skill: C:/repo/.claude/skills/review-animations" }] } };
  assert.equal(classifica(prova("review-animations"), [init(["review-animations"]), espanso, risultato()]).esito, "OK");
  assert.equal(classifica(prova("review-animations"), [init(["review-animations"]), risultato()]).esito, "KO (non richiamata)");
  assert.equal(espansioneComando([espanso], "review-animations"), true);
  assert.equal(espansioneComando([espanso], "vinea-marketing"), false);
});

test("skill manuale: anche lo strumento Skill vale", () => {
  assert.equal(classifica(prova("vinea-marketing"), [init(["vinea-marketing"]), usoSkill("vinea-marketing"), risultato()]).esito, "OK");
});

test("prova negativa: OK se nessuna skill di marketing parte", () => {
  const r = classifica(prova("negativo"), [init(SKILL_MARKETING), usoSkill("vinea-test"), risultato()]);
  assert.equal(r.esito, "OK");
});

test("prova negativa: interferenza se parte una skill di marketing", () => {
  const r = classifica(prova("negativo"), [init(SKILL_MARKETING), usoSkill("copywriting"), risultato()]);
  assert.equal(r.esito, "KO (interferenza)");
  assert.deepEqual(r.skillVietateRichiamate, ["copywriting"]);
});

test("eventi ignora righe non JSON", () => {
  assert.equal(eventi('rumore\n{"type":"result"}\n\n{rotto').length, 1);
});

test("le nove skill e la prova negativa sono tutte previste", () => {
  assert.deepEqual(
    PROVE.map((p) => p.skill).sort(),
    ["animation-performance", "copywriting", "cro", "negativo", "product-marketing", "review-animations", "seo-audit", "supabase-postgres-best-practices", "vinea-browser-qa", "vinea-marketing"],
  );
  for (const p of PROVE) assert.ok(p.prompt.length > 20);
});
