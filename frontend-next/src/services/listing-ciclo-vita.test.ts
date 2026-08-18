import { describe, expect, it } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import {
  ETICHETTA_STATO,
  STATI_MODIFICABILI,
  STATI_SOSPENDIBILI,
  rigaProprietarioAWine,
  type ListingStato,
} from "@/services/listing-service";

const progetto = join(import.meta.dir, "../..");
const radice = join(progetto, "..");
const leggi = (percorso: string) => readFileSync(join(progetto, percorso), "utf8");
const leggiRepo = (percorso: string) => readFileSync(join(radice, percorso), "utf8");
// Un contratto che vieta una parola deve guardare il codice, non i commenti:
// altrimenti spiegare perche' quella cosa e' vietata fa fallire la verifica che
// e' vietata. Stessa ragione, e stessa forma, di public-surface-contract.
const senzaCommenti = (sorgente: string) =>
  sorgente.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");
// In SQL il commento e' `--`, non `//`. Senza questa il caso "non allarga il
// GRANT UPDATE" leggeva anche la prosa che spiega perche' non lo allarga, e
// falliva su quella: e' lo stesso difetto che la #50 aveva gia' pagato con
// `pravatar`, cioe' spiegare il divieto facendo fallire la verifica del
// divieto. Trovato eseguendo, non leggendo.
const senzaCommentiSql = (sorgente: string) => sorgente.replace(/^\s*--.*$/gm, "");

/** I nove valori di `public.listing_stato`, letti dal progetto reale. */
const STATI: ListingStato[] = [
  "bozza",
  "in_revisione",
  "modifiche_richieste",
  "attivo",
  "riservato",
  "sospeso",
  "scaduto",
  "venduto",
  "rifiutato",
];

const PROPOSTA_RLS = "supabase/queries/04_PROPOSTA_NON_ESEGUIRE_MODIFICA_ANNUNCIO_ATTIVO.sql";

const rigaMinima = {
  id: "11111111-1111-4111-8111-111111111111",
  slug: "barolo-prova-2018",
  stato: "sospeso" as ListingStato,
  prezzo_cents: 12345,
  prezzo_mercato_cents: null,
  condizione: "Ottimo",
  conservazione: "Cantina interrata",
  storia: "Comprata in cantina.",
  degustazione: "",
  immagini: ["utente-1/foto-a.jpg"],
  tag: null,
  published_at: null,
  created_at: "2026-08-19T10:00:00Z",
  bottle_units: {
    wines: {
      id: "22222222-2222-4222-8222-222222222222",
      slug: "barolo-prova",
      produttore: "Prova",
      nome: "Barolo",
      annata: 2018,
      regione: "Piemonte",
      denominazione: "DOCG",
      tipo: "Rosso",
      formato: "0,75 L",
      provenienza: "utente" as const,
    },
  },
  profiles: { username: "enrico", citta: "Torino", avatar_url: "/avatar/uno.svg" },
};

describe("stati del ciclo di vita di un annuncio", () => {
  it("nomina tutti e nove gli stati dell'enum, nessuno escluso", () => {
    // Se un domani l'enum cresce, la pagina del proprietario mostrerebbe
    // `undefined` come stato. Meglio che a protestare sia questo test.
    for (const stato of STATI) {
      expect(ETICHETTA_STATO[stato]).toBeString();
      expect(ETICHETTA_STATO[stato].length).toBeGreaterThan(0);
    }
    expect(Object.keys(ETICHETTA_STATO).sort()).toEqual([...STATI].sort());
  });

  it("consente di sospendere soltanto da 'attivo', come la RPC", () => {
    // `listing_sospendi` solleva P0001 «Si puo' sospendere solo un annuncio
    // attivo» da qualunque altro stato: un comando mostrato altrove porterebbe
    // l'utente dritto a un rifiuto.
    expect([...STATI_SOSPENDIBILI]).toEqual(["attivo"]);
  });

  it("NON considera modificabile un annuncio attivo finche' la RLS non e' applicata", () => {
    // Questo test e' scritto per fallire il giorno in cui la proposta viene
    // applicata SENZA aggiornare l'elenco, e viceversa. Le due cose devono
    // muoversi insieme: un pulsante che scrive dove la policy non fa passare
    // torna indietro con zero righe modificate e nessun errore, cioe' il
    // peggiore dei modi di non funzionare.
    expect([...STATI_MODIFICABILI]).toEqual(["bozza", "modifiche_richieste"]);
    expect(STATI_MODIFICABILI).not.toContain("attivo");
  });

  it("tiene la proposta RLS fuori da supabase/migrations/", () => {
    // Sotto migrations/ il merge la applicherebbe da se' al progetto reale
    // (7.10) e il ramo di preview la eseguirebbe all'apertura della PR:
    // esattamente cio' che l'autorizzazione separata deve poter fermare.
    expect(existsSync(join(radice, PROPOSTA_RLS))).toBe(true);
    const proposta = leggiRepo(PROPOSTA_RLS);
    expect(proposta).toInclude("NON ESEGUIRE SENZA AUTORIZZAZIONE ESPLICITA");
    expect(proposta).toInclude("'bozza', 'modifiche_richieste', 'attivo'");
  });

  it("porta con se' la guardia 9b sull'UPDATE, non solo l'allentamento", () => {
    // Meta' della proposta che nessuno aveva chiesto: senza questa,
    // `listings_update_own` esteso ad 'attivo' lascerebbe a un utente sospeso
    // al primo livello la riscrittura di un annuncio pubblico.
    const proposta = leggiRepo(PROPOSTA_RLS);
    expect(proposta).toInclude("before insert or update on public.listings");
    expect(proposta).toInclude("private.scrittura_social_guard()");
  });

  it("non allarga il GRANT UPDATE per colonna", () => {
    // La difesa contro un venditore che si scrive lo stato e' il GRANT, non la
    // policy: se la proposta lo toccasse, il `with check` che non nomina lo
    // stato smetterebbe di essere sicuro.
    const proposta = senzaCommentiSql(leggiRepo(PROPOSTA_RLS));
    expect(proposta).not.toMatch(/grant\s+update/i);
    expect(proposta).not.toMatch(/\brevoke\b/i);
    // Gli unici due statement eseguibili sono la policy e il trigger.
    expect(proposta).toInclude('create policy "listings_update_own"');
    expect(proposta).toInclude("create trigger listings_scrittura_social_guard");
  });
});

describe("lettura dell'annuncio da parte del proprietario", () => {
  it("costruisce il Wine da tabella, bottiglia e vino", () => {
    const wine = rigaProprietarioAWine(rigaMinima);
    expect(wine).not.toBeNull();
    expect(wine!.id).toBe("barolo-prova-2018");
    expect(wine!.listingId).toBe(rigaMinima.id);
    expect(wine!.wineSlug).toBe("barolo-prova");
    expect(wine!.prezzo).toBe(123.45);
    expect(wine!.produttore).toBe("Prova");
    expect(wine!.venditore.nome).toBe("enrico");
  });

  it("restituisce null quando il vino non e' raggiungibile", () => {
    // Puo' succedere: `wines` ha le sue policy, e una riga non leggibile
    // arriverebbe come innesto vuoto. Meglio nessuna scheda che una scheda
    // senza nome del vino.
    expect(rigaProprietarioAWine({ ...rigaMinima, bottle_units: null })).toBeNull();
    expect(rigaProprietarioAWine({ ...rigaMinima, bottle_units: { wines: null } })).toBeNull();
  });

  it("non perde prezzo, foto e descrizione di un annuncio sospeso", () => {
    // E' la garanzia della Parte A: la sospensione toglie la visibilita', non
    // i dati.
    const wine = rigaProprietarioAWine({ ...rigaMinima, stato: "sospeso" });
    expect(wine!.prezzo).toBe(123.45);
    expect(wine!.storia).toBe("Comprata in cantina.");
    expect(wine!.conservazione).toBe("Cantina interrata");
    expect(wine!.immagini).toHaveLength(1);

    // Una fotografia gia' pubblica passa intatta: e' l'unico caso in cui
    // l'esito non dipende da `NEXT_PUBLIC_SUPABASE_URL`, che nell'ambiente di
    // test non c'e'. Con quella variabile assente `urlImmagine()` ripiega sul
    // segnaposto per i percorsi di bucket, ed e' un comportamento del
    // trasformatore di URL, non una perdita di dati: `immaginiPercorsi` porta
    // comunque i percorsi grezzi, che sono cio' che `aggiorna()` riscrive.
    const conStatico = rigaProprietarioAWine({
      ...rigaMinima,
      stato: "sospeso",
      immagini: ["/images/vinea-bottle-3.jpg"],
    });
    expect(conStatico!.immagini).toEqual(["/images/vinea-bottle-3.jpg"]);
  });

  it("legge dalla tabella e non dalla vista pubblica", () => {
    // `public_listings` filtra `stato = 'attivo'`: leggere da li' vorrebbe dire
    // che dopo la sospensione la pagina risponde 404 anche al venditore.
    const sorgente = senzaCommenti(leggi("src/services/listing-service.ts"));
    const corpo = sorgente.slice(sorgente.indexOf("async mioAnnuncio"));
    const finoAllaFine = corpo.slice(0, corpo.indexOf("async pubblica"));
    expect(finoAllaFine).toInclude('.from("listings")');
    expect(finoAllaFine).not.toInclude("public_listings");
  });

  it("disambigua l'innesto su profiles nominando il vincolo", () => {
    // Da `listings` partono TRE chiavi esterne verso `profiles` — seller_id,
    // reserved_by, stato_aggiornato_da — e un innesto ambiguo non e' un valore
    // sbagliato: e' un errore in faccia a chi apre la pagina.
    const sorgente = leggi("src/services/listing-service.ts");
    expect(sorgente).toInclude("profiles!listings_seller_id_fkey");
  });
});

describe("riuso delle fotografie fra cantina e annunci", () => {
  const azioni = () => senzaCommenti(leggi("src/app/vendi/actions.ts"));

  it("copia da cantina ad annunci invece di referenziare il bucket privato", () => {
    // `cantina` e' privato e si legge con URL firmato; `annunci` e' pubblico.
    // Un percorso di cantina dentro `listings.immagini` darebbe un URL
    // pubblico verso un oggetto che li' non esiste.
    const sorgente = azioni();
    expect(sorgente).toInclude("destinationBucket: BUCKET_ANNUNCI");
    expect(sorgente).toInclude(".from(BUCKET_CANTINA)");
  });

  it("non accetta percorsi dal client, ma solo l'id della bottiglia", () => {
    // Un client che proponesse i percorsi chiederebbe di copiare file scelti
    // da lui. La firma prende un id e i percorsi li legge il server.
    const sorgente = azioni();
    expect(sorgente).toMatch(/riusaFotoDellaBottiglia\(\s*bottleUnitId: string,?\s*\)/);
    expect(sorgente).toInclude('.from("bottle_units")');
  });

  it("costruisce il percorso di destinazione dall'utente della sessione", () => {
    const sorgente = azioni();
    expect(sorgente).toInclude("const uid = utente.user.id;");
    expect(sorgente).toMatch(/\$\{uid\}\/\$\{crypto\.randomUUID\(\)\}/);
  });

  it("chiede conferma del prezzo ereditato invece di applicarlo in silenzio", () => {
    const wizard = senzaCommenti(leggi("src/hooks/useSellWizard.ts"));
    expect(wizard).toInclude("prezzoPrecedente !== null && !prezzoConfermato");
    expect(wizard).toInclude("Conferma il prezzo prima di pubblicare.");
  });

  it("aggiunge le foto riusate senza sostituire quelle gia' caricate", () => {
    const wizard = senzaCommenti(leggi("src/hooks/useSellWizard.ts"));
    expect(wizard).toInclude("setFoto((attuali) => [...esito.data.foto, ...attuali])");
  });

  it("tiene il marcatore di richiesta in un ref e non in state", () => {
    // In state il setState provoca un render, il render rifa' l'effetto perche'
    // il marcatore e' fra le sue dipendenze, e la pulizia annulla la richiesta
    // appena partita. Misurato nella 10c sul pannello Sommelier.
    const wizard = senzaCommenti(leggi("src/hooks/useSellWizard.ts"));
    expect(wizard).toInclude("const riusoChiesto = useRef(false)");
    expect(wizard).toInclude("riusoChiesto.current = true");
  });
});
