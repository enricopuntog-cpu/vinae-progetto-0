import { describe, expect, it } from "bun:test";
import {
  BUCKET_CLUB_COVERS,
  coverSicura,
  PRESET_COVER_CLUB,
  percorsoCoverProprio,
  riferimentoCoverSicuro,
} from "@/lib/phase12/club-cover";

// Gli UUID sono scritti per esteso e non generati: un test che genera il dato
// che poi verifica non prova che il formato atteso sia quello, prova solo che
// due generatori sono d'accordo.
const OWNER = "3f2a1b4c-5d6e-4f70-8912-a3b4c5d6e7f8";
const ALTRO = "9e8d7c6b-5a49-4b38-9271-0f1e2d3c4b5a";
const OGGETTO = "0a1b2c3d-4e5f-4061-8273-8495a6b7c8d9";
const PERCORSO = `${OWNER}/${OGGETTO}.webp`;

describe("percorsoCoverProprio", () => {
  it("accetta il percorso nella cartella del proprietario", () => {
    expect(percorsoCoverProprio(PERCORSO, OWNER)).toBe(PERCORSO);
  });

  it("rifiuta il percorso nella cartella di un altro utente", () => {
    // E la meta client di `clubs_cover_image_vinea_check`: la cover di un club
    // sta nella cartella del suo proprietario, cosi il percorso memorizzato non
    // puo puntare a un oggetto scritto da qualcun altro.
    expect(percorsoCoverProprio(`${ALTRO}/${OGGETTO}.webp`, OWNER)).toBeNull();
  });

  it("rifiuta i percorsi che non hanno la forma canonica", () => {
    expect(percorsoCoverProprio(`${OWNER}/${OGGETTO}.png`, OWNER)).toBeNull();
    expect(percorsoCoverProprio(`${OWNER}/copertina.webp`, OWNER)).toBeNull();
    expect(percorsoCoverProprio(`${OWNER}/sotto/${OGGETTO}.webp`, OWNER)).toBeNull();
    expect(percorsoCoverProprio(`../${PERCORSO}`, OWNER)).toBeNull();
    expect(percorsoCoverProprio("", OWNER)).toBeNull();
  });

  it("senza proprietario non c'e percorso da fidarsi", () => {
    // Un club di sistema non ha owner_id: non c'e cartella a cui legare la
    // cover, quindi il valore non si usa invece di usarlo senza verifica.
    expect(percorsoCoverProprio(PERCORSO, null)).toBeNull();
    expect(percorsoCoverProprio(PERCORSO, undefined)).toBeNull();
  });
});

describe("riferimentoCoverSicuro — URL esterni", () => {
  it("rifiuta un URL HTTP arbitrario", () => {
    // Il requisito e esplicito: nel database va un percorso, mai un URL. Un
    // URL esterno non e un percorso e non deve poter diventare la cover di un
    // club, ne finire nel `src` di un'immagine servita dal dominio Vinea.
    expect(riferimentoCoverSicuro("https://esempio.invalid/cover.webp", OWNER)).toBeNull();
    expect(
      riferimentoCoverSicuro(`https://esempio.invalid/${PERCORSO}`, OWNER),
    ).toBeNull();
  });

  it("rifiuta gli schemi che non sono nemmeno HTTP", () => {
    expect(riferimentoCoverSicuro("javascript:alert(1)", OWNER)).toBeNull();
    expect(riferimentoCoverSicuro("data:image/webp;base64,AAAA", OWNER)).toBeNull();
  });

  it("rifiuta un URL del bucket giusto che contiene il percorso giusto", () => {
    // Il caso insidioso: la stringa contiene davvero `<owner>/<uuid>.webp`. Se
    // il controllo fosse un `includes`, passerebbe. L'ancoraggio `^...$` e la
    // ragione per cui non passa.
    expect(
      riferimentoCoverSicuro(
        `https://progetto.supabase.co/storage/v1/object/public/${BUCKET_CLUB_COVERS}/${PERCORSO}`,
        OWNER,
      ),
    ).toBeNull();
  });
});

describe("coverSicura", () => {
  it("ricompone l'indirizzo dalla configurazione, non dal valore memorizzato", () => {
    expect(coverSicura(PERCORSO, OWNER, "https://progetto.supabase.co")).toBe(
      `https://progetto.supabase.co/storage/v1/object/public/${BUCKET_CLUB_COVERS}/${PERCORSO}`,
    );
  });

  it("fallisce chiuso quando la configurazione manca o non e un'origine HTTP", () => {
    expect(coverSicura(PERCORSO, OWNER, undefined)).toBeNull();
    expect(coverSicura(PERCORSO, OWNER, "")).toBeNull();
    expect(coverSicura(PERCORSO, OWNER, "non-un-url")).toBeNull();
    expect(coverSicura(PERCORSO, OWNER, "ftp://progetto.supabase.co")).toBeNull();
  });

  it("un club senza cover non ha immagine, e non e un errore", () => {
    expect(coverSicura(null, OWNER, "https://progetto.supabase.co")).toBeNull();
  });
});

describe("PRESET_COVER_CLUB", () => {
  it("serve i preset da public/, non da URL esterni", () => {
    // I preset sono asset Vinea. Se uno di questi percorsi diventasse un URL
    // assoluto, la scelta di una cover predefinita farebbe una richiesta a un
    // terzo dal browser di chi crea il club.
    for (const voce of PRESET_COVER_CLUB) {
      expect(voce.percorso.startsWith("/club-covers/")).toBe(true);
      expect(voce.etichetta.length).toBeGreaterThan(0);
    }
  });

  it("gli id sono distinti", () => {
    const id = PRESET_COVER_CLUB.map((v) => v.id);
    expect(new Set(id).size).toBe(id.length);
  });
});
