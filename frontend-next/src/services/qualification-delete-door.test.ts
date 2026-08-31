// Qualification & Trust Closure — la porta di eliminazione, letta dal SQL.
//
// Questi test non fanno girare PostgreSQL: la prova d'esecuzione è la griglia
// in `supabase/tests/`. Quello che sorvegliano è la FORMA della porta, cioè
// tutto ciò che una riscrittura distratta potrebbe allargare senza accorgersi:
// un `p_user_id` fra i parametri, un `grant` ad `anon`, uno stato in più fra
// quelli eliminabili, un `search_path` dimenticato.
//
// Sorvegliano anche l'altra metà: che le due migrazioni D1 congelate non siano
// state toccate, perché la correzione di una migrazione già distribuita si fa
// con una nuova migrazione, mai in luogo.

import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const root = join(import.meta.dir, "../../..");
const read = (percorso: string) => readFileSync(join(root, percorso), "utf8");

const NUOVA = "supabase/migrations/20260831130000_professional_qualification_delete.sql";
const CONGELATA_DOMINIO = "supabase/migrations/20260827160000_d1_professional_qualifications.sql";
const CONGELATA_PROFILO = "supabase/migrations/20260827160500_d1_public_profile_qualifiche.sql";

const sql = read(NUOVA);
// Il SQL senza i commenti: le motivazioni nominano gli stati non eliminabili e
// cercarle nel testo integrale troverebbe la spiegazione al posto del codice.
const codice = sql
  .split("\n")
  .filter((riga) => !riga.trimStart().startsWith("--"))
  .join("\n");

const corpoFunzione = (nome: string) => {
  const inizio = codice.indexOf(`create or replace function public.${nome}`);
  expect(inizio).toBeGreaterThan(-1);
  const fine = codice.indexOf("$$;", inizio);
  return codice.slice(inizio, fine + 3);
};

describe("professional_qualification_delete — la porta stretta", () => {
  const porta = corpoFunzione("professional_qualification_delete");

  it("è una porta fidata dichiarata per intero", () => {
    expect(porta).toInclude("security definer");
    expect(porta).toInclude("set search_path = ''");
    expect(porta).toInclude("volatile");
    expect(porta).toInclude("language plpgsql");
  });

  it("richiede una sessione e risolve il titolare server-side", () => {
    expect(porta).toInclude("auth.uid()");
    expect(porta).toMatch(/if v_uid is null then[\s\S]*?42501/);
    // Il filtro sul titolare è nella lettura E nella cancellazione.
    expect(porta).toMatch(/from public\.professional_qualifications q\s*\n\s*where q\.id = p_id and q\.user_id = v_uid/);
    expect(porta).toMatch(/delete from public\.professional_qualifications q\s*\n\s*where q\.id = p_id and q\.user_id = v_uid/);
  });

  it("non accetta un titolare dal client: nessun p_user_id, un solo parametro", () => {
    expect(codice).toInclude("public.professional_qualification_delete(p_id uuid)");
    // `p_user_id` non compare nel corpo eseguibile: se ci fosse, sarebbe il
    // client a dire di chi è la riga. (Il testo del `comment on` lo nomina
    // apposta per dichiararne l'assenza, ed è fuori dal corpo.)
    expect(porta).not.toInclude("p_user_id");
    const parametri = porta.slice(porta.indexOf("(") + 1, porta.indexOf(")"));
    expect(parametri.split(",")).toHaveLength(1);
  });

  it("elimina soltanto una bozza: lo stato è riletto, non ricevuto", () => {
    expect(porta).toInclude("for update");
    expect(porta).toInclude("v_stato <> 'bozza'::public.qualifica_professionale_stato");
    // Nessuno stato diverso da `bozza` compare come condizione di uscita:
    // inviata, approvata, rifiutata e ritirata cadono tutte nel `<>`.
    for (const stato of ["inviata", "approvata", "rifiutata", "ritirata"]) {
      expect(porta).not.toInclude(`'${stato}'`);
    }
    // Riga inesistente e riga altrui danno la stessa risposta.
    expect(porta).toMatch(/if v_stato is null then[\s\S]*?Qualifica non trovata/);
  });

  it("è concessa al solo ruolo authenticated, revocando anche i default di service_role", () => {
    expect(codice).toInclude(
      "revoke all on function public.professional_qualification_delete(uuid)\n  from public, anon, authenticated, service_role;",
    );
    expect(codice).toInclude(
      "grant execute on function public.professional_qualification_delete(uuid)\n  to authenticated;",
    );
    expect(codice).not.toMatch(/grant execute on function public\.professional_qualification_delete[\s\S]{0,60}(anon|service_role|public)\s*;/);
  });

  it("non tocca storage.objects: gli oggetti li rimuove il chiamante", () => {
    expect(codice).not.toInclude("storage.objects");
    expect(codice).not.toMatch(/delete from storage/i);
  });

  it("non apre nessuna porta di verdetto e non tocca ruoli o enum", () => {
    expect(codice).not.toMatch(/review_apply|user_roles|has_role|approvata'::.*update|create type|alter type/i);
    expect(codice).not.toMatch(/drop (function|table|type|policy)/i);
  });
});

describe("professional_qualifications_me — la proiezione del titolare", () => {
  const proiezione = corpoFunzione("professional_qualifications_me");

  it("esclude le ritirate, e solo quelle", () => {
    expect(proiezione).toInclude("q.user_id = (select auth.uid())");
    expect(proiezione).toInclude(
      "and q.stato <> 'ritirata'::public.qualifica_professionale_stato",
    );
  });

  it("resta una porta fidata filtrata, con le stesse colonne di prima", () => {
    expect(proiezione).toInclude("security definer");
    expect(proiezione).toInclude("set search_path = ''");
    expect(proiezione).toInclude("stable");
    for (const colonna of [
      "credential_reference",
      "stato",
      "submitted_at",
      "reviewed_at",
      "valida",
      "documenti_elenco",
    ]) {
      expect(proiezione).toInclude(colonna);
    }
    // `valida` continua a venire dalla vista privata: la regola della spunta
    // resta scritta in un posto solo e non è ricalcolata qui.
    expect(proiezione).toInclude("private.qualifiche_professionali_valide");
    expect(proiezione).not.toMatch(/current_date|now\(\)/);
  });

  it("non espone niente della verifica", () => {
    expect(proiezione).not.toMatch(/provider|model|confidence|reasoning|private_payload/i);
  });

  it("la riga ritirata resta nel database: nessuna cancellazione mascherata", () => {
    // L'unico `delete` della migrazione è quello della bozza dentro la porta.
    const cancellazioni = codice.match(/delete from/g) ?? [];
    expect(cancellazioni).toHaveLength(1);
    expect(codice).not.toMatch(/update public\.professional_qualifications[\s\S]{0,120}ritirata/);
  });
});

describe("le migrazioni D1 congelate restano intatte", () => {
  it("la nuova migrazione è additiva e non riscrive le precedenti", () => {
    for (const congelata of [CONGELATA_DOMINIO, CONGELATA_PROFILO]) {
      const testo = read(congelata);
      // La firma della porta di eliminazione non esisteva prima e non deve
      // essere stata retro-inserita nelle migrazioni già distribuite.
      expect(testo).not.toInclude("professional_qualification_delete");
      expect(testo).not.toInclude("q.stato <> 'ritirata'");
    }
  });

  it("il profilo pubblico non ha guadagnato né documenti né percorsi", () => {
    // Senza i commenti: quel file spiega a lungo che cosa NON espone, e cercare
    // quelle parole nel testo integrale troverebbe la spiegazione, non il SQL.
    const profilo = read(CONGELATA_PROFILO)
      .split("\n")
      .filter((riga) => !riga.trimStart().startsWith("--"))
      .join("\n");
    const firma = profilo.slice(
      profilo.indexOf("create function public.profilo_pubblico"),
      profilo.indexOf("comment on function public.profilo_pubblico"),
    );
    expect(firma.length).toBeGreaterThan(0);
    expect(firma).not.toInclude("storage_path");
    expect(firma).not.toInclude("credential_reference");
    expect(firma).not.toMatch(/documenti|professional_qualification_documents/);
  });
});
