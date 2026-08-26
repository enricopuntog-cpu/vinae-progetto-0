import { describe, expect, it } from "bun:test";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

const progetto = join(import.meta.dir, "../../..");
const leggi = (percorso: string) => readFileSync(join(progetto, percorso), "utf8");
const esiste = (percorso: string) => existsSync(join(progetto, percorso));
// Un contratto che vieta una parola deve guardare il codice, non i commenti:
// altrimenti spiegare perche quella cosa e vietata fa fallire la verifica che
// e vietata, e la difesa diventa "non scriverne".
const senzaCommenti = (sorgente: string) =>
  sorgente.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");
const fileRicorsivi = (directory: string): string[] =>
  readdirSync(directory, { withFileTypes: true }).flatMap((voce) => {
    const percorso = join(directory, voce.name);
    return voce.isDirectory() ? fileRicorsivi(percorso) : [percorso];
  });

describe("superfici pubbliche della beta", () => {
  it("non dichiara evidenza IA sull'annuncio senza un dato canonico", () => {
    const dettaglio = leggi("src/app/annuncio/[id]/page-client.tsx");
    expect(dettaglio).not.toInclude('TrustBadge source="ia"');
    expect(dettaglio).toInclude('TrustBadge source="piattaforma"');
  });

  it("invia le proposte con il servizio Phase 7 e non con lo store locale", () => {
    const proposta = leggi("src/components/vinea/ProposalAction.tsx");
    expect(proposta).toInclude("createProposalService(client)");
    expect(proposta).toInclude("service.invia(listingId, cents)");
    expect(proposta).not.toMatch(/\bcreateProposal\(|pushNotifica|toast\.success/);
  });

  it("richiede altre foto soltanto con conversazione e messaggio Phase 8", () => {
    const contatti = leggi("src/components/vinea/ListingContactActions.tsx");
    expect(contatti).toInclude("openConversation({ listingId })");
    expect(contatti).toInclude("await sendMessage({");
    expect(contatti).not.toMatch(/richiediAltreFoto|pushNotifica|toast/);
  });

  it("non espone preferiti o follow locali sulle schede pubbliche", () => {
    const superfici = [
      leggi("src/components/vinea/WineCard.tsx"),
      leggi("src/app/annuncio/[id]/page-client.tsx"),
    ].join("\n");
    expect(superfici).not.toMatch(/toggleFavorite|toggleFollow|Aggiunto ai preferiti|Ora segui/);
  });

  it("inoltra la ricerca regionale dalla landing al catalogo", () => {
    const landing = leggi("src/app/page-client.tsx");
    const pagina = leggi("src/app/esplora/page.tsx");
    const catalogo = leggi("src/app/esplora/page-client.tsx");
    expect(landing).toInclude("/esplora?regione=");
    // Il valore grezzo della query attraversa server e client per la
    // validazione canonica. Non viene più pre-impostato a "Tutte" sul server.
    expect(pagina).toInclude("initialRegion={regione}");
    expect(catalogo).toInclude("risolviRegioneIniziale");
  });

  // Fase 12a. Questo blocco sostituisce "rende irraggiungibile la community
  // dimostrativa", che asseriva il contrario: la #44 aveva reso /community un
  // notFound() perche i suoi dati erano finti, e il 12a la riapre perche ora
  // sono veri. Cio che quel test difendeva - nessun contenuto inventato nella
  // beta pubblica - resta difeso qui, sulle fonti invece che sull'assenza
  // della pagina.
  it("apre i club su dati reali e non sul mock", () => {
    for (const percorso of [
      "src/app/community/page.tsx",
      "src/app/community/[slug]/page.tsx",
      "src/app/community/page-client.tsx",
      "src/app/community/[slug]/page-client.tsx",
    ]) {
      expect(esiste(percorso)).toBeTrue();
      expect(senzaCommenti(leggi(percorso))).not.toInclude("@/data/communities");
    }
    const elenco = senzaCommenti(leggi("src/app/community/page.tsx"));
    const dettaglio = senzaCommenti(leggi("src/app/community/[slug]/page.tsx"));
    expect(elenco).toInclude("createSupabaseClubService");
    expect(dettaglio).toInclude("createSupabaseClubService");
    // Il 404 del dettaglio resta, ma ora e una risposta a uno slug assente e
    // non lo stub che rispondeva 404 a qualunque slug.
    expect(dettaglio).toInclude("if (!club) notFound()");
    expect(elenco).not.toInclude("notFound()");
    expect(leggi("src/components/vinea/Layout.tsx")).toInclude('to: "/community"');
  });

  // Questo test diceva «non riapre la scrittura di contenuti insieme ai club»
  // ed era giusto: era il confine della 12a, che era in sola lettura piu il
  // follow. La 12b e il checkpoint che quel confine lo attraversa, per
  // eccezione esplicita e per nome, quindi il test non viene cancellato ma
  // riscritto sul confine NUOVO - che e piu stretto, non piu largo.
  it("apre la scrittura di contenuti solo insieme al modo di segnalarli", () => {
    const pagine = senzaCommenti(
      [
        leggi("src/app/community/page-client.tsx"),
        leggi("src/app/community/[slug]/page-client.tsx"),
      ].join("\n"),
    );
    // Il mock resta fuori: il "Crea un post" di prima della #44 apriva un
    // toast, e un pulsante che finge in un ambiente che scrive davvero e
    // peggio di un pulsante assente.
    expect(pagine).not.toMatch(/Crea un post|toast|discussions|communityPosts/);
    expect(pagine).toInclude("Discussioni del club");
    expect(pagine).toInclude("Post popolari");
    // "disponibile a breve" non c'e piu perche non c'e piu niente da
    // rimandare.
    expect(pagine).not.toInclude("ClubProssimamente");
    expect(pagine).toInclude("ClubDiscussioni");
  });

  // IL CONTRATTO CHE TIENE INSIEME 12B E 12C, scritto come test e non come
  // buona intenzione. La scrittura di contenuti pubblici e stata ammessa a una
  // condizione: che esista un modo per segnalarli. Se domani qualcuno mostra
  // testo scritto da un utente senza il suo "Segnala", questo test fallisce -
  // che e l'unico modo perche quella condizione sopravviva a chi non ha letto
  // la PR. Stessa forma della prova sulle etichette IA della Fase 10, che
  // impedisce di aggiungere una quarta superficie IA senza etichetta.
  it("ogni testo pubblico dei club ha il suo Segnala", () => {
    const discussioni = leggi("src/components/vinea/ClubDiscussioni.tsx");
    const codice = senzaCommenti(discussioni);
    // Il componente che disegna post e risposte e lo stesso che importa il
    // dialogo di segnalazione: non c'e un percorso in cui il testo compare e
    // il pulsante no.
    expect(codice).toInclude("ReportDialog");
    // I due bersagli che la decisione 7.6a teneva sospesi «finche i club non
    // hanno schema Supabase». Ora ce l'hanno, e sono cablati entrambi.
    expect(codice).toInclude('targetType="post"');
    expect(codice).toInclude('targetType="commento"');
    // I due valori devono esistere davvero anche a database, o il dialogo
    // manderebbe una segnalazione che la RPC rifiuta.
    const enumMigrazione = leggi("../supabase/migrations/20260817120500_phase_12c_report_target_enum.sql");
    expect(enumMigrazione).toInclude("add value if not exists 'post'");
    expect(enumMigrazione).toInclude("add value if not exists 'commento'");
    // E i motivi ammessi devono coincidere con quelli che il client propone:
    // il controllo di elenco chiuso in segnalazione_invia confronta le
    // stringhe, e una differenza di un accento sarebbe un rifiuto a ogni
    // tentativo.
    const moderazione = leggi("../supabase/migrations/20260817121000_phase_12c_club_moderation.sql");
    const dati = leggi("src/data/moderation.ts");
    for (const motivo of [
      "Contenuto inappropriato",
      "Off-topic per il club",
      "Spam commerciale",
      "Disinformazione",
      "Insulti o linguaggio offensivo",
      "Molestia mirata",
    ]) {
      expect(moderazione).toInclude(`'${motivo}'`);
      expect(dati).toInclude(`"${motivo}"`);
    }
  });

  it("non espone la tabella club ne un userId dal client", () => {
    const servizio = senzaCommenti(leggi("src/services/phase12/supabase-club-service.ts"));
    // La lettura passa dalla vista: `clubs` non ha grant per i ruoli client.
    expect(servizio).toInclude('.from("public_clubs")');
    expect(servizio).not.toInclude('.from("clubs")');
    // Il payload dell'insert e fissato per intero: user_id arriva dal DEFAULT
    // del database, e se comparisse qui vorrebbe dire che lo sceglie il client.
    expect(servizio).toInclude('.insert({ club_slug: slug })');
    expect(servizio).toInclude('.delete().eq("club_slug", slug)');
    expect(servizio).not.toMatch(/user_id|userId/);
    // Nessuna delle quattro firme dell'interfaccia accetta un identificativo
    // utente.
    const tipi = leggi("src/services/types.ts");
    const inizio = tipi.indexOf("export interface ClubService");
    const contratto = tipi.slice(inizio, tipi.indexOf("}", inizio));
    expect(inizio).toBeGreaterThan(-1);
    expect(contratto).not.toMatch(/userId|user_id/);
  });

  it("usa il nome profilo autenticato senza identita personale hardcoded", () => {
    const home = leggi("src/app/home/page-client.tsx");
    expect(home).toInclude("authProfileName");
    expect(home).not.toMatch(/Elena Rossi|preferiti|seguiti|communityPosts/);
  });

  /**
   * L'invariante non è cambiato — il profilo si legge dalla riga canonica di
   * `public.profiles` e non da un dato dimostrativo — ma ha cambiato casa: sta
   * in `ProfileService`, non più in `AuthService`, che ora si ferma
   * all'autenticazione e ai ruoli. Il caso è stato riscritto sul confine nuovo
   * invece di essere cancellato, e ne difende **di più**: che l'identificativo
   * non arrivi da fuori.
   */
  it("legge il profilo dalla riga profiles canonica, risolvendo l'utente dalla sessione", () => {
    const profilo = leggi("src/services/profile-service.ts");
    expect(profilo).toInclude('.from("profiles")');
    // Le due firme del profilo risolvono l'utente con `getUser()`, che
    // interroga GoTrue, e non con `getSession()`, che legge il JSON tenuto dal
    // browser: da lì esce anche `email_confirmed_at`, che è l'unico campo di
    // questa schermata che qualcuno avrebbe interesse a ritoccare in locale.
    expect(profilo).toInclude("auth.getUser()");
    expect(profilo).toInclude('.eq("id", utente.id)');
    // L'identificativo esce dalla sessione e non da un argomento: le due firme
    // pubbliche non hanno parametri oltre al patch da scrivere. (`userId`
    // compare come *campo restituito* di ProfiloCorrente, che è un'altra cosa,
    // ed è il motivo per cui qui si guardano le firme e non la parola.)
    expect(profilo).toInclude("async leggiProfiloCorrente()");
    expect(profilo).toInclude("async aggiornaProfiloCorrente(patch: ProfiloModifica)");
  });

  it("auth-service non scrive piu su profiles: una sola porta per quella tabella", () => {
    const auth = leggi("src/services/auth-service.ts");
    expect(auth).not.toInclude('.from("profiles")');
  });

  it("il contratto ProfileService non accetta un identificativo utente", () => {
    const tipi = leggi("src/services/types.ts");
    const inizio = tipi.indexOf("export interface ProfileService");
    expect(inizio).toBeGreaterThan(-1);
    const contratto = tipi.slice(inizio, tipi.indexOf("}", inizio));
    expect(contratto).not.toMatch(/userId|user_id/);
  });

  /**
   * L'avatar di produzione non arriva da un servizio esterno. La demo storica
   * usava `pravatar.cc`: ogni apertura di un profilo sarebbe stata una
   * richiesta a terzi con l'IP di chi guarda.
   */
  it("gli avatar sono serviti da noi, mai da un servizio placeholder esterno", () => {
    // `senzaCommenti` non è un dettaglio: il modulo degli avatar **nomina**
    // pravatar.cc nel commento che spiega perché non lo si usa più, e senza
    // questo filtro spiegare il divieto farebbe fallire la verifica del
    // divieto. Stessa forma già adottata dai contratti della 12a.
    const avatar = senzaCommenti(leggi("src/lib/profilo/avatar.ts"));
    const account = senzaCommenti(leggi("src/app/account/page-client.tsx"));
    for (const sorgente of [avatar, account]) {
      expect(sorgente).not.toMatch(/pravatar|gravatar|placeholder\.com|dicebear/i);
      expect(sorgente).not.toMatch(/https?:\/\/[^\s"')]*avatar/i);
    }
    // La lettura passa dalla convalida, perche' `avatar_url` e' scrivibile dal
    // client e il valore memorizzato non e' fidato.
    expect(account).toInclude("avatarSicuro");
  });

  it("non mostra il promemoria non persistito", () => {
    const finestra = leggi("src/components/vinea/DrinkWindow.tsx");
    expect(finestra).not.toMatch(/Ricordamelo|Promemoria impostato|toast\.success/);
  });

  it("non monta i domini demo rimossi nel provider globale", () => {
    const store = leggi("src/lib/vinea-store.tsx");
    expect(store).not.toMatch(/use(Order|Clubs|Listings|Messaging|Moderation|Profile)Domain/);
    for (const file of [
      "clubs-domain.ts",
      "listings-domain.ts",
      "messaging-domain.ts",
      "moderation-domain.ts",
      "order-domain.ts",
      "profile-domain.ts",
    ]) {
      expect(esiste(`src/lib/store/${file}`)).toBeFalse();
    }
  });

  it("non usa servizi messaggi mock come fallback pubblico", () => {
    const controller = leggi("src/lib/phase8/use-phase8-controller.ts");
    expect(controller).toInclude('mode: client ? "supabase" : "unavailable"');
    expect(controller).not.toInclude("createMockPhase8Services");
    expect(leggi("src/components/vinea/messaging/MessagesPageClient.tsx")).not.toInclude(
      "MOCK_PHASE8_USER_ID",
    );
  });

  it("non usa dati moderazione mock come fallback pubblico", () => {
    const controller = leggi("src/lib/phase9/use-phase9-moderation.ts");
    expect(controller).toInclude('mode: "unavailable" as const');
    expect(controller).not.toMatch(/reportsMock|auditMock|mode: "mock"/);
  });

  it("rimuove personalizzazioni e storico inventato dalla cantina", () => {
    const cantina = leggi("src/app/cantina/page-client.tsx");
    expect(cantina).not.toMatch(/PreferenzeCantina|SfondoDialog|ANDAMENTO|ultimi 12 mesi/);
    expect(cantina).not.toInclude("Somma dei prezzi collegati");
    expect(cantina).toInclude("Valore di riferimento Vinea");
    expect(cantina).toInclude("Capitale noto");
    expect(cantina).toInclude("Incassi trasferiti");
    expect(cantina).toInclude("Performance netta");
  });

  it("blocca il punto logistico demo senza renderlo raggiungibile", () => {
    expect(esiste("src/components/vinea/orders/PackagingPointPicker.tsx")).toBeFalse();
    expect(leggi("src/components/vinea/orders/SellerPrepPanel.tsx")).toInclude(
      '<BetaActionNotice tipo="spedizione"',
    );
  });

  it("fallisce chiuso quando il servizio segnalazioni non e configurato", () => {
    const report = leggi("src/components/vinea/ReportDialog.tsx");
    const controllo = report.indexOf("if (!client)");
    const invio = report.indexOf("createSupabaseModerationService(client).segnala");
    expect(controllo).toBeGreaterThan(-1);
    expect(invio).toBeGreaterThan(controllo);
  });

  it("non lascia identita demo nel runtime delle route pubbliche", () => {
    const sorgenti = ["src/app", "src/components", "src/hooks", "src/lib/store"]
      .flatMap((directory) => fileRicorsivi(join(progetto, directory)))
      .filter((file) => /\.(ts|tsx)$/.test(file) && !file.endsWith(".test.ts"))
      .map((file) => readFileSync(file, "utf8"))
      .join("\n");
    expect(sorgenti).not.toMatch(/Elena Rossi|elena@demo\.it|i\.pravatar\.cc/);
  });
});
