/**
 * Gli ingressi al profilo pubblico: annuncio, Messaggi, Club.
 *
 * `/profilo/[id]` e il servizio che lo alimenta sono CLOSED e hanno gia i loro
 * test. Qui si verifica l'altra meta del problema — che quella pagina sia
 * raggiungibile — e soprattutto il modo in cui lo e: riusando identita che i
 * read model gia portano, senza aprire una seconda lettura del profilo.
 *
 * La forma e quella dei contratti di sorgente gia in uso nel progetto
 * (`app/profilo/[id]/page.test.ts`, `lib/beta/public-surface-contract.test.ts`):
 * il pacchetto non ha una libreria DOM e questo lavoro non e una ragione per
 * introdurne una.
 */

import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { wines } from "@/data/wines";
import { rigaAWine, type PublicListingRow } from "@/services/listing-service";

const progetto = join(import.meta.dir, "../../..");
const leggi = (percorso: string) => readFileSync(join(progetto, percorso), "utf8");

// Un contratto che vieta una parola deve guardare il codice, non i commenti:
// altrimenti spiegare perche quella cosa e vietata fa fallire la verifica.
const senzaCommenti = (sorgente: string) =>
  sorgente
    .replace(/\{\s*\/\*[\s\S]*?\*\/\s*\}/g, "")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/.*$/gm, "$1");

const SORGENTI = {
  annuncio: "src/app/annuncio/[id]/page-client.tsx",
  conversazioneHeader: "src/components/vinea/messaging/ConversationHeader.tsx",
  conversazioneList: "src/components/vinea/messaging/ConversationList.tsx",
  clubDiscussioni: "src/components/vinea/ClubDiscussioni.tsx",
  clubScheda: "src/app/community/[slug]/page-client.tsx",
  listingService: "src/services/listing-service.ts",
} as const;

const VENDITORE = "11111111-1111-4111-8111-111111111111";

const RIGA: PublicListingRow = {
  id: "99999999-9999-4999-8999-999999999999",
  slug: "barolo-2018",
  prezzo_cents: 5000,
  prezzo_mercato_cents: null,
  quantita: 1,
  condizione: "Perfetto",
  conservazione: "Cantina",
  storia: "",
  degustazione: "",
  immagini: null,
  tag: null,
  published_at: "2026-08-21T00:00:00Z",
  created_at: "2026-08-21T00:00:00Z",
  pubblicato_at: "2026-08-21T00:00:00Z",
  wine_id: "88888888-8888-4888-8888-888888888888",
  wine_slug: "barolo",
  produttore: "Vinea",
  nome: "Barolo",
  annata: 2018,
  regione: "Piemonte",
  denominazione: "Barolo DOCG",
  tipo: "Rosso",
  formato: "0,75 L",
  ricerca: "barolo",
  seller_id: VENDITORE,
  seller_username: "elena",
  seller_citta: "Milano",
  seller_avatar_url: "",
  wine_provenienza: "staff",
  seller_verificato: false,
};

describe("annuncio: identita del venditore", () => {
  it("conserva `seller_id` come identita del venditore", () => {
    expect(rigaAWine(RIGA).venditore.userId).toBe(VENDITORE);
  });

  it("non lega l'identita alla spunta: un venditore certificato e uno no hanno lo stesso id", () => {
    expect(rigaAWine({ ...RIGA, seller_verificato: true }).venditore.userId).toBe(VENDITORE);
    expect(rigaAWine({ ...RIGA, seller_verificato: false }).venditore.userId).toBe(VENDITORE);
  });

  it("non inventa un profilo per i dati dimostrativi", () => {
    expect(wines.length).toBeGreaterThan(0);
    for (const vino of wines) {
      expect(vino.venditore.userId).toBeUndefined();
    }
  });

  it("porta il riferimento dell'avatar, non l'indirizzo gia ricomposto", () => {
    // `AvatarPersona` verifica la cartella e ricompone l'URL da se: ricevere un
    // indirizzo lo farebbe cadere sulla silhouette anche per una foto vera.
    const foto = `${VENDITORE}/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.webp`;
    const venditore = rigaAWine({ ...RIGA, seller_avatar_url: foto }).venditore;
    expect(venditore.avatarRef).toBe(foto);
    expect(venditore.avatarRef).not.toInclude("http");
  });

  it("non lascia passare la foto di un altro venditore ne un URL esterno", () => {
    const altrui = "22222222-2222-4222-8222-222222222222/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.webp";
    expect(rigaAWine({ ...RIGA, seller_avatar_url: altrui }).venditore.avatarRef).toBe("");
    expect(
      rigaAWine({ ...RIGA, seller_avatar_url: "https://evil.example/a.webp" }).venditore.avatarRef,
    ).toBe("");
  });

  it("legge l'identita dalla riga gia in mano, senza una seconda interrogazione", () => {
    const codice = senzaCommenti(leggi(SORGENTI.listingService));
    // `seller_id` e gia nella proiezione: la prova e che non compaia una
    // seconda `select` verso il profilo per ottenere lo stesso valore.
    expect(codice).toInclude("userId: riga.seller_id");
    expect(codice).not.toMatch(/\.from\(["']profiles["']\)/);
  });
});

describe("annuncio: la scheda venditore porta al profilo", () => {
  const sorgente = leggi(SORGENTI.annuncio);
  const codice = senzaCommenti(sorgente);

  it("costruisce la destinazione solo dall'identita reale del venditore", () => {
    expect(codice).toInclude(
      "const profiloVenditore = wine.venditore.userId ? `/profilo/${wine.venditore.userId}` : null;",
    );
  });

  it("collega sia l'avatar sia lo username alla stessa destinazione", () => {
    expect(codice).toInclude('data-testid="annuncio-venditore-avatar"');
    expect(codice).toInclude('data-testid="annuncio-venditore-username"');
    expect(codice.match(/href=\{profiloVenditore\}/g)).toHaveLength(2);
  });

  it("senza identita non disegna nessun link", () => {
    // I due rami `profiloVenditore ? ... : ...` sono la prova che l'assenza ha
    // una resa propria e non produce un href verso `/profilo/undefined`.
    expect(codice.match(/profiloVenditore \? \(/g)).toHaveLength(2);
    expect(codice).not.toMatch(/\/profilo\/\$\{[^}]*\}\s*`?\s*}?\s*>/);
    expect(codice).not.toInclude("/profilo/undefined");
  });

  it("disegna il venditore con la foundation chiusa, silhouette in fondo", () => {
    // Il fondo della catena e la silhouette, non le iniziali: `inizialiDa()` e
    // rimasto alla schermata profilo e qui non deve ricomparire.
    expect(codice).toInclude("<AvatarPersona");
    expect(codice).toInclude("avatarUrl={wine.venditore.avatarRef}");
    expect(codice).toInclude("proprietarioId={wine.venditore.userId}");
    expect(codice).not.toInclude("inizialiDa");
    expect(codice).not.toInclude("<img src={wine.venditore.avatar}");
  });

  it("non usa `verificato` per decidere se il profilo esiste", () => {
    for (const riga of codice.split("\n")) {
      if (riga.includes("/profilo")) expect(riga).not.toInclude("verificato");
      if (riga.includes("profiloVenditore")) expect(riga).not.toInclude("verificato");
    }
  });

  it("non tocca il comportamento commerciale della scheda", () => {
    expect(sorgente).toInclude("<ProposalAction");
    expect(sorgente).toInclude("<ListingContactActions");
    expect(sorgente).toInclude("<ListingOwnerActions");
  });
});

describe("messaggi: l'intestazione porta al profilo della controparte", () => {
  const sorgente = leggi(SORGENTI.conversazioneHeader);
  const codice = senzaCommenti(sorgente);

  it("usa `counterpart.userId`, che il read model gia porta", () => {
    expect(codice).toInclude(
      "const profiloControparte = `/profilo/${conversation.counterpart.userId}`;",
    );
    expect(codice).not.toMatch(/\.from\(|createClient|Service\(/);
  });

  it("collega avatar e username alla stessa destinazione", () => {
    expect(codice).toInclude('data-testid="conversazione-controparte-avatar"');
    expect(codice).toInclude('data-testid="conversazione-controparte-username"');
    expect(codice.match(/href=\{profiloControparte\}/g)).toHaveLength(2);
  });

  it("disegna l'avatar con la foundation chiusa e non con la stringa grezza", () => {
    expect(codice).toInclude("<AvatarPersona");
    expect(codice).toInclude("proprietarioId={conversation.counterpart.userId}");
    expect(codice).not.toInclude("<img src={conversation.counterpart.avatarUrl}");
    expect(codice).not.toMatch(/risolviAvatar|avatarSicuro|inizialiDa/);
  });

  it("lascia intatto l'annuncio collegato", () => {
    expect(codice.match(/href=\{`\/annuncio\/\$\{conversation\.listingSlug\}`\}/g)).toHaveLength(2);
    expect(codice).toInclude("Annuncio collegato");
    expect(codice).toInclude("src={conversation.wineImage}");
  });

  it("disegna la miniatura dell'annuncio con la foundation e non con un `img` grezzo", () => {
    // `conversations_page` proietta `coalesce(l.immagini[1], '')`: senza
    // foundation un annuncio senza foto diventa `src=""`, cioè il riquadro
    // rotto. Il soggetto qui è che la miniatura non sia più un `<img>` nudo.
    expect(codice).toInclude("<SafeImage");
    expect(codice).not.toMatch(/<img\b/);
    expect(codice).toInclude('data-testid="conversazione-annuncio-immagine"');
    // Il valore è quello che la conversazione porta già: nessuna lettura in più.
    expect(codice).not.toMatch(/\.from\(|createClient|Service\(|fetch\(/);
  });

  it("non annida un link dentro un altro e non tocca back o composer", () => {
    // I link della persona e dell'annuncio sono fratelli dentro lo stesso
    // `<span>`: se uno dei due finisse dentro l'altro, fra i due `<Link` non ci
    // sarebbe una chiusura `</Link>`.
    const apre = [...codice.matchAll(/<Link\b/g)].map((m) => m.index ?? 0);
    const chiude = [...codice.matchAll(/<\/Link>/g)].map((m) => m.index ?? 0);
    expect(apre).toHaveLength(chiude.length);
    for (let i = 0; i + 1 < apre.length; i += 1) {
      expect(chiude[i]!).toBeLessThan(apre[i + 1]!);
    }
    expect(codice).toInclude("onClick={onBack}");
    expect(codice).toInclude('aria-label="Indietro"');
  });
});

describe("messaggi: l'elenco resta un selettore", () => {
  const codice = senzaCommenti(leggi(SORGENTI.conversazioneList));

  it("migliora l'avatar con la stessa foundation", () => {
    expect(codice).toInclude("<AvatarPersona");
    expect(codice).toInclude("proprietarioId={conversation.counterpart.userId}");
  });

  it("non introduce un link dentro il bottone di selezione", () => {
    expect(codice).not.toInclude("/profilo/");
    expect(codice).not.toInclude("next/link");
    expect(codice).not.toInclude("<Link");
    expect(codice).toInclude("onClick={() => onSelect(conversation.id)}");
  });
});

describe("club: gli autori sono persone raggiungibili", () => {
  const sorgente = leggi(SORGENTI.clubDiscussioni);
  const codice = senzaCommenti(sorgente);

  it("collega l'autore di un post con `autoreId`", () => {
    expect(codice).toInclude("href={`/profilo/${post.autoreId}`}");
    expect(codice).toInclude("{post.autoreUsername}");
  });

  it("collega l'autore di una risposta con `autoreId`", () => {
    expect(codice).toInclude("href={`/profilo/${r.autoreId}`}");
    expect(codice).toInclude("{r.autoreUsername}");
  });

  it("non apre nessuna lettura del profilo per farlo", () => {
    expect(codice).not.toMatch(/\.from\(["']profiles["']\)|profilo\(|PublicProfileService/);
  });

  it("lascia intatti like, risposta, segnalazione e modalita di pubblicazione", () => {
    expect(sorgente).toInclude("azioni.cambiaLike");
    expect(sorgente).toInclude("azioni.rispondi");
    expect(sorgente).toInclude("<ReportDialog");
    expect(sorgente).toInclude("puoScrivere");
  });
});

describe("club: il creatore della scheda", () => {
  const codice = senzaCommenti(leggi(SORGENTI.clubScheda));

  it("e linkabile soltanto quando `ownerId` esiste", () => {
    expect(codice).toInclude("club.ownerId ? (");
    expect(codice).toInclude("href={`/profilo/${club.ownerId}`}");
    expect(codice).toInclude("club.ownerUsername");
  });

  it("non aggiunge una sezione proprietario nuova", () => {
    // Il creatore resta la riga che c'era: una sola, con il suo testid
    // originale. Il link vive dentro quella riga, non in un blocco in piu.
    expect(codice.match(/data-testid="club-creatore"/g)).toHaveLength(1);
    expect(codice.match(/Creato da/g)).toHaveLength(1);
  });
});

describe("invarianti degli ingressi", () => {
  const tutte = Object.values(SORGENTI)
    .map((percorso) => senzaCommenti(leggi(percorso)))
    .join("\n");

  it("nessuna lettura diretta di `profiles` e nessun service_role", () => {
    expect(tutte).not.toMatch(/\.from\(["']profiles["']\)/);
    expect(tutte).not.toMatch(/service_role|SERVICE_ROLE/);
  });

  it("nessun servizio profilo nuovo e nessuna directory di persone", () => {
    expect(tutte).not.toMatch(/creaPublicProfileService|createProfileService/);
    expect(tutte).not.toMatch(/listaUtenti|cercaUtenti|peopleDirectory|elencoProfili/i);
  });

  it("nessun link al profilo deciso da `seller_verificato`", () => {
    for (const riga of tutte.split("\n")) {
      if (riga.includes("/profilo/")) {
        expect(riga).not.toMatch(/verificato|TrustBadge|ShieldCheck/);
      }
    }
  });
});
