import { describe, expect, it } from "bun:test";
import { renderToStaticMarkup } from "react-dom/server";
import { AccessoriPostvenditaAdmin, type PagamentiDaVerificare } from "./AccessoriPostvenditaAdmin";

// VPM-015QA-FINAL-B2-COMPLETION: ciò che l'admin legge per gli intenti orfani e i rimborsi dovuti.
const text = (markup: string) =>
  markup.replace(/<[^>]+>/g, " ").replace(/&#x27;/g, "'").replace(/&quot;/g, '"').replace(/\s+/g, " ");

const vuoto = { contestazioni: [], rimborsi: [] };
const ORDINE = "11111111-1111-4111-8111-111111111111";

const pagamenti = (extra: Partial<PagamentiDaVerificare> = {}): PagamentiDaVerificare => ({
  orfani: { ok: true, data: [] },
  dovuti: { ok: true, data: [] },
  ...extra,
});

const mostra = (p: PagamentiDaVerificare) => text(renderToStaticMarkup(<AccessoriPostvenditaAdmin iniziale={vuoto} pagamenti={p} />));

describe("AccessoriPostvenditaAdmin: intenti orfani e rimborsi dovuti", () => {
  it("elenchi vuoti validi dicono «Nessuno», non un errore", () => {
    const t = mostra(pagamenti());
    expect(t).toContain("Intenti di pagamento orfani");
    expect(t).toContain("Rimborsi dovuti");
    expect(t).not.toContain("Elenco non disponibile");
  });

  it("una lettura fallita è un ERRORE visibile, mai un falso elenco vuoto", () => {
    const t = mostra(
      pagamenti({ orfani: { ok: false, error: "Operazione non riuscita." }, dovuti: { ok: false, error: "Accedi per continuare." } }),
    );
    expect(t).toContain("Elenco non disponibile: Operazione non riuscita.");
    expect(t).toContain("Elenco non disponibile: Accedi per continuare.");
    expect(t).toContain("Non significa che non ci siano intenti orfani.");
    expect(t).toContain("Non significa che non ci siano rimborsi dovuti.");
  });

  it("mostra ordine, stato, fornitore, intento, importo, valuta e data di ogni anomalia", () => {
    const t = mostra(
      pagamenti({
        orfani: {
          ok: true,
          data: [
            {
              ordineId: ORDINE, provider: "stripe", intento: "pi_test_abc", importoCents: 4724, valuta: "eur",
              statoPagamento: "expired", statoIntento: "incerto", motivo: "intento_orfano", aggiornatoAt: "2026-11-03T10:00:00Z",
            },
          ],
        },
        dovuti: {
          ok: true,
          data: [{ ordineId: ORDINE, importoCents: 4724, valuta: "eur", rimborsatoCents: 0, motivo: "intento_orfano_incassato", aggiornatoAt: "2026-11-03T10:00:00Z" }],
        },
      }),
    );
    expect(t).toContain("Incerto");
    expect(t).toContain("47,24");
    expect(t).toContain("EUR");
    expect(t).toContain(`Ordine ${ORDINE}`);
    expect(t).toContain("stripe pi_test_abc");
    expect(t).toContain("motivo: intento_orfano");
    expect(t).toContain("già rimborsato 0,00");
    expect(t).toContain("Apri nel fascicolo");
  });

  it("non promette azioni: nessun comando di annullo, rimborso o riconciliazione automatica", () => {
    const markup = renderToStaticMarkup(
      <AccessoriPostvenditaAdmin
        iniziale={vuoto}
        pagamenti={pagamenti({
          orfani: {
            ok: true,
            data: [
              {
                ordineId: ORDINE, provider: "stripe", intento: "pi_test_abc", importoCents: 100, valuta: "eur",
                statoPagamento: "expired", statoIntento: "da_annullare", motivo: null, aggiornatoAt: "2026-11-03T10:00:00Z",
              },
            ],
          },
        })}
      />,
    );
    const t = text(markup);
    expect(t).toContain("non annulla né rimborsa e non riconcilia in automatico");
    expect(t).toContain("Da annullare");
    // I soli pulsanti nelle due sezioni nuove aprono il fascicolo: nessun «Annulla intento» o «Rimborsa ora».
    const sezione = markup.slice(markup.indexOf('data-testid="intenti-orfani-admin"'), markup.indexOf("Operazioni sull"));
    const pulsanti = [...sezione.matchAll(/<button[^>]*>(.*?)<\/button>/g)].map((m) => m[1]);
    expect(pulsanti).toEqual(["Apri nel fascicolo"]);
    expect(sezione).not.toMatch(/sk_|service_role|secret/i);
  });
});
