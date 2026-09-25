import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const pagina = readFileSync(new URL("./page.tsx", import.meta.url), "utf8");
const caricamento = readFileSync(new URL("./loading.tsx", import.meta.url), "utf8");
const nonTrovato = readFileSync(new URL("../not-found.tsx", import.meta.url), "utf8");
const progetto = join(import.meta.dir, "../../../../..");
const contratti = readFileSync(join(progetto, "src/services/types.ts"), "utf8");
const codice = pagina.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");

describe("/profilo/[id]/cantina", () => {
  it("valida il profilo con la stessa porta pubblica prima di leggere la Cantina", () => {
    const profilo = pagina.indexOf("await service.profilo(id)");
    const controllo = pagina.indexOf("if (!esitoProfilo.data) notFound()");
    const cantina = pagina.indexOf("await service.cantinaPubblica(id, finestraCollezione(pagina))");

    expect(profilo).toBeGreaterThan(-1);
    expect(controllo).toBeGreaterThan(profilo);
    expect(cantina).toBeGreaterThan(controllo);
    expect(pagina).toInclude("creaPublicProfileService(client)");
    expect(pagina.match(/creaPublicProfileService\(/g)).toHaveLength(1);
  });

  it("resta fail-closed per un profilo assente o non raggiungibile", () => {
    expect(pagina).toInclude("if (!esitoProfilo.ok) return <ProfiloNonDisponibile />");
    expect(pagina).toInclude("if (!esitoProfilo.data) notFound()");
    expect(pagina).toInclude("Profilo non disponibile");
    expect(nonTrovato).toInclude("Profilo non disponibile");
    expect(codice).not.toMatch(/sospes|modera|inesistente|esitoProfilo\.error/i);
  });

  it("pagina la sola porta Cantina pubblica senza un conteggio separato", () => {
    expect(pagina).toInclude("finestraCollezione(pagina)");
    expect(pagina).toInclude("paginaDiBottiglie(esitoCantina.data)");
    expect(pagina).toInclude("altraPagina={collezione.altraPagina}");
    expect(codice).not.toMatch(/count\(|conteggio\w*\(|\.from\(/i);
  });

  it("compone una testata minima con identità pubblica e ritorno al profilo", () => {
    expect(pagina).toInclude("<AvatarPersona");
    expect(pagina).toInclude("profilo.avatarUrl");
    expect(pagina).toInclude("profilo.username");
    expect(pagina).toInclude("profilo.citta");
    expect(pagina).toInclude("profilo.provincia");
    expect(pagina).toInclude("La cantina di {username}");
    expect(pagina).toInclude("Torna al profilo");
    expect(pagina).toInclude("indirizzoProfiloPubblico(userId)");
  });

  it("il proprietario attraversa la stessa route pubblica e riceve solo un link di gestione", () => {
    expect(pagina).toInclude("utente?.id === profilo.userId");
    expect(pagina).toInclude("profiloProprio={profiloProprio}");
    expect(pagina).toInclude("{profiloProprio && (");
    expect(pagina).toInclude("Gestisci la mia cantina");
    expect(pagina).toInclude("href={routes.cantina}");
    expect(pagina.match(/service\.cantinaPubblica\(/g)).toHaveLength(1);
  });

  it("non legge dati o strutture della Cantina privata", () => {
    expect(codice).not.toMatch(
      /CellarService|createCellarService|useCellar|bottle_units|cellar_environments|cellar_modules|cellar_slots|Cellar3D/,
    );
    expect(codice).not.toMatch(
      /note_personali|apertura_pianificata|degustazione_nota|degustazione_at|acquisition|prezzo_visibilita|signedUrl|cantina bucket/i,
    );
    for (const campo of ["notePersonali", "costoAcquisto", "posizione", "ambiente", "modulo", "slot"]) {
      expect(contratti).not.toMatch(new RegExp(`BottigliaCantinaPubblica[\\s\\S]{0,500}${campo}`, "i"));
    }
  });

  it("ha una superficie di caricamento responsiva senza dipendenze client", () => {
    expect(caricamento).toInclude('aria-busy="true"');
    expect(caricamento).toInclude('aria-label="Caricamento Cantina pubblica"');
    expect(caricamento).toInclude("grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3");
    expect(caricamento).not.toInclude('"use client"');
    expect(caricamento).not.toMatch(/min-w-\[|w-\[\d|overflow-x/);
  });
});
