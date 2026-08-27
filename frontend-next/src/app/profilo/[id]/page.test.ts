import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";

const pagina = readFileSync(new URL("./page.tsx", import.meta.url), "utf8");
const nonTrovato = readFileSync(new URL("./not-found.tsx", import.meta.url), "utf8");
const codice = pagina.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");

describe("/profilo/[id]", () => {
  it("rende dal server attraverso l'unico PublicProfileService", () => {
    expect(pagina).not.toInclude('"use client"');
    expect(pagina).toInclude("params: Promise<{ id: string }>");
    expect(pagina).toInclude("await getSupabaseServerClient()");
    expect(pagina).toInclude("creaPublicProfileService(client)");
    expect(pagina.match(/creaPublicProfileService\(/g)).toHaveLength(1);
    expect(pagina).toInclude("await service.profilo(id)");
    expect(codice).not.toMatch(/fetch\(|useEffect|createClient|@\/lib\/supabase\/client/);
  });

  it("tratta ogni profilo assente come la stessa superficie non disponibile", () => {
    expect(pagina).toInclude("if (!esitoProfilo.data) notFound()");
    expect(nonTrovato).toInclude("Profilo non disponibile");
    expect(nonTrovato).not.toMatch(/sospes|rimoss|modera|inesistente/i);
  });

  it("mostra un errore tecnico generico senza dettagli del database", () => {
    expect(pagina).toInclude("if (!esitoProfilo.ok)");
    expect(pagina).toInclude("Non è stato possibile caricare questo profilo. Riprova fra poco.");
    expect(pagina).not.toInclude("esitoProfilo.error");
    expect(codice).not.toMatch(/PostgreSQL|PostgREST|22P02|PGRST|error\.message/);
  });

  it("riusa la foundation avatar e la sola allowlist visuale del profilo", () => {
    expect(pagina).toInclude("<AvatarPersona");
    expect(pagina).toInclude("avatarUrl={profilo.avatarUrl}");
    expect(pagina).toInclude("proprietarioId={profilo.userId}");
    expect(pagina).toInclude("{profilo.username}");
    expect(pagina).toInclude("esperienzaLabels[profilo.esperienza]");
    expect(pagina).toInclude("profilo.citta");
    expect(pagina).toInclude("profilo.provincia");
    expect(pagina).toInclude("profilo.bio");
    expect(codice).not.toMatch(
      /seller_verificato|TrustBadge|ShieldCheck|rating|recension|certific|email|dob|ruol|stato_utente/i,
    );
  });

  it("la spunta e i badge vengono dalla riga del profilo, non da una seconda lettura", () => {
    // Un solo servizio e una sola chiamata al profilo: la spunta arriva con la
    // riga. Una lettura per badge sarebbe un N+1 sulla pagina, e una porta
    // interrogabile su un elenco di uuid sarebbe una sonda su chi e verificato.
    expect(pagina).toInclude("profilo.professionistaVerificato");
    expect(pagina).toInclude("profilo.qualificheProfessionali");
    expect(pagina.match(/await service\./g)).toHaveLength(2);
    expect(codice).not.toMatch(/qualific\w*\(|professional_qualification|\.rpc\(/i);
  });

  it("nomina la qualifica professionale, non l'identita ne una certificazione Vinea", () => {
    expect(pagina).toInclude("Qualifica professionale verificata");
    expect(codice).not.toMatch(/KYC|verifica d.identit|certificazione vinea/i);
  });

  it("zero qualifiche non disegna nulla: nessun segnaposto su chi non ne ha", () => {
    expect(pagina).toInclude("profilo.qualificheProfessionali.length > 0 &&");
    expect(codice).not.toMatch(/nessuna qualifica|non verificat/i);
  });

  it("il badge pubblico mostra la sola allowlist, e nessun dato privato", () => {
    for (const campo of ["q.titolo", "q.enteEmittente", "q.paese", "q.issuedOn"]) {
      expect(pagina).toInclude(campo);
    }
    expect(codice).not.toMatch(
      /credentialReference|storagePath|documenti|provider|confidence|reasoning|q\.id/i,
    );
  });

  it("carica gli annunci attivi solo dopo un profilo valido e li mantiene opzionali", () => {
    const profiloValido = pagina.indexOf("if (!esitoProfilo.data) notFound()");
    const letturaAnnunci = pagina.indexOf("await service.annunciAttivi(id)");
    expect(profiloValido).toBeGreaterThan(-1);
    expect(letturaAnnunci).toBeGreaterThan(profiloValido);
    expect(pagina).toInclude("const annunci = esitoAnnunci.ok ? esitoAnnunci.data : []");
    expect(pagina).toInclude("Annunci attivi");
    expect(pagina).toInclude("Nessun annuncio attivo");
    expect(pagina).toInclude('<WineCard key={annuncio.id} wine={annuncio} variant="list" />');
  });

  it("non apre query profilo, directory o azioni sociali alternative", () => {
    expect(codice).not.toMatch(/\.from\(["']profiles["']\)|service_role/);
    expect(codice).not.toMatch(/listaUtenti|cercaUtenti|people|directory|follow|messagg|recension|CTA/i);
    expect(codice).not.toMatch(/href=["'{`]\/profilo/);
  });
});
