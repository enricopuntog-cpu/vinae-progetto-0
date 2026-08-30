import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { reportReasonLabel, reportReasons } from "@/data/moderation";

const progetto = join(import.meta.dir, "../../..");
const leggi = (percorso: string) => readFileSync(join(progetto, percorso), "utf8");
const senzaCommenti = (sorgente: string) =>
  sorgente
    .replace(/\{\s*\/\*(?:(?!\*\/)[\s\S])*\*\/\s*\}/g, "")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/.*$/gm, "$1");

const dialogo = senzaCommenti(leggi("src/components/vinea/ReportDialog.tsx"));
const annuncio = senzaCommenti(leggi("src/app/annuncio/[id]/page-client.tsx"));
const profilo = senzaCommenti(leggi("src/app/profilo/[id]/page.tsx"));
const club = senzaCommenti(leggi("src/app/community/[slug]/page-client.tsx"));
const discussioni = senzaCommenti(leggi("src/components/vinea/ClubDiscussioni.tsx"));
const account = senzaCommenti(leggi("src/app/account/page-client.tsx"));
const mieiReport = senzaCommenti(
  leggi("src/components/vinea/moderation/MyReportsPageClient.tsx"),
);

describe("A20 - dialogo condiviso di segnalazione", () => {
  it("espone motivi Club stabili con etichette leggibili", () => {
    expect(reportReasons.club).toEqual([
      "contenuto_non_conforme",
      "comportamento_scorretto",
      "spam",
      "altro",
    ]);
    expect(reportReasonLabel.club).toEqual({
      contenuto_non_conforme: "Contenuto non conforme",
      comportamento_scorretto: "Comportamento scorretto",
      spam: "Spam",
      altro: "Altro",
    });
    expect(dialogo).toInclude('club: "Segnala Club"');
    expect(dialogo).toInclude('profilo: "Segnala profilo"');
    expect(dialogo).toInclude("reportReasonLabel[targetType]?.[voce] ?? voce");
  });

  it("richiede autenticazione e l'identificatore adatto al bersaglio", () => {
    expect(dialogo).toInclude("if (!authUser)");
    expect(dialogo).toInclude("Accedi prima di inviare una segnalazione.");
    expect(dialogo).toMatch(/targetType === "club" && !clubSlug\?\.trim\(\)/);
    expect(dialogo).toMatch(/targetType !== "club" && !targetId/);
    expect(dialogo).toInclude("Questo contenuto non può essere segnalato.");
  });

  it("impedisce il doppio invio e rende non chiudibile il dialogo durante il caricamento", () => {
    expect(dialogo).toInclude("if (loading) return;");
    expect(dialogo).toInclude("const [reason, setReason] = useState(reasons[0]);");
    expect(dialogo).toMatch(/onClick=\{\(\) => void invia\(\)\}\s*disabled=\{loading\}/);
    expect(dialogo).toMatch(/onOpenChange=\{\(valore\) => \{\s*if \(loading\) return;/);
    expect(dialogo).toMatch(/setLoading\(true\)[\s\S]*finally \{\s*setLoading\(false\)/);
  });

  it("media duplicati e guasti senza mostrare internals PostgreSQL", () => {
    expect(dialogo).toInclude("Hai già una segnalazione aperta per questo contenuto.");
    expect(dialogo).toInclude("Invio non riuscito. Riprova più tardi.");
    expect(dialogo).not.toMatch(/sqlstate|postgres|public\.reports|42P01/i);
    expect(dialogo).toInclude('role="alert"');
  });

  it("conferma il successo, invoca la callback e permette di seguire lo stato", () => {
    expect(dialogo).toMatch(/setStep\(2\);\s*onSuccess\?\.\(\);/);
    expect(dialogo).toInclude("La segnalazione è stata registrata.");
    expect(dialogo).toInclude('href="/segnalazioni"');
    expect(dialogo).toInclude('role="status"');
    expect(dialogo).toInclude("if (!valore) reset();");
  });
});

describe("A20 - punti di ingresso", () => {
  it("l'annuncio usa il listing UUID reale e nasconde l'azione al venditore", () => {
    expect(annuncio).toInclude("const listingId = wine.listingId ?? wine.id;");
    expect(annuncio).toInclude('targetType="annuncio"');
    expect(annuncio).toInclude("targetId={listingId}");
    expect(annuncio).toMatch(/sonoIlVenditore[\s\S]*Segnala annuncio/);
  });

  it("il profilo usa il trigger interattivo condiviso e lo nasconde a chi guarda se stesso", () => {
    expect(profilo).toInclude("const profiloProprio = utente?.id === profilo.userId;");
    expect(profilo).toInclude("{!profiloProprio ? (");
    expect(profilo).toInclude('targetType="profilo"');
    expect(profilo).toInclude("targetId={profilo.userId}");
    expect(dialogo).toInclude("const triggerPredefinito =");
    expect(dialogo).toInclude("<DialogTrigger asChild>{trigger ?? triggerPredefinito}</DialogTrigger>");
    expect(dialogo).not.toInclude("<TriggerPredefinito");
  });

  it("l'annuncio continua ad aprire lo stesso dialogo condiviso", () => {
    expect(annuncio).toMatch(/<ReportDialog[\s\S]*targetType="annuncio"[\s\S]*Segnala annuncio/);
    expect(dialogo).toInclude("setOpen(valore);");
  });

  it("il Club usa slug e nome reali e nasconde l'azione al proprietario", () => {
    expect(club).toInclude("{!club.mio ? (");
    expect(club).toInclude('targetType="club"');
    expect(club).toInclude("clubSlug={club.slug}");
    expect(club).toInclude("targetLabel={club.nome}");
  });

  it("post e commenti inoltrano i rispettivi UUID reali", () => {
    expect(discussioni).toMatch(/targetType="post"\s*targetId=\{post\.id\}/);
    expect(discussioni).toMatch(/targetType="commento"\s*targetId=\{r\.id\}/);
  });

  it("Account riusa la pagina esistente Le mie segnalazioni", () => {
    expect(account).toInclude("href={routes.segnalazioni}");
    expect(account).toInclude("Le mie segnalazioni");
    expect(mieiReport).toInclude("usePhase9Moderation");
    expect(mieiReport).toInclude("mieSegnalazioni");
    expect(mieiReport).not.toMatch(/noteInterne|assigned_to|moderation_audit_log/);
  });
});
