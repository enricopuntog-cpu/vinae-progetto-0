import { describe, expect, it } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { AI_UI, valoreFlagEsattamenteTrue } from "@/config/features";

const sorgentiSuperfici = {
  sommelier: readFileSync(join(import.meta.dir, "../components/vinea/Layout.tsx"), "utf8"),
  catalogazione: readFileSync(join(import.meta.dir, "../app/vendi/page-client.tsx"), "utf8"),
  abbinamento: readFileSync(join(import.meta.dir, "../app/esplora/page-client.tsx"), "utf8"),
} as const;

const envExample = readFileSync(join(import.meta.dir, "../../.env.example"), "utf8");
const sorgenteFlag = readFileSync(join(import.meta.dir, "features.ts"), "utf8");

describe("flag pubblica delle superfici IA", () => {
  it("fallisce chiusa quando il valore manca", () => {
    expect(valoreFlagEsattamenteTrue(undefined)).toBeFalse();
  });

  it("abilita la UI soltanto con la stringa esatta true", () => {
    expect(valoreFlagEsattamenteTrue("true")).toBeTrue();

    for (const valore of ["", "false", "TRUE", "True", "1", "yes", " true "]) {
      expect(valoreFlagEsattamenteTrue(valore)).toBeFalse();
    }
  });

  it("copre le tre superfici previste nei rispettivi punti di montaggio", () => {
    expect(Object.keys(AI_UI).sort()).toEqual([
      "abbinamento",
      "catalogazione",
      "sommelier",
    ]);

    const puntiMontaggio = {
      sommelier: "{AI_UI.sommelier && <SommelierChat />}",
      catalogazione: "{AI_UI.catalogazione && (",
      abbinamento:
        'const abbinamentoAttivo = AI_UI.abbinamento && mode === "abbinamento";',
    } as const;

    for (const [superficie, sorgente] of Object.entries(sorgentiSuperfici)) {
      expect(sorgente).toInclude(puntiMontaggio[superficie as keyof typeof puntiMontaggio]);
    }
  });

  it("non rende pubblico alcun secret o gate server-side IA", () => {
    const pubblicheIa = [...`${sorgenteFlag}\n${envExample}`.matchAll(/NEXT_PUBLIC_[A-Z0-9_]*AI[A-Z0-9_]*/g)]
      .map(([nome]) => nome)
      .filter((nome, indice, nomi) => nomi.indexOf(nome) === indice);

    expect(pubblicheIa).toEqual([
      "NEXT_PUBLIC_AI_UI_ENABLED",
      "NEXT_PUBLIC_AI_ACTIONS_ENABLED",
    ]);
    expect(envExample).toInclude("\nAI_ENABLED=false");
    expect(envExample).toInclude("\nOPENAI_API_KEY=");
  });

  it("rende irraggiungibile il pannello demo degli sfondi nel target", () => {
    const vendi = sorgentiSuperfici.catalogazione;
    expect(existsSync(join(import.meta.dir, "../components/vinea/BetaBackgroundPanel.tsx"))).toBeFalse();
    expect(vendi).not.toInclude("BetaBackgroundPanel");
    expect(vendi).not.toInclude("SfondoIAPanel");
    expect(vendi).not.toInclude("setTimeout(");
    expect(vendi).not.toInclude("Sfondo applicato (demo)");
    expect(vendi).not.toInclude("Migliora lo sfondo con IA");
    expect(vendi).not.toInclude("Applica sfondo suggerito");
  });
});
