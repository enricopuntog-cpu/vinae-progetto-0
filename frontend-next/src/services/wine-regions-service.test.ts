import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { SupabaseClient } from "@supabase/supabase-js";
import { creaWineRegionsService } from "@/services/wine-regions-service";

const progetto = join(import.meta.dir, "../..");
const leggi = (percorso: string) => readFileSync(join(progetto, percorso), "utf8");

const MIGRAZIONE = leggi("../supabase/migrations/20260826120000_wine_regions_canonical.sql");

/** Il corpo eseguibile, senza i commenti: un divieto non va cercato nella prosa che lo spiega. */
const SQL = MIGRAZIONE.split("\n")
  .filter((riga) => !riga.trimStart().startsWith("--"))
  .join("\n");

const SORGENTE = leggi("src/services/wine-regions-service.ts");
/** TypeScript eseguibile, senza commenti: anche qui la prosa nomina i divieti che documenta. */
const SORGENTE_ESEGUIBILE = SORGENTE.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");
const ESPLORA = leggi("src/app/esplora/page-client.tsx");
const WIZARD = leggi("src/hooks/useSellWizard.ts");

// ---------------------------------------------------------------------------
// Doppio del client, sulla forma di quello di `public-profile-service.test`.
// Registra relazione, colonne, ordini e tentativi di scrittura: serve a provare
// non solo che cosa il servizio chiede, ma che cosa non chiede mai.
// ---------------------------------------------------------------------------

type Risposta = { data?: unknown; error?: { code?: string; message?: string } | null };

const fakeClient = (risposta: Risposta) => {
  const relazioni: string[] = [];
  const colonne: string[] = [];
  const ordini: { colonna: string; ascending?: boolean }[] = [];
  const scritture: string[] = [];
  const chiamateRpc: string[] = [];

  const chain: Record<string, unknown> = {};
  chain.select = (c: string) => {
    colonne.push(c);
    return chain;
  };
  chain.order = (colonna: string, opzioni?: { ascending?: boolean }) => {
    ordini.push({ colonna, ascending: opzioni?.ascending });
    return chain;
  };
  // La catena si conclude su `order`: e il punto in cui supabase-js manda
  // davvero la richiesta, quindi deve essere attendibile.
  chain.then = (risolvi: (valore: Risposta) => unknown) => Promise.resolve(risposta).then(risolvi);
  chain.insert = () => {
    scritture.push("insert");
    return chain;
  };
  chain.update = () => {
    scritture.push("update");
    return chain;
  };
  chain.delete = () => {
    scritture.push("delete");
    return chain;
  };

  const client = {
    from: (relazione: string) => {
      relazioni.push(relazione);
      return chain;
    },
    rpc: (nome: string) => {
      chiamateRpc.push(nome);
      return Promise.resolve(risposta);
    },
  } as unknown as SupabaseClient;

  return { client, relazioni, colonne, ordini, scritture, chiamateRpc };
};

const righe = (...nomi: string[]) => nomi.map((nome) => ({ nome }));

describe("WineRegionsService — lettura", () => {
  it("legge i nomi dal registro canonico e li restituisce nell'ordine ricevuto", async () => {
    const { client, relazioni, colonne } = fakeClient({
      data: righe("Piemonte", "Toscana", "Veneto"),
      error: null,
    });

    expect(await creaWineRegionsService(client).elenco()).toEqual({
      ok: true,
      data: ["Piemonte", "Toscana", "Veneto"],
    });
    expect(relazioni).toEqual(["wine_regions"]);
    expect(colonne).toEqual(["nome"]);
  });

  // `ordine` non e unico: la migrazione lascia un valore predefinito comune ai
  // nomi futuri. Senza il secondo criterio due righe pari potrebbero tornare in
  // un verso oggi e nell'altro domani, e un menu che si riordina da solo e un
  // difetto che nessuno riesce a riprodurre.
  it("ordina per (ordine, nome), entrambi ascendenti", async () => {
    const { client, ordini } = fakeClient({ data: [], error: null });
    await creaWineRegionsService(client).elenco();
    expect(ordini).toEqual([
      { colonna: "ordine", ascending: true },
      { colonna: "nome", ascending: true },
    ]);
  });

  it("non riordina la lista per conto suo", async () => {
    // L'ordine del registro non e alfabetico: Champagne e ultima per scelta del
    // dato. Un `sort()` di cortesia nel servizio la riporterebbe in testa.
    const { client } = fakeClient({
      data: righe("Piemonte", "Toscana", "Champagne"),
      error: null,
    });
    const esito = await creaWineRegionsService(client).elenco();
    expect(esito).toEqual({ ok: true, data: ["Piemonte", "Toscana", "Champagne"] });
  });

  it("scarta le righe malformate invece di lasciarle scivolare in string[]", async () => {
    const { client } = fakeClient({
      data: [{ nome: "Toscana" }, { nome: null }, { nome: 42 }, { nome: "" }, {}],
      error: null,
    });
    expect(await creaWineRegionsService(client).elenco()).toEqual({ ok: true, data: ["Toscana"] });
  });
});

describe("WineRegionsService — guasti", () => {
  it("non travasa il messaggio di PostgreSQL nel Result", async () => {
    const { client } = fakeClient({
      data: null,
      error: { code: "42501", message: "permission denied for table wine_regions" },
    });
    const esito = await creaWineRegionsService(client).elenco();
    expect(esito.ok).toBe(false);
    if (!esito.ok) {
      expect(esito.error).toBe("Non è stato possibile leggere l'elenco delle regioni.");
      expect(esito.error).not.toContain("permission denied");
    }
  });

  // Un elenco vuoto NON e un errore: il servizio riferisce quello che ha letto.
  // Il registro pero e seminato dalla migrazione e nessun client puo svuotarlo,
  // quindi un vuoto e un segnale, e chi chiama deve poterlo distinguere da un
  // guasto — che e la ragione per cui il contratto resta un Result.
  it("un registro vuoto e un successo con lista vuota, non un errore", async () => {
    const { client } = fakeClient({ data: [], error: null });
    expect(await creaWineRegionsService(client).elenco()).toEqual({ ok: true, data: [] });
  });

  it("senza client configurato risponde con l'errore di configurazione", async () => {
    const esito = await creaWineRegionsService(null).elenco();
    expect(esito.ok).toBe(false);
    if (!esito.ok) expect(esito.error).toContain("NEXT_PUBLIC_SUPABASE_URL");
  });
});

describe("WineRegionsService — confini", () => {
  it("non scrive e non passa da una RPC", async () => {
    const { client, scritture, chiamateRpc } = fakeClient({ data: [], error: null });
    await creaWineRegionsService(client).elenco();
    expect(scritture).toEqual([]);
    expect(chiamateRpc).toEqual([]);
  });

  it("non legge profiles e non e un modulo solo-browser", () => {
    expect(SORGENTE_ESEGUIBILE).not.toContain('"use client"');
    expect(SORGENTE_ESEGUIBILE).not.toContain('from("profiles")');
    expect(SORGENTE_ESEGUIBILE).not.toContain("service_role");
    // Il client arriva da fuori: nessun modulo browser cablato dentro.
    expect(SORGENTE_ESEGUIBILE).not.toContain("@/lib/supabase/client");
    expect(SORGENTE_ESEGUIBILE).toContain("client: SupabaseClient | null");
  });

  // `Tutte` e un pseudo-valore della UI di `/esplora`, non una regione. Se
  // entrasse nel contratto finirebbe prima o poi in un INSERT, e la chiave
  // esterna lo rifiuterebbe.
  it("non conosce il pseudo-valore Tutte ne alcuna lista cablata", () => {
    expect(SORGENTE).not.toContain('"Tutte"');
    expect(SORGENTE).not.toContain('"Piemonte"');
  });
});

describe("D2 — la fondazione che il servizio legge", () => {
  it("il registro esiste, e leggibile e non e scrivibile dal client", () => {
    expect(SQL).toContain("create table public.wine_regions");
    expect(SQL).toMatch(/revoke all on public\.wine_regions from anon, authenticated/);
    expect(SQL).toMatch(/grant select on public\.wine_regions to anon, authenticated/);
    expect(SQL).toContain("alter table public.wine_regions enable row level security");
    expect(SQL).toMatch(
      /create unique index wine_regions_nome_lower_key\s+on public\.wine_regions \(lower\(nome\)\)/,
    );
    // Nessun grant di scrittura, per nessuno dei due ruoli client.
    expect(SQL).not.toMatch(/grant (insert|update|delete)[^;]*public\.wine_regions/i);
  });

  it("wines.regione e vincolata al registro da una chiave esterna VALIDATA", () => {
    expect(SQL).toContain("add constraint wines_regione_fkey");
    expect(SQL).toContain("references public.wine_regions (nome)");
    expect(SQL).toContain("validate constraint wines_regione_fkey");
  });

  // Il pacchetto UI successivo deve trovare nel registro tutto cio che
  // `/esplora` gia oggi sa filtrare: se un nome sparisse, un filtro esistente
  // smetterebbe di avere corrispondenze senza che nulla lo segnali.
  it("il seed copre le 17 regioni canoniche che /esplora filtra", () => {
    // La migrazione è il seed unico. /esplora non cablista più nomi: legge dal
    // registro tramite WineRegionsService. Il vincolo qui è che i 17 nomi
    // sostenuti dal vecchio array siano tutti presenti nel seed: se un nome
    // sparisse, un filtro esistente smetterebbe di avere corrispondenze senza
    // che nulla lo segnali.
    const nomi = [
      "Piemonte", "Toscana", "Veneto", "Sicilia", "Friuli-Venezia Giulia",
      "Trentino-Alto Adige", "Abruzzo", "Emilia-Romagna", "Lombardia",
      "Campania", "Puglia", "Marche", "Umbria", "Liguria", "Sardegna",
      "Lazio", "Champagne",
    ];
    expect(nomi.length).toBe(17);
    for (const nome of nomi) expect(SQL).toContain(`('${nome}'`);
    // `Tutte` non e una regione e non deve essere seminata.
    expect(SQL).not.toContain("('Tutte'");
  });

  it("la canonicalizzazione vive in private e non e eseguibile dai ruoli client", () => {
    expect(SQL).toContain("create function private.regione_canonica");
    expect(SQL).toMatch(
      /revoke execute on function private\.regione_canonica\(text\)\s+from public, anon, authenticated/,
    );
  });
});

describe("D2 — cio che questa fondazione non tocca", () => {
  // Il selettore, il filtro e la traduzione AI sono il pacchetto dopo. Qui si
  // fissa il confine: la fondazione e collegabile, non collegata.
  it("/vendi e /esplora usano WineRegionsService e non interrogano wine_regions direttamente", () => {
    // /esplora pagina server
    const esploraServer = leggi("src/app/esplora/page.tsx");
    expect(esploraServer).toContain("creaWineRegionsService");
    expect(esploraServer).not.toContain('.from("wine_regions")');
    // /esplora pagina client
    expect(ESPLORA).not.toContain('.from("wine_regions")');
    // /vendi wizard
    expect(WIZARD).toContain("creaWineRegionsService");
    expect(WIZARD).not.toContain('.from("wine_regions")');
  });

  // Il `.trim()` in `datiBottiglia()` resta ed e corretto: normalizza, non apre
  // una porta. La porta era il campo libero, e quella e chiusa qui — il valore
  // puo entrare solo da una voce del registro.
  it("/vendi non ha piu un campo Regione a testo libero", () => {
    const vendiClient = leggi("src/app/vendi/page-client.tsx");
    expect(vendiClient).toContain('onValueChange={set("regione")}');
    expect(vendiClient).not.toMatch(/<Input[^>]*value=\{d\.regione\}/);
    expect(vendiClient).not.toContain('set("regione")(e.target.value)');
  });

  it("/vendi non include Tutte nel selettore e rende Region obbligatoria", () => {
    const vendiClient = leggi("src/app/vendi/page-client.tsx");
    expect(vendiClient).not.toContain('"Tutte"');
    // Il selettore è disabilitato finché il registro non è letto con successo
    expect(vendiClient).toContain("disabled={regioni.stato !== \"disponibili\"}");
    // La navigazione blocca senza Region canonica
    expect(vendiClient).toContain("regioneValida");
    expect(WIZARD).toContain("regioneValida");
  });

  it("/esplora mantiene Tutte solo come pseudo-valore UI e non dal registro", () => {
    expect(ESPLORA).toContain("REGIONE_TUTTE");
    expect(ESPLORA).toContain('risolviRegioneIniziale');
    expect(ESPLORA).not.toContain('const regioni = [');
    // Il filtro "Tutte" è solo UI: non arriva dal server
    const esploraServer = leggi("src/app/esplora/page.tsx");
    expect(esploraServer).not.toContain('"Tutte"');
  });

  it("la migrazione non allarga privilegi o policy delle tabelle esistenti", () => {
    for (const tabella of ["wines", "bottle_units", "listings"]) {
      expect(SQL).not.toMatch(new RegExp(`grant [^;]*on public\\.${tabella}`, "i"));
      expect(SQL).not.toMatch(new RegExp(`create policy[^;]*on public\\.${tabella}`, "i"));
    }
  });
});
