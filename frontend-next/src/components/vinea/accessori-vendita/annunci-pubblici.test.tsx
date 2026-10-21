import { describe, expect, it } from "bun:test";
import { renderToStaticMarkup } from "react-dom/server";
import { parseAnnuncioPubblico, type AnnuncioPubblico } from "@/lib/accessori-vendita/annunci-pubblici";
import {
  AnnunciVetrina,
  AvvisoAcquistiNonDisponibili,
  DettaglioAnnuncioPubblico,
  SchedaAnnuncioPubblicoCard,
} from "./AnnunciPubblici";

// Render server-side reale: ciò che l'utente legge, non il sorgente.
const html = (node: React.ReactNode) => renderToStaticMarkup(<>{node}</>);
const text = (markup: string) =>
  markup.replace(/<[^>]+>/g, " ").replace(/&#x27;/g, "'").replace(/&quot;/g, '"').replace(/\s+/g, " ");

const U1 = "11111111-1111-4111-8111-111111111111";
const U2 = "22222222-2222-4222-8222-222222222222";
const FOTO = `${U1}/${U2}/33333333-3333-4333-8333-333333333333.webp`;
const FOTO2 = `${U1}/${U2}/44444444-4444-4444-8444-444444444444.webp`;
const URL_FIRMATA = "https://example.test/storage/v1/object/sign/cantina-accessori-foto/x.webp?token=t";

const annuncio = (extra: Record<string, unknown> = {}): AnnuncioPubblico => {
  const a = parseAnnuncioPubblico({
    id: U1,
    nome: "Calice di prova",
    marchio: "Cristalleria",
    categoria: { slug: "calici-da-rosso", nome: "Calici da rosso", genitore: "Calici" },
    condizione: "come_nuovo",
    quantita: 2,
    descrizione: "Due calici in ottimo stato.",
    foto: [FOTO, FOTO2],
    prezzo_acquirente_cents: 2273,
    pubblicato_at: "2026-10-22T08:00:00Z",
    aggiornato_at: "2026-10-22T08:00:00Z",
    venditore: { username: "ua", avatar_url: null },
    acquistabile: false,
    ...extra,
  });
  if (!a) throw new Error("annuncio non valido");
  return a;
};

// Nessun comando che sembri funzionante: né «Acquista», né carrello, né pagamento.
const COMANDO_ACQUISTO = /(\bAcquista\b|\bCompra\b|Aggiungi al carrello|\bPaga ora\b|Checkout|\bbuy\b|\bPrenota\b)/i;

describe("vetrina degli annunci pubblici", () => {
  it("la scheda dice che non è acquistabile e mostra il prezzo indicativo spedizione esclusa", () => {
    const markup = html(<ul><SchedaAnnuncioPubblicoCard annuncio={annuncio()} immagine={URL_FIRMATA} /></ul>);
    const t = text(markup);
    expect(t).toContain("Calice di prova");
    expect(t).toContain("22,73");
    expect(t).toContain("a pezzo, spedizione esclusa");
    expect(t).toContain("Non ancora acquistabile");
    expect(t).toContain("2 pezzi");
    expect(markup).toContain(`href="/accessori/annunci/${U1}"`);
    expect(t).not.toMatch(COMANDO_ACQUISTO);
    // la foto non si ritaglia: oggetti verticali interi, proporzioni 4:5
    expect(markup).toContain("object-contain");
    expect(markup).not.toContain("object-cover");
    expect(markup).toContain("aspect-[4/5]");
    expect(markup).toContain(URL_FIRMATA);
  });

  it("senza URL firmata mostra il segnaposto, mai un errore", () => {
    const markup = html(<ul><SchedaAnnuncioPubblicoCard annuncio={annuncio()} immagine={null} /></ul>);
    expect(markup).toContain('aria-label="Immagine non disponibile"');
    expect(markup).not.toContain("<img");
  });

  it("l'elenco dichiara sempre che gli acquisti non sono disponibili e che la moderazione è successiva", () => {
    const markup = html(
      <AnnunciVetrina annunci={[annuncio()]} immagini={{ [FOTO]: URL_FIRMATA }} modalita="pubblica" pagina={1} haAltri={false} />,
    );
    const t = text(markup);
    expect(t).toContain("Gli acquisti non sono ancora disponibili");
    expect(t).toContain("senza controllo preventivo");
    expect(markup).toContain('data-testid="annunci-avviso-acquisti"');
    expect(markup).toContain(URL_FIRMATA);
    expect(t).not.toMatch(COMANDO_ACQUISTO);
    // nessun collegamento verso checkout, ordini o il vino
    expect(markup).not.toMatch(/href="\/(checkout|ordine|acquisti|vendite|vendi|annuncio)/);
  });

  it("senza annunci mostra lo stato vuoto; la paginazione compare solo quando serve", () => {
    const vuoto = html(<AnnunciVetrina annunci={[]} immagini={{}} modalita="pubblica" pagina={1} haAltri={false} />);
    expect(text(vuoto)).toContain("Nessun annuncio in vetrina");
    expect(vuoto).not.toContain('aria-label="Pagine"');
    const paginato = html(<AnnunciVetrina annunci={[annuncio()]} immagini={{}} modalita="pubblica" pagina={2} haAltri />);
    expect(paginato).toContain('href="/accessori/annunci?pagina=1"');
    expect(paginato).toContain('href="/accessori/annunci?pagina=3"');
  });

  it("l'anteprima riservata agli admin è dichiarata", () => {
    const markup = html(<AnnunciVetrina annunci={[]} immagini={{}} modalita="anteprima" pagina={1} haAltri={false} />);
    expect(markup).toContain('data-testid="accessori-anteprima"');
  });

  it("l'avviso è una nota annunciata, non un errore", () => {
    const markup = html(<AvvisoAcquistiNonDisponibili />);
    expect(markup).toContain('role="note"');
    expect(text(markup)).toContain("non è possibile comprare, prenotare o pagare");
  });
});

describe("dettaglio dell'annuncio pubblico", () => {
  const dettaglio = (autenticato: boolean) =>
    html(
      <DettaglioAnnuncioPubblico
        annuncio={annuncio()}
        immagini={{ [FOTO]: URL_FIRMATA }}
        modalita="pubblica"
        autenticato={autenticato}
      />,
    );

  it("mostra solo dati pubblici e nessun comando d'acquisto", () => {
    const markup = dettaglio(false);
    const t = text(markup);
    expect(t).toContain("Calice di prova");
    expect(t).toContain("Cristalleria");
    expect(t).toContain("Proposto da ua");
    expect(t).toContain("Prezzo indicativo");
    expect(t).toContain("22,73");
    expect(t).toContain("Gli acquisti non sono ancora disponibili");
    expect(t).not.toMatch(COMANDO_ACQUISTO);
    expect(markup).not.toMatch(/<button[^>]*>[^<]*(Acquista|Compra|Prenota|Paga)/i);
    // nessun id interno oltre a quello dell'annuncio, nessuna nota privata
    expect(markup).not.toContain("note_private");
    expect(markup).not.toContain(U2 + "/note");
  });

  it("senza sessione la segnalazione rimanda all'accesso (nessuna porta anonima) e torna sull'annuncio", () => {
    const markup = dettaglio(false);
    expect(text(markup)).toContain("Accedi per segnalare");
    expect(markup).toContain(`href="/accedi?next=${encodeURIComponent(`/accessori/annunci/${U1}`)}"`);
    expect(markup).toContain('data-testid="segnala-annuncio-accedi"');
    expect(markup).not.toContain('data-testid="segnala-annuncio"');
  });

  it("la foto principale non si ritaglia e le altre hanno un testo alternativo", () => {
    const markup = dettaglio(false);
    expect(markup).toContain("object-contain");
    expect(markup).toContain('alt="Calice di prova"');
    expect(markup).toContain('aria-label="Altre immagini"');
  });
});
