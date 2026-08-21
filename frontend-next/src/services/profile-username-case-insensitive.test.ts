import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";

const MIGRAZIONE = readFileSync(
  new URL(
    "../../../supabase/migrations/20260821120000_profiles_username_case_insensitive.sql",
    import.meta.url,
  ),
  "utf8",
);

describe("unicità case-insensitive del nome utente", () => {
  it("impedisce a Mario e mario di coesistere senza limitare username differenti", () => {
    expect(MIGRAZIONE).toMatch(
      /create unique index profiles_username_lower_key\s+on public\.profiles \(lower\(username\)\)/,
    );

    const chiavi = ["Mario", "mario", "Luigi"].map((username) => username.toLowerCase());
    expect(chiavi[0]).toBe(chiavi[1]);
    expect(chiavi[0]).not.toBe(chiavi[2]);
  });

  it("ferma la migration con un errore esplicito senza riscrivere gli username", () => {
    expect(MIGRAZIONE).toContain("group by lower(username)");
    expect(MIGRAZIONE).toContain("having count(*) > 1");
    expect(MIGRAZIONE).toContain("resolve those data collisions manually");
    expect(MIGRAZIONE).not.toMatch(/update\s+public\.profiles\s+set\s+username/i);
  });

  it("il trigger cerca il candidato libero ignorando il case e conserva i suffissi", () => {
    expect(MIGRAZIONE).toContain("where lower(username) = lower(candidato)");
    expect(MIGRAZIONE).toContain("tentativo := tentativo + 1");
    expect(MIGRAZIONE).toContain("candidato := base_username || '_' || tentativo::text");
  });
});
