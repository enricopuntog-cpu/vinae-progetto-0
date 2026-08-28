import { describe, expect, it } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import {
  NAV_MOBILE_AUTENTICATA,
  NAV_MOBILE_OSPITE,
  classiRicercaHeader,
  navMobile,
  percorsoAttivo,
  voceNavAttiva,
  type VoceNavMobile,
} from "@/lib/shell/navigazione-mobile";

const progetto = join(import.meta.dir, "../../..");
const leggi = (percorso: string) => readFileSync(join(progetto, percorso), "utf8");

/**
 * Una voce vale solo se la sua rotta esiste davvero. `src/app/<rotta>/page.tsx`
 * e' l'unica prova che serve, e sposta il fallimento dal browser al test.
 */
const rottaEsiste = (to: string) =>
  existsSync(join(progetto, "src/app", to === "/" ? "page.tsx" : `${to.slice(1)}/page.tsx`));

const etichette = (voci: readonly VoceNavMobile[]) => voci.map((v) => v.label);

describe("barra mobile", () => {
  it("da autenticati e' esattamente Home / Ricerca / Vendi / Club / Cantina", () => {
    expect(etichette(NAV_MOBILE_AUTENTICATA)).toEqual([
      "Home",
      "Ricerca",
      "Vendi",
      "Club",
      "Cantina",
    ]);
    expect(navMobile(true)).toBe(NAV_MOBILE_AUTENTICATA);
  });

  it("da autenticati Account non e' nella barra e Cantina si'", () => {
    expect(etichette(NAV_MOBILE_AUTENTICATA)).not.toContain("Account");
    const cantina = NAV_MOBILE_AUTENTICATA.find((v) => v.label === "Cantina");
    expect(cantina?.to).toBe("/cantina");
  });

  it("da autenticati Home porta a /home", () => {
    expect(NAV_MOBILE_AUTENTICATA[0]!.to).toBe("/home");
  });

  it("la barra ospite resta quella di prima", () => {
    expect(etichette(NAV_MOBILE_OSPITE)).toEqual([
      "Home",
      "Ricerca",
      "Vendi",
      "Club",
      "Account",
    ]);
    expect(NAV_MOBILE_OSPITE[0]!.to).toBe("/");
    expect(navMobile(false)).toBe(NAV_MOBILE_OSPITE);
  });

  it("entrambe le barre hanno cinque voci, quante ne disegna la griglia", () => {
    expect(NAV_MOBILE_OSPITE).toHaveLength(5);
    expect(NAV_MOBILE_AUTENTICATA).toHaveLength(5);
    const layout = leggi("src/components/vinea/Layout.tsx");
    expect(layout).toInclude("grid-cols-5");
  });

  it("ogni voce punta a una rotta che esiste davvero", () => {
    for (const voce of [...NAV_MOBILE_OSPITE, ...NAV_MOBILE_AUTENTICATA]) {
      expect(rottaEsiste(voce.to)).toBe(true);
    }
  });
});

// Senza queste asserzioni la shell potrebbe disegnare sempre la stessa barra e
// tutti gli altri test resterebbero verdi: `navMobile()` e' verificato sopra,
// ma nessuno provava che il layout la chiami davvero, ne' da che cosa ricavi
// l'essere autenticato.
describe("la shell sceglie la barra dal ruolo", () => {
  const layout = leggi("src/components/vinea/Layout.tsx");

  it("ricava l'essere autenticato dal ruolo e non da un secondo segnale", () => {
    expect(layout).toInclude('const autenticato = ruolo !== "guest";');
    // `ruolo` arriva dallo store, non da una prop ne' da un secondo hook.
    // L'elenco destrutturato non e' fissato: la shell legge dallo stesso hook
    // anche altri campi - da D10 `authRuolo`, per la voce Admin - e bloccare la
    // riga intera avrebbe fatto fallire questa asserzione per una ragione che
    // non e' la sua. Cio' che deve restare vero e' che `autenticato` abbia una
    // sorgente sola, ed e' la riga sopra piu' il conteggio qui sotto a dirlo.
    expect(layout).toMatch(/const \{[^}]*\bruolo\b[^}]*\} = useVinea\(\);/);
    expect(layout.match(/const autenticato =/g) ?? []).toHaveLength(1);
  });

  it("la barra disegnata e' quella scelta dal ruolo, non una lista fissa", () => {
    expect(layout).toInclude("const vociMobile = navMobile(autenticato);");
    expect(layout).toInclude("{vociMobile.map((n) => {");
    // Nessuna delle due liste e' nominata nel componente: se lo fosse, la
    // scelta sarebbe scavalcabile senza toccare `navMobile()`.
    expect(layout).not.toMatch(/NAV_MOBILE_(?:OSPITE|AUTENTICATA)/);
  });

  it("con lo switcher demo spento il ruolo e' quello della sessione vera", () => {
    const store = leggi("src/lib/vinea-store.tsx");
    const dominio = leggi("src/lib/store/auth-domain.ts");
    const ruoli = leggi("src/lib/auth/role.ts");
    expect(store).toInclude("ruoloReale: realAuthDomain.authRuolo");
    expect(store).toInclude("demoAbilitata: DEMO_UI_ABILITATA");
    expect(dominio).toInclude("ruolo: demoAbilitata ? ruolo : ruoloReale");
    // Fail-closed: senza sessione il ruolo reale e' "guest", quindi la barra
    // autenticata non puo' comparire per default con la demo spenta.
    expect(ruoli).toInclude('if (!authUser) return "guest";');
  });
});

describe("stato attivo della barra mobile", () => {
  const voce = (voci: readonly VoceNavMobile[], label: string) =>
    voci.find((v) => v.label === label)!;

  it("accende una sola voce per volta", () => {
    for (const pathname of ["/home", "/esplora", "/vendi", "/community", "/cantina"]) {
      const attive = NAV_MOBILE_AUTENTICATA.filter((v) => voceNavAttiva(v, pathname));
      expect(attive).toHaveLength(1);
    }
  });

  it("Cantina resta accesa sulle pagine figlie", () => {
    const cantina = voce(NAV_MOBILE_AUTENTICATA, "Cantina");
    expect(voceNavAttiva(cantina, "/cantina")).toBe(true);
    expect(voceNavAttiva(cantina, "/cantina/abc/degustazione")).toBe(true);
  });

  // `/vendite` e' una rotta reale: con il vecchio `startsWith` nudo accendeva
  // `Vendi`, che porta altrove. Il confronto col separatore lo impedisce.
  it("non accende Vendi su /vendite", () => {
    const vendi = voce(NAV_MOBILE_AUTENTICATA, "Vendi");
    expect(rottaEsiste("/vendite")).toBe(true);
    expect(voceNavAttiva(vendi, "/vendite")).toBe(false);
    expect(voceNavAttiva(vendi, "/vendi")).toBe(true);
  });

  it("Home e' esatta e copre sia / sia /home", () => {
    const home = voce(NAV_MOBILE_AUTENTICATA, "Home");
    expect(voceNavAttiva(home, "/home")).toBe(true);
    expect(voceNavAttiva(home, "/")).toBe(true);
    expect(voceNavAttiva(home, "/esplora")).toBe(false);
    expect(voceNavAttiva(voce(NAV_MOBILE_OSPITE, "Home"), "/")).toBe(true);
  });

  it("la barra disegna aria-current dallo stato attivo", () => {
    const layout = leggi("src/components/vinea/Layout.tsx");
    expect(layout).toInclude("const active = voceNavAttiva(n, pathname);");
    expect(layout).toInclude('aria-current={active ? "page" : undefined}');
  });

  it("il layout mobile e la safe area restano", () => {
    const layout = leggi("src/components/vinea/Layout.tsx");
    expect(layout).toInclude("pb-safe");
    expect(layout).toInclude("pb-[calc(5rem+env(safe-area-inset-bottom))] md:pb-0");
  });
});

describe("azioni dell'header autenticato", () => {
  const layout = leggi("src/components/vinea/Layout.tsx");
  const azioni = layout.slice(layout.indexOf('className="ml-auto flex items-center gap-2"'));

  it("da autenticati la lente sparisce su mobile e resta su desktop", () => {
    expect(classiRicercaHeader(true)).toBe("hidden md:inline-flex");
    expect(classiRicercaHeader(true)).toInclude("hidden");
    expect(layout).toInclude("${classiRicercaHeader(autenticato)}");
  });

  // La lente ospite non cambia di una classe: e' il pezzo di header che questo
  // task non deve toccare.
  it("da ospiti la lente resta il link di prima", () => {
    expect(classiRicercaHeader(false)).toBe("");
    const ricerca = azioni.slice(azioni.indexOf('data-testid="header-search-link"'));
    expect(ricerca).toInclude('className={`rounded-full p-2 hover:bg-secondary');
  });

  it("Messaggi e Notifiche ci sono e vengono dall'infrastruttura esistente", () => {
    expect(azioni).toInclude("<HeaderInboxActions />");
    const inbox = leggi("src/components/vinea/notifications/HeaderInboxActions.tsx");
    expect(inbox).toInclude('href="/messaggi"');
    expect(inbox).toInclude('aria-label="Messaggi"');
    expect(inbox).toInclude('aria-label="Notifiche"');
    // L'ordine richiesto: Messaggi prima, Notifiche poi.
    expect(inbox.indexOf('aria-label="Messaggi"')).toBeLessThan(
      inbox.indexOf('aria-label="Notifiche"'),
    );
    expect(rottaEsiste("/messaggi")).toBe(true);
    expect(rottaEsiste("/notifiche")).toBe(true);
  });

  it("l'avatar e' l'ultima azione, quindi all'estrema destra", () => {
    const posRicerca = azioni.indexOf('data-testid="header-search-link"');
    const posInbox = azioni.indexOf("<HeaderInboxActions />");
    const posAvatar = azioni.indexOf("header-avatar-link");
    expect(posRicerca).toBeGreaterThan(-1);
    expect(posInbox).toBeGreaterThan(posRicerca);
    expect(posAvatar).toBeGreaterThan(posInbox);

    // Dopo l'avatar il contenitore deve chiudersi e basta. Si delimita la coda
    // sul `</div>` che chiude la riga di azioni e si verifica che non contenga
    // altro markup: un `indexOf("</div>")` da solo sarebbe sempre vero.
    const coda = azioni.slice(azioni.indexOf("</Link>", posAvatar) + "</Link>".length);
    const resto = coda.slice(0, coda.indexOf("</div>"));
    expect(resto.replace(/[\s)}]/g, "")).toBe("");
  });

  it("l'avatar porta ad /account, e' etichettato e mostra solo da autenticati", () => {
    expect(azioni).toInclude("{autenticato && (");
    expect(azioni).toInclude('href="/account"');
    expect(azioni).toInclude('aria-label="Account"');
    expect(rottaEsiste("/account")).toBe(true);
  });

  // Stessa classe di difetto di `/vendite` su `Vendi`: il prefisso nudo
  // annuncerebbe "pagina corrente" su una rotta che comincia per /account
  // senza esserlo. Oggi non ce n'e' una, ed e' proprio per questo che il
  // confronto va fissato adesso e non dopo che qualcuno la aggiunge.
  it("l'aria-current dell'avatar usa il confronto col separatore", () => {
    expect(azioni).toInclude('percorsoAttivo("/account", pathname)');
    expect(azioni).not.toInclude('pathname.startsWith("/account")');
    expect(percorsoAttivo("/account", "/account")).toBe(true);
    expect(percorsoAttivo("/account", "/account/avatar")).toBe(true);
    expect(percorsoAttivo("/account", "/accounting")).toBe(false);
  });

  it("usa il componente avatar riusabile con i dati del profilo reale", () => {
    expect(azioni).toInclude("<AvatarPersona");
    expect(azioni).toInclude("avatarUrl={authProfilo?.avatarUrl}");
    expect(azioni).toInclude("proprietarioId={authProfilo?.userId}");
  });

  it("non introduce messaggistica nuova nel layout", () => {
    expect(layout).not.toMatch(/sendMessage|openConversation|createMessag/);
  });
});

describe("avatar riusabile", () => {
  const componente = leggi("src/components/vinea/AvatarPersona.tsx");

  it("delega la priorita al resolver della foundation, senza riscriverla", () => {
    expect(componente).toInclude("risolviAvatarPersona");
    expect(componente).not.toMatch(/storage\/v1\/object|avatar-profili|CATALOGO_AVATAR/);
  });

  it("la silhouette e' un export a se', non un pezzo dell'header", () => {
    expect(componente).toInclude("export const SilhouettePersona");
    expect(componente).toInclude("export const AvatarPersona");
  });

  it("non usa le iniziali come fondo della catena", () => {
    expect(componente).not.toInclude("inizialiDa");
  });

  it("la silhouette e' disegnata inline e non chiede la rete", () => {
    expect(componente).toInclude("<svg");
    expect(componente).not.toMatch(/<img|src=\{?["'`]?https?:/);
  });

  it("disegna l'immagine solo quando c'e' un URL risolto", () => {
    expect(componente).toInclude("{avatar.url ? <AvatarImage");
  });
});

describe("home autenticata", () => {
  const home = leggi("src/app/home/page-client.tsx");

  it("saluta con il nome del profilo reale", () => {
    expect(home).toInclude("Bentornato, {nome}");
    expect(home).toInclude("authProfileName");
    expect(home).toInclude("nome={authProfileName}");
  });

  it("tiene gli stati di caricamento e profilo mancante", () => {
    expect(home).toInclude("if (authLoading) return <LoadingBlock");
    expect(home).toInclude("if (!authUser) return <AccessRequired />");
    expect(home).toInclude("if (authProfileLoading) return <LoadingBlock");
    expect(home).toInclude("if (!authProfileName) return <ProfileMissing />");
  });

  it("tiene l'accesso alla Cantina e non diventa un cruscotto di vendita", () => {
    expect(home).toInclude('href="/cantina"');
    expect(home).not.toMatch(/Saldo|Balance|payout|venditore verificato/i);
  });
});
