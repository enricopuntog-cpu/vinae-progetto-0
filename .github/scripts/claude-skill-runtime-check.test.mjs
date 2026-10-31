// Test offline del classificatore di claude-skill-runtime-check.mjs: nessuna chiamata
// al modello, nessuna rete, nessuna credenziale. Verifica che un esito OK richieda
// una prova strutturale e che i fallimenti restino distinti.
import assert from "node:assert/strict";
import test from "node:test";
import { PROVE, SKILL_MARKETING, classifica, eventi, espansioneComando, stessoNome } from "./claude-skill-runtime-check.mjs";

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

test("nessun evento (profilo senza accesso) e' NON VERIFICATO", () => {
  assert.equal(classifica(prova("cro"), []).esito, "NON VERIFICATO (autenticazione)");
});

test("errore API con costo e token e' KO, non autenticazione", () => {
  const ev = [init(["cro"]), risultato({ is_error: true, result: "overloaded" })];
  assert.equal(classifica(prova("cro"), ev).esito, "KO (errore API)");
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

test("le otto skill e la prova negativa sono tutte previste", () => {
  assert.deepEqual(
    PROVE.map((p) => p.skill).sort(),
    ["animation-performance", "copywriting", "cro", "negativo", "product-marketing", "review-animations", "seo-audit", "supabase-postgres-best-practices", "vinea-marketing"],
  );
  for (const p of PROVE) assert.ok(p.prompt.length > 20);
});
