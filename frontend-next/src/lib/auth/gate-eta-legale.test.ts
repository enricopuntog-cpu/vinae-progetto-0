import { describe, expect, it } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { percorsoRelativoSicuro } from "@/lib/auth/origine-redirect";
import { PARAMETRO_NEXT } from "@/lib/auth/ritorno-auth";

/**
 * Contratto D4: il gate 18+, il ritorno alla pagina richiesta e il Centro
 * legale. Stessa forma delle prove di superficie della beta — si guarda il
 * sorgente, non un DOM montato — più il giro di andata e ritorno vero, che qui
 * si può eseguire perché passa da due funzioni pure già esistenti.
 */
const progetto = join(import.meta.dir, "../../..");
const leggi = (percorso: string) => readFileSync(join(progetto, percorso), "utf8");
const esiste = (percorso: string) => existsSync(join(progetto, percorso));
// Un divieto di parola deve guardare il codice, non i commenti che spiegano il
// divieto: stessa convenzione di public-surface-contract.test.ts.
const senzaCommenti = (sorgente: string) =>
  sorgente.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");

/** La composizione che fa AgeGate, riprodotta sulle stesse funzioni. */
const rimandoACompletamento = (pathname: string) => {
  const next = percorsoRelativoSicuro(pathname) ?? "/home";
  return `/completa-profilo?${PARAMETRO_NEXT}=${encodeURIComponent(next)}`;
};

/** La lettura che fa /completa-profilo, sulle stesse funzioni. */
const ritornoDa = (url: string) =>
  percorsoRelativoSicuro(new URL(url, "https://vinea.test").searchParams.get(PARAMETRO_NEXT)) ??
  "/home";

describe("ritorno alla pagina richiesta dopo il completamento", () => {
  it("porta a termine il giro /cantina → /completa-profilo → /cantina", () => {
    const rimando = rimandoACompletamento("/cantina");
    expect(rimando).toBe("/completa-profilo?next=%2Fcantina");
    expect(ritornoDa(rimando)).toBe("/cantina");
  });

  it("rifiuta una destinazione assoluta o protocol-relative e ricade su /home", () => {
    expect(ritornoDa("/completa-profilo?next=https%3A%2F%2Fevil.example")).toBe("/home");
    expect(ritornoDa("/completa-profilo?next=%2F%2Fevil.example")).toBe("/home");
    expect(ritornoDa("/completa-profilo?next=%2F%5Cevil.example")).toBe("/home");
    expect(ritornoDa("/completa-profilo")).toBe("/home");
  });

  it("non introduce un secondo contratto di redirect accanto a quello D5", () => {
    for (const percorso of [
      "src/components/vinea/AgeGate.tsx",
      "src/app/completa-profilo/page-client.tsx",
    ]) {
      const sorgente = leggi(percorso);
      expect(sorgente).toInclude("percorsoRelativoSicuro");
      expect(sorgente).toInclude("PARAMETRO_NEXT");
      // Nessuna validazione parallela scritta a mano, che è il modo in cui un
      // redirect aperto rientra da una porta laterale.
      expect(senzaCommenti(sorgente)).not.toMatch(/startsWith\("\/"\)|window\.location|new URL\(/);
    }
  });
});

describe("AgeGate", () => {
  const gate = leggi("src/components/vinea/AgeGate.tsx");

  it("non espone il contenuto mentre sessione o profilo sono ancora in verifica", () => {
    // Le route pubbliche consentite passano anche durante il bootstrap. Tutte
    // le altre restano coperte finché sappiamo se il visitatore è un ospite.
    expect(gate).toInclude("if (consentito) return null;");
    expect(gate).toInclude("if (authLoading) {");
    expect(gate).toInclude("Verifica dell&apos;accesso…");
    // Soltanto dopo il bootstrap l'assenza di utente identifica davvero un
    // ospite. Per una sessione, `completo` è l'unico stato che passa.
    expect(gate).toInclude('if (!authUser || authStatoEta === "completo") return null;');
    expect(gate).toInclude('authStatoEta === "errore_lettura"');
    expect(gate).toInclude('authStatoEta !== "da_completare"');
  });

  it("manda a completare il profilo conservando il percorso richiesto", () => {
    expect(gate).toInclude("const next = percorsoRelativoSicuro(pathname) ?? \"/home\";");
    expect(gate).toInclude(
      "router.replace(`/completa-profilo?${PARAMETRO_NEXT}=${encodeURIComponent(next)}`)",
    );
  });

  it("fallisce chiuso sulla lettura non riuscita, con riprova e uscita", () => {
    const errore = gate.slice(gate.indexOf('authStatoEta === "errore_lettura"'));
    expect(errore).toInclude("Non riusciamo a verificare il tuo profilo.");
    expect(errore).toInclude("Riprova");
    expect(errore).toInclude("Esci");
    expect(errore).toInclude("authRicaricaProfilo()");
    expect(errore).toInclude("authLogout()");
  });

  it("non interroga il profilo per conto suo e non mostra errori grezzi", () => {
    const codice = senzaCommenti(gate);
    expect(codice).not.toMatch(/getSupabaseClient|\.from\(|supabaseProfileService|profile-service/);
    // Nessun messaggio del provider viene stampato: il testo è nostro.
    expect(codice).not.toMatch(/authError|error\.message|\{esito\.error\}/);
  });

  it("lascia raggiungibile il Centro legale in qualunque stato del profilo", () => {
    expect(gate).toInclude('"/legale"');
    expect(gate).toInclude('"/completa-profilo"');
    expect(gate).toInclude('"/accedi"');
    expect(gate).toInclude('"/registrati"');
  });
});

describe("riprova della lettura profilo", () => {
  const dominio = leggi("src/lib/store/real-auth-domain.ts");

  it("passa da ProfileService e legge la riga intera una volta per tentativo", () => {
    expect(dominio).toInclude("supabaseProfileService.leggiProfiloCorrente()");
    // Una sola chiamata nel modulo: il tentativo iniziale e la riprova
    // condividono la stessa azione invece di duplicarla.
    expect(dominio.split("leggiProfiloCorrente()").length - 1).toBe(1);
    expect(dominio).toInclude("const authRicaricaProfilo = useCallback");
  });

  it("non parte una seconda volta mentre la prima è ancora in corso", () => {
    expect(dominio).toInclude(
      "if (!userId || profiloInLetturaRef.current?.userId === userId) return;",
    );
  });

  it("scarta una risposta che appartiene a una sessione precedente", () => {
    expect(dominio).toInclude(
      "if (authUserIdRef.current !== userId || profiloInLetturaRef.current !== token) return;",
    );
    expect(dominio).toInclude("if (authUserIdRef.current !== authUser.userId) return result;");
  });

  it("l'esito riuscito aggiorna lo stesso stato canonico del profilo", () => {
    expect(dominio).toInclude('stato: esito.ok ? "letto" : "errore_lettura"');
    expect(dominio).toInclude("setProfiloLetto({ userId, profilo: null, stato: \"in_verifica\" })");
  });

  it("non lascia sopravvivere il vecchio valore sovraccarico", () => {
    expect(senzaCommenti(dominio)).not.toInclude("sconosciuto");
    expect(leggi("src/lib/vinea-store.tsx")).toInclude("authStatoEta: StatoEta");
  });
});

describe("/completa-profilo", () => {
  const pagina = leggi("src/app/completa-profilo/page-client.tsx");

  it("legge il ritorno dai parametri e ci torna dopo il salvataggio", () => {
    expect(pagina).toInclude("useSearchParams");
    expect(pagina).toInclude("percorsoRelativoSicuro(parametri.get(PARAMETRO_NEXT))");
    expect(pagina).toInclude("if (esito.ok) router.push(destinazione);");
    // Il wrapper della route fornisce il Suspense che useSearchParams richiede.
    expect(leggi("src/app/completa-profilo/page.tsx")).toInclude("<Suspense");
  });

  it("usa il ritorno sicuro anche quando il profilo è già completo", () => {
    const completo = pagina.slice(pagina.indexOf('authStatoEta === "completo"'));
    expect(completo).toInclude("<Link href={destinazione}>");
  });

  it("non mostra il modulo dopo una lettura fallita", () => {
    const errore = pagina.indexOf('authStatoEta === "errore_lettura"');
    const modulo = pagina.indexOf("Ancora un passaggio");
    expect(errore).toBeGreaterThan(-1);
    expect(modulo).toBeGreaterThan(errore);
    expect(pagina).toInclude("Non riusciamo a verificare il tuo profilo.");
  });

  it("conserva nome utente, data di nascita, dichiarazione e una sola scrittura", () => {
    expect(pagina).toInclude("authAggiornaProfilo({ username: username.trim(), dob })");
    // Una chiamata sola in tutta la pagina: nome utente e data di nascita
    // partono insieme, mai in due scritture.
    expect(pagina.split("authAggiornaProfilo(").length - 1).toBe(1);
    expect(pagina).toInclude("isMaggiorenne(value, new Date())");
    expect(pagina).toInclude("authLogout()");
  });
});

describe("Centro legale", () => {
  const legale = leggi("src/app/legale/page.tsx");

  it("esiste come route pubblica con le tre sezioni e le loro ancore", () => {
    expect(esiste("src/app/legale/page.tsx")).toBeTrue();
    expect(legale).toInclude("Centro legale");
    expect(legale).toInclude('id="termini"');
    expect(legale).toInclude('id="privacy"');
    expect(legale).toInclude('id="eta"');
    expect(legale).toInclude("Termini di utilizzo");
    expect(legale).toInclude("Privacy");
    expect(legale).toInclude("Requisito di età");
    // Nessuna sessione, nessun profilo: la pagina non consulta lo store.
    expect(legale).not.toMatch(/useVinea|"use client"/);
  });

  it("dichiara il rinvio invece di inventare il testo definitivo", () => {
    expect(legale).toInclude("Il testo definitivo sarà pubblicato prima del lancio pubblico.");
    expect(legale).toInclude("Vinea è riservato ai maggiorenni.");
    expect(legale).toInclude("La data di nascita è dichiarata dall&apos;utente.");
    expect(legale).toInclude("In questa fase non sono richiesti");
  });

  it("non promette clausole, basi giuridiche, conservazione o verifica dell'identità", () => {
    expect(legale).not.toMatch(
      /KYC|verifica dell.identit|documento d.identit|base giuridica|GDPR|art\.\s*\d|conservazione dei dati|foro competente|legge applicabile|responsabilit/i,
    );
  });

  it("offre un ritorno indietro visibile senza diventare un client component", () => {
    expect(legale).toInclude("<AzioneIndietro");
    expect(legale).toInclude('from "@/components/vinea/AzioneIndietro"');
    // La pagina resta server: il ritorno è client, e lo è da solo.
    expect(legale).not.toMatch(/useVinea|"use client"|useRouter/);
  });

  it("il ritorno indietro ha una destinazione anche senza cronologia", () => {
    const azione = leggi("src/components/vinea/AzioneIndietro.tsx");
    expect(esiste("src/components/vinea/AzioneIndietro.tsx")).toBeTrue();
    expect(azione).toInclude('"use client"');
    // I due rami: la cronologia quando c'è, una rotta interna quando non c'è.
    expect(azione).toInclude("window.history.length > 1");
    expect(azione).toInclude("router.back()");
    expect(azione).toInclude("router.push(fallback)");
    expect(azione).toInclude("fallback = routes.home");
    // Il fallback non può arrivare da fuori: niente referrer, niente query. Il
    // divieto guarda il codice, non il commento che lo spiega.
    expect(senzaCommenti(azione)).not.toMatch(/document\.referrer|searchParams|location\.href/);
  });

  it("il ritorno indietro è un controllo accessibile e non un'icona muta", () => {
    const azione = leggi("src/components/vinea/AzioneIndietro.tsx");
    expect(azione).toInclude('type="button"');
    // Un'etichetta testuale accanto all'icona, e l'icona esclusa dall'albero
    // accessibile perché non ripeta la stessa parola due volte.
    expect(azione).toInclude("{etichetta}");
    expect(azione).toInclude('etichetta = "Indietro"');
    expect(azione).toMatch(/<ArrowLeft[^>]*aria-hidden/);
    expect(azione).toInclude("focus-visible:ring-2");
  });

  it("è raggiungibile da un rimando discreto senza toccare le navigazioni", () => {
    const layout = leggi("src/components/vinea/Layout.tsx");
    expect(layout).toInclude('<Link href="/legale"');
    expect(layout).toInclude("Centro legale");
    // Le due navigazioni restano quelle di prima: il link sta nel footer.
    expect(layout).not.toMatch(/to: "\/legale"|icona: "legale"/);
    expect(layout.indexOf('href="/legale"')).toBeGreaterThan(layout.indexOf("<footer"));
  });
});

describe("consenso", () => {
  const registrati = leggi("src/app/registrati/page-client.tsx");
  const completa = leggi("src/app/completa-profilo/page-client.tsx");

  it("collega Termini e Privacy al Centro legale su entrambe le superfici", () => {
    for (const sorgente of [registrati, completa]) {
      expect(sorgente).toInclude('href="/legale#termini"');
      expect(sorgente).toInclude('href="/legale#privacy"');
      expect(sorgente).toInclude('testId="consenso-termini"');
    }
  });

  it("aprire un link legale non vale come spunta del consenso", () => {
    const checkbox = senzaCommenti(leggi("src/components/vinea/ConsentCheckbox.tsx"));
    // Con un <label> attorno, il click sul link marcherebbe anche la casella:
    // il testo resta collegato per aria-labelledby, non per annidamento.
    expect(checkbox).not.toInclude("<label");
    expect(checkbox).toInclude("aria-labelledby={idTesto}");
    expect(checkbox).toInclude("onCheckedChange(v === true)");
  });

  it("il click su Google non vale come consenso, e nessun consenso viene registrato", () => {
    const social = senzaCommenti(leggi("src/components/vinea/SocialAuthButtons.tsx"));
    // Il consenso non si deduce dal click: la superficie social non ha una
    // casella propria e non decide nulla, riceve solo il motivo per cui è
    // ferma. La spunta resta l'unica di /registrati.
    expect(social).not.toMatch(/ConsentCheckbox|terms|accett/i);
    expect(social).toInclude("consensoMancante");
    for (const sorgente of [registrati, completa]) {
      // E nessuna delle due pagine tiene una prova del consenso da qualche
      // parte: niente versione, niente data, niente colonna. Il testo accettato
      // è quello pubblicato su /legale.
      expect(senzaCommenti(sorgente)).not.toMatch(
        /consentVersion|versioneConsenso|consentAt|consenso_at|accettatoIl/,
      );
    }
  });

  it("la registrazione chiede la data di nascita una volta sola, senza casella gemella", () => {
    const codice = senzaCommenti(registrati);
    // La data resta obbligatoria e resta validata: sono queste due condizioni a
    // fermare un minorenne, non una spunta accanto a esse.
    expect(codice).toInclude('id="dob"');
    expect(codice).toInclude('type="date"');
    expect(codice).toInclude("isMaggiorenne(value, new Date())");
    expect(codice).toInclude("Devi avere almeno 18 anni per usare Vinea.");
    expect(codice).toInclude('dob !== ""');
    expect(codice).toInclude("dobError === null");
    // La casella «confermo di avere 18 anni» chiedeva lo stesso fatto una
    // seconda volta e la risposta non raggiungeva nessuna barriera: non c'è
    // più, e con lei lo stato che la reggeva.
    expect(codice).not.toInclude('testId="consenso-eta"');
    expect(codice).not.toInclude("maggiorenne &&");
    expect(codice).not.toMatch(/setMaggiorenne|\[maggiorenne,/);
    // Il requisito resta però scritto sulla pagina, e la casella dei Termini
    // resta una spunta vera.
    expect(codice).toInclude("Vinea è riservato ai maggiorenni.");
    expect(codice).toInclude('testId="consenso-termini"');
  });

  it("nemmeno il completamento profilo chiede due volte lo stesso fatto", () => {
    // Stessa forma dell'altra superficie: la casella non veniva scritta da
    // nessuna parte — `authAggiornaProfilo` porta solo nome utente e data — e
    // il CHECK su `profiles.dob` vincola l'UPDATE come vincola l'INSERT.
    const codice = senzaCommenti(completa);
    expect(codice).toInclude('id="dob"');
    expect(codice).toInclude('type="date"');
    expect(codice).toInclude("isMaggiorenne(value, new Date())");
    expect(codice).toInclude("Devi avere almeno 18 anni per usare Vinea.");
    expect(codice).toInclude('dob !== ""');
    expect(codice).toInclude("dobError === null");
    expect(codice).not.toInclude('testId="consenso-eta"');
    expect(codice).not.toInclude("maggiorenne &&");
    expect(codice).not.toMatch(/setMaggiorenne|\[maggiorenne,/);
    // Il requisito resta scritto, e i Termini restano una spunta vera.
    expect(codice).toInclude("Vinea è riservato ai maggiorenni.");
    expect(codice).toInclude('testId="consenso-termini"');
    // La scrittura non è cambiata: resta una sola, e porta ancora la data.
    expect(codice).toInclude("authAggiornaProfilo({ username: username.trim(), dob })");
  });

  it("la registrazione manda al provider la data, e la barriera vera resta il CHECK", () => {
    expect(senzaCommenti(registrati)).toInclude("dataNascita: dob");
    expect(leggi("src/services/auth-service.ts")).toInclude("dob: dataNascita");
    expect(leggi("../supabase/migrations/20260728000545_auth_profiles_roles.sql")).toInclude(
      "check (dob <= (current_date - interval '18 years'))",
    );
  });

  it("non chiede documenti su nessuna delle due superfici", () => {
    for (const sorgente of [senzaCommenti(registrati), senzaCommenti(completa)]) {
      expect(sorgente).not.toMatch(/KYC|type="file"|carica.*documento|upload/i);
    }
  });
});

describe("confine server", () => {
  it("lascia intatta la barriera autoritativa del dob", () => {
    // D4 è un lavoro di sola interfaccia: il CHECK sul dob e la funzione usata
    // dalle operazioni sensibili restano dove sono, e nessuna delle due viene
    // sostituita da un controllo client.
    const auth = leggi("../supabase/migrations/20260728000545_auth_profiles_roles.sql");
    expect(auth).toInclude("check (dob <= (current_date - interval '18 years'))");
    expect(leggi("../supabase/migrations/20260729230000_security_invariants.sql")).toInclude(
      "function public.utente_maggiorenne",
    );
  });
});
