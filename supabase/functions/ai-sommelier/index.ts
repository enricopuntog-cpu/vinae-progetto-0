// Fase 10b — la chat Sommelier, con storico e streaming.
//
// Porta di `backend/ai_routes.py:47-108`. È l'unica delle tre function che
// **scrive** e l'unica che fa streaming, ed è per questo che sta da sola
// (decisione 7.6).
//
// ---------------------------------------------------------------------------
// IL VINCOLO CHE NON VA SCOPERTO IN PRODUZIONE
// ---------------------------------------------------------------------------
//
// Una Edge Function che inoltra uno stream **può essere troncata** quando il
// worker viene ritirato: Supabase lo documenta come scenario noto («SSE or AI
// streams end before completion»). Se la `Response` viene restituita e l'isolate
// non ha più lavoro registrato, la piattaforma può ritirarlo mentre i chunk
// stanno ancora arrivando dal fornitore.
//
// Il rimedio è tenere l'isolate vivo per tutta la durata dell'inoltro con
// `EdgeRuntime.waitUntil()` sulla `pipeTo`, restituendo il lato leggibile.
// Senza, lo stream si interrompe **in modo intermittente e a metà risposta**,
// che è la classe di difetto peggiore: non fallisce nei test e non fallisce
// sempre.
//
// La decisione 7.7 ci aggiunge la metà che manca: `EdgeRuntime.waitUntil()`
// riduce la probabilità, non la azzera, quindi **anche il client deve trattare
// un troncamento parziale come caso atteso**. Uno stream che finisce senza
// l'evento `done` non è un errore da mostrare: è una risposta parziale da
// tenere. Il contratto lato client è `SommelierEsito.troncato`
// (`frontend-next/src/services/types.ts`).
//
// Conseguenza sulla persistenza, che è dove il troncamento fa male davvero: si
// salva **solo a stream concluso e non vuoto**, come nel legacy
// (`backend/ai_routes.py:92-101`). Una risposta troncata a metà non entra nello
// storico, perché diventerebbe il contesto delle battute successive.
//
// WI-016 — VERIFICA PRIMA DELLA TRASMISSIONE. Dal fornitore la risposta arriva a
// pezzi, ma al client non ne esce nessuno finché non è arrivata TUTTA ed è
// passata dallo stesso rilevatore dei dati sensibili usato in ingresso. Una
// finestra scorrevole non basta: un segreto può essere spezzato su più pezzi e
// alcune forme (JWT, «password: …») non hanno una lunghezza massima prima di
// essere riconoscibili. La risposta è già limitata, quindi si tiene in memoria.
// Nell'attesa partono solo commenti SSE senza contenuto: tengono viva la
// connessione e fanno accorgere subito di un client che se n'è andato. Un
// guasto o un troncamento a metà non consegna testo non verificato.

import { rilevaDatiSensibili } from "../_shared/ai-sicurezza.ts";
import { timeoutMs } from "../_shared/ai-provider.ts";
import {
  apriIngresso,
  apriPorta,
  chiamataGovernata,
  chiusa,
  json,
  leggiCorpo,
  testo,
  registraConsuntivo,
  registraEsitoFornitore,
  segnalaSicurezza,
  type Ingresso,
} from "../_shared/ai-gate.ts";
import {
  costruisciContestoCantina,
  costruisciContestoVino,
  costruisciPromptConContesto,
  LIMITI_CONTESTO,
  PROMPT_ISTRUZIONI_CONTESTO,
  pulisciRigaStorico,
  type RigaBottiglia,
  type RigaVino,
  serializzaContesto,
} from "../_shared/sommelier-contesto.ts";
import {
  candidatiDaRigheCanoniche,
  costruisciContestoRicerca,
  costruisciSchedaDocumentata,
  LIMITI_RICERCA,
  PROMPT_ISTRUZIONI_RICERCA,
  serializzaContestoRicerca,
  serializzaSchedaDocumentata,
} from "../_shared/sommelier-ricerca.ts";

// Identico a `SOMMELIER_SYSTEM` (`backend/ai_routes.py:18-23`). Le due
// istruzioni finali — non inventare produttori o annate, nessun consiglio
// medico, consumo responsabile — sono l'unico presidio degli invarianti AI
// scritti in `docs/SECURITY.md`, e non sono formule di cortesia.
const SYSTEM = "Sei Vinea Sommelier, un sommelier virtuale esperto che assiste appassionati " +
  "italiani nell'esplorazione del vino. Rispondi sempre in italiano con tono " +
  "cordiale, competente e sintetico (max 4 paragrafi brevi). Non inventare " +
  "produttori o annate. Non fornire consigli medici e ricorda il consumo responsabile.";

// `SOMMELIER_CONTEXT_MESSAGES`, `SOMMELIER_MAX_RESPONSE_CHARS`
// (`backend/.env.example:36-37`). Il tetto sui caratteri non è solo una difesa
// sul traffico: con la 7.2 = A è ciò che tiene la riga dentro il vincolo di
// lunghezza della colonna, quindi appartiene alla stessa migrazione.
const CONTESTO_MESSAGGI = 12;
const RISPOSTA_MAX_CHARS = 8000;
const MESSAGGIO_MAX_CHARS = 2000;

const SESSION_ID = /^[A-Za-z0-9_-]{4,64}$/;

// WI-016: quanto al massimo si può verificare per intero. Con il tetto di token
// in uscita non ci si avvicina; oltre non si trasmette nulla.
const RISPOSTA_VERIFICABILE_MAX_CHARS = 64_000;
// Durata massima della lettura dal fornitore: sotto i 150 s della piattaforma.
const LETTURA_MASSIMA_MS = 120_000;
const IN_VERIFICA = ": in verifica\n\n";
const RISPOSTA_BLOCCATA =
  "La risposta conteneva dati riservati ed è stata bloccata. Riformula la domanda.";

/** Una lettura che non arriva entro `ms` è un guasto: il fornitore muto non tiene aperta la richiesta. */
const leggiEntroScadenza = async <T>(lettura: Promise<T>, ms: number): Promise<T> => {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const scadenza = new Promise<never>((_, rifiuta) => {
    timer = setTimeout(() => rifiuta(new DOMException("fornitore muto", "TimeoutError")), Math.max(ms, 0));
  });
  try {
    return await Promise.race([lettura, scadenza]);
  } finally {
    clearTimeout(timer);
  }
};

type RigaContesto = { ruolo: "utente" | "sommelier"; contenuto: string };

/**
 * Il prompt con il contesto, nella forma esatta del legacy
 * (`backend/ai_routes.py:57-68`): la conversazione precedente entra come testo
 * marcato «solo contesto», non come messaggi di ruolo. È una scelta del legacy
 * e viene trasportata, non migliorata: cambiarla cambierebbe le risposte, e
 * questa è una migrazione.
 */
export const costruisciPrompt = (contesto: RigaContesto[], messaggio: string): string => {
  if (contesto.length === 0) return messaggio;
  const trascritto = contesto
    .map((riga) => `${riga.ruolo === "utente" ? "Utente" : "Sommelier"}: ${riga.contenuto.trim()}`)
    .join("\n");
  return "Conversazione precedente (solo contesto, non ripetere):\n" +
    `${trascritto}\n\nNuovo messaggio dell'utente:\n${messaggio}`;
};

const sse = (payload: Record<string, unknown>): string =>
  `data: ${JSON.stringify(payload)}\n\n`;

// ---------------------------------------------------------------------------
// WI-004 — contesto verificato lato server
// ---------------------------------------------------------------------------
//
// Il corpo può portare `contesto`, e di quattro cose sole:
//   * assente → Sommelier generale, esattamente come prima (stesso prompt di
//     sistema, stesso prompt utente, nessuna lettura di dominio);
//   * `{ tipo: "vino", annuncio_id }` → la scheda del vino realmente consultato,
//     riletta qui dalla vista pubblica a colonne chiuse e dalla tabella dei vini;
//   * `{ tipo: "cantina", consenso: true }` → le bottiglie dell'utente del token;
//   * `{ tipo: "ricerca", produttore, nome, codice }` (WI-008) → i candidati del catalogo canonico per QUELLA ricerca esplicita,
//     letti dal server con `vini_canonici_cerca_servizio` (massimo 5, 3.500 caratteri). Il testo libero non viene analizzato per trovare vini.
//     Catalogo spento, vuoto o in errore → Sommelier generale, esattamente come prima (nessun 503, nessun contesto).
//
// Il browser non è un'autorità su nessuno dei due: non manda inventari, non
// sceglie il proprietario (qualunque `owner_id`, `user_id` o simile nel corpo è
// ignorato e il solo proprietario è `userId`, ricavato dal token da
// `apriPorta`), non fornisce attributi del vino. Il consenso vale per UNA
// richiesta: il client lo rimanda a ogni messaggio finché l'utente lo tiene
// attivo, e il server lo pretende ogni volta — non esiste uno stato «consenso»
// salvato che sopravviva a una conversazione, a un logout o a un cambio utente.
//
// La lettura della Cantina usa il client di servizio (non esiste una porta
// owner-scoped per questo, e una migrazione non è stata autorizzata): per questo
// il filtro `owner_id = userId` è esplicito, l'elenco colonne è chiuso e povero
// (niente note, costi, foto, posizioni, date) e i test provano l'isolamento fra
// utenti. Le stringhe del database entrano nel prompt solo come blocco dati
// ripulito e limitato (`_shared/sommelier-contesto.ts`), mai nel prompt di sistema.

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type RichiestaContesto =
  | { tipo: "vino"; annuncioId: string }
  | { tipo: "cantina" }
  | { tipo: "ricerca"; produttore: string; nome: string; codice: string | null };

type EsitoContesto =
  | { ok: true; richiesta: RichiestaContesto | null }
  | { ok: false; status: number; corpo: Record<string, unknown> };

const leggiRichiestaContesto = (grezzo: unknown): EsitoContesto => {
  if (grezzo === undefined || grezzo === null) return { ok: true, richiesta: null };
  if (typeof grezzo !== "object" || Array.isArray(grezzo)) {
    return { ok: false, status: 400, corpo: { error: "Contesto non valido." } };
  }
  const c = grezzo as Record<string, unknown>;
  if (c.tipo === "vino") {
    return typeof c.annuncio_id === "string" && UUID.test(c.annuncio_id)
      ? { ok: true, richiesta: { tipo: "vino", annuncioId: c.annuncio_id.toLowerCase() } }
      : { ok: false, status: 400, corpo: { error: "Contesto non valido." } };
  }
  if (c.tipo === "cantina") {
    // Solo il booleano `true`: «true», 1 e simili non sono un consenso.
    return c.consenso === true
      ? { ok: true, richiesta: { tipo: "cantina" } }
      : {
        ok: false,
        status: 400,
        corpo: { error: "Serve il tuo consenso esplicito per usare la tua Cantina.", code: "consenso_richiesto" },
      };
  }
  if (c.tipo === "ricerca") {
    const campo = (v: unknown): string | null =>
      v === undefined || v === null ? "" : typeof v === "string" && v.length <= 120 ? v.trim() : null;
    const produttore = campo(c.produttore);
    const nome = campo(c.nome);
    const codice = c.codice === undefined || c.codice === null ? "" : typeof c.codice === "string" ? c.codice.trim() : null;
    // WI-011: il codice di una scheda è il LWIN-7 oppure l'UUID del vino canonico (schede senza LWIN).
    if (produttore === null || nome === null || codice === null || (codice !== "" && !/^[0-9]{7}$/.test(codice) && !UUID.test(codice))) {
      return { ok: false, status: 400, corpo: { error: "Contesto non valido." } };
    }
    // Serve almeno un nome o un identificativo: una ricerca vuota non interroga il catalogo.
    if (nome === "" && codice === "") return { ok: false, status: 400, corpo: { error: "Contesto non valido." } };
    return { ok: true, richiesta: { tipo: "ricerca", produttore, nome, codice: codice || null } };
  }
  return { ok: false, status: 400, corpo: { error: "Contesto non valido." } };
};

// Solo ciò che il contesto usa davvero (niente `finestra_affidabilita`, `creato_da`, date).
const COLONNE_VINO = "slug, produttore, nome, annata, regione, denominazione, tipo, formato, provenienza, " +
  "finestra_inizio, finestra_fine, apice_inizio, apice_fine, finestra_fonte, " +
  "temperatura_servizio, decantazione_minuti, calice, occasione, abbinamenti";

// Elenco chiuso. Assenti di proposito: id, owner_id, note_personali,
// override_nota, degustazione_nota, acquisition_cost_cents, immagini, posizione
// (cellar_slots), prezzi, date, collegamenti a annunci e ordini.
const COLONNE_BOTTIGLIA = "stato, formato, ceduta_at, override_finestra_inizio, override_finestra_fine, " +
  `override_apice_inizio, override_apice_fine, override_preferenza, wines!inner(${COLONNE_VINO})`;

type Letto =
  | { ok: true; blocco: string; istruzioni?: string }
  // `vuoto`: nessun contesto utilizzabile (catalogo spento/vuoto/in errore): si prosegue come il Sommelier generale.
  | { ok: true; vuoto: true }
  | { ok: false; status: number; corpo: Record<string, unknown> };

const INDISPONIBILE = { error: "Il Sommelier non è al momento disponibile." };

const primo = <T>(valore: T | T[] | null | undefined): T | null =>
  Array.isArray(valore) ? (valore[0] ?? null) : (valore ?? null);

// deno-lint-ignore no-explicit-any
const leggiContesto = async (supabase: any, userId: string, richiesta: RichiestaContesto, messaggio: string): Promise<Letto> => {
  const annoCorrente = new Date().getUTCFullYear();

  if (richiesta.tipo === "ricerca") {
    // Porta di sola lettura riservata a service_role, spenta con l'interruttore del catalogo. Il limite per utente è quello
    // del gate AI, già consumato; qui nessun contatore condiviso fra utenti.
    // Gli errori non sono mai mostrati: il Sommelier torna quello di prima.
    const { data, error } = await supabase.rpc("vini_canonici_cerca_servizio", {
      p_produttore: richiesta.produttore,
      p_nome: richiesta.nome,
      p_limite: LIMITI_RICERCA.candidatiLetti,
      p_codice: richiesta.codice,
    });
    if (error) {
      console.error("[ai-sommelier] ricerca canonica non disponibile", { code: error.code });
      return { ok: true, vuoto: true };
    }
    const contestoRicerca = costruisciContestoRicerca(candidatiDaRigheCanoniche(data));
    if (contestoRicerca.inclusi === 0) return { ok: true, vuoto: true };
    let blocco = serializzaContestoRicerca(contestoRicerca).testo;
    // WI-016: annate e dati documentati SOLO per il vino identificato dal codice richiesto (una lettura mirata).
    if (richiesta.codice && contestoRicerca.candidati.some((c) => c.identificato)) {
      const scheda = await supabase.rpc("vini_canonici_scheda_servizio", { p_codice: richiesta.codice });
      if (scheda.error) console.error("[ai-sommelier] scheda documentata non disponibile", { code: scheda.error.code });
      else {
        const testo = serializzaSchedaDocumentata(costruisciSchedaDocumentata(scheda.data));
        if (testo) blocco += `\nScheda documentata del candidato identificato:\n${testo}`;
      }
    }
    return { ok: true, blocco, istruzioni: PROMPT_ISTRUZIONI_RICERCA };
  }

  if (richiesta.tipo === "vino") {
    // Vista pubblica a colonne chiuse: un annuncio non pubblico non esiste per questa lettura.
    const { data: annuncio, error } = await supabase
      .from("public_listings")
      .select("wine_id, formato")
      .eq("id", richiesta.annuncioId)
      .maybeSingle();
    if (error) {
      console.error("[ai-sommelier] lettura annuncio fallita", { code: error.code });
      return { ok: false, status: 503, corpo: INDISPONIBILE };
    }
    if (!annuncio?.wine_id) {
      return { ok: false, status: 404, corpo: { error: "Questo vino non è disponibile per il Sommelier." } };
    }
    const { data: vino, error: erroreVino } = await supabase
      .from("wines")
      .select(COLONNE_VINO)
      .eq("id", annuncio.wine_id)
      .maybeSingle();
    if (erroreVino) {
      console.error("[ai-sommelier] lettura vino fallita", { code: erroreVino.code });
      return { ok: false, status: 503, corpo: INDISPONIBILE };
    }
    if (!vino) {
      return { ok: false, status: 404, corpo: { error: "Questo vino non è disponibile per il Sommelier." } };
    }
    const riga = { ...(vino as RigaVino), formato: annuncio.formato ?? (vino as RigaVino).formato };
    return { ok: true, blocco: serializzaContesto(costruisciContestoVino(riga, { annoCorrente })).testo };
  }

  // Cantina: il proprietario è `userId` e basta.
  const { data, error, count } = await supabase
    .from("bottle_units")
    .select(COLONNE_BOTTIGLIA, { count: "exact" })
    .eq("owner_id", userId)
    .eq("inventario", "personale")
    .is("deleted_at", null)
    .is("ceduta_at", null)
    .in("stato", ["chiusa", "aperta"])
    .order("created_at", { ascending: true })
    .limit(LIMITI_CONTESTO.righeLetteMax);
  if (error) {
    console.error("[ai-sommelier] lettura Cantina fallita", { code: error.code });
    return { ok: false, status: 503, corpo: INDISPONIBILE };
  }
  const righe = ((data ?? []) as { wines: RigaVino | RigaVino[] | null }[])
    .map((r) => ({ ...r, wines: primo(r.wines) }))
    .filter((r): r is RigaBottiglia => r.wines !== null);
  const letturaLimitata = typeof count === "number" && count > righe.length;
  const contesto = costruisciContestoCantina(righe, messaggio, { annoCorrente, letturaLimitata });
  return { ok: true, blocco: serializzaContesto(contesto).testo };
};

Deno.serve(async (request) => {
  const porta = await apriPorta(request, "ai:chat");
  if (chiusa(porta)) return porta.risposta;
  const { cors, supabase, userId } = porta;

  const lettura = await leggiCorpo(request, cors);
  if ("risposta" in lettura) return lettura.risposta;
  const corpo = lettura.corpo;
  const sessionId = corpo ? testo(corpo.session_id, 64) : null;
  const messaggio = corpo ? testo(corpo.message, MESSAGGIO_MAX_CHARS) : null;
  if (!sessionId || !SESSION_ID.test(sessionId) || !messaggio) {
    return json({ error: "Sessione o messaggio non validi." }, 400, cors);
  }

  const esitoContesto = leggiRichiestaContesto(corpo?.contesto);
  if (!esitoContesto.ok) return json(esitoContesto.corpo, esitoContesto.status, cors);
  const richiestaContesto = esitoContesto.richiesta;

  // WI-016: ingresso per identità PRIMA di ogni lettura di dominio; si chiude qui, o a stream concluso.
  const ingresso = await apriIngresso(supabase, "ai:chat", userId, cors, {
    liberi: [messaggio, ...(richiestaContesto?.tipo === "ricerca" ? [richiestaContesto.produttore, richiestaContesto.nome] : [])],
    identita: [sessionId, messaggio, JSON.stringify(richiestaContesto)],
  });
  if ("risposta" in ingresso) return ingresso.risposta;
  let inStream = false;
  try {
    const risposta = await rispondi({ cors, supabase, userId, sessionId, messaggio, richiestaContesto, ingresso });
    inStream = risposta.headers.get("content-type") === "text/event-stream";
    return risposta;
  } finally {
    if (!inStream) await ingresso.chiudi(false);
  }
});

type Turno = {
  cors: HeadersInit;
  // deno-lint-ignore no-explicit-any
  supabase: any;
  userId: string;
  sessionId: string;
  messaggio: string;
  richiestaContesto: RichiestaContesto | null;
  ingresso: Ingresso;
};

const rispondi = async ({ cors, supabase, userId, sessionId, messaggio, richiestaContesto, ingresso }: Turno): Promise<Response> => {
  // Il contesto passa dalla porta concessa a `service_role`, non dalla vista:
  // con il client di servizio `auth.uid()` è nullo e la vista darebbe zero
  // righe, cioè una conversazione senza memoria che sembra funzionare.
  const { data: contestoGrezzo, error: contestoError } = await supabase.rpc(
    "sommelier_contesto_leggi",
    { p_owner_id: userId, p_session_id: sessionId, p_limite: CONTESTO_MESSAGGI },
  );
  if (contestoError) {
    console.error("[ai-sommelier] lettura contesto fallita", { code: contestoError.code });
    return json({ error: "Il Sommelier non è al momento disponibile." }, 503, cors);
  }
  // WI-016: stessa regola dell'ingresso anche per lo storico: una riga salvata con un dato sensibile non riparte.
  const contesto = ((contestoGrezzo ?? []) as RigaContesto[]).filter(
    (riga) => rilevaDatiSensibili(riga.contenuto) === null,
  );

  let system = SYSTEM;
  let prompt = costruisciPrompt(contesto, messaggio);
  if (richiestaContesto) {
    // Lettura autorizzata PRIMA del fornitore: se fallisce non parte nessuna chiamata.
    let letto: Letto;
    try {
      letto = await leggiContesto(supabase, userId, richiestaContesto, messaggio);
    } catch (errore) {
      // Anche un'eccezione imprevista resta un 503 generico con gli header CORS:
      // senza, il browser vedrebbe un errore opaco e i log lo stack.
      console.error("[ai-sommelier] contesto non costruito", {
        tipo: errore instanceof Error ? errore.name : "sconosciuto",
      });
      return json(INDISPONIBILE, 503, cors);
    }
    if (!letto.ok) return json(letto.corpo, letto.status, cors);
    if (!("vuoto" in letto)) {
      system = SYSTEM + PROMPT_ISTRUZIONI_CONTESTO + (letto.istruzioni ?? "");
      // Lo storico è testo di conversazioni precedenti: con dati in gioco potrebbe
      // ripetere un valore ostile del database, quindi ogni riga torna ripulita.
      prompt = costruisciPromptConContesto(
        letto.blocco,
        costruisciPrompt(
          contesto.map((riga) => ({ ruolo: riga.ruolo, contenuto: pulisciRigaStorico(riga.contenuto) })),
          messaggio,
        ),
      );
    }
  }

  // Tentativi e riserva valgono solo PRIMA che lo stream cominci: dopo, l'errore è un evento dentro lo stream e
  // una risposta parziale non si rifà.
  const chiamata = await chiamataGovernata({
    supabase,
    userId,
    scope: "ai:chat",
    compito: "chat",
    cors,
    ingresso,
    system,
    prompt,
    nonDisponibile: "Il Sommelier non è al momento disponibile.",
    chiama: (provider, call) => provider.streamText(call),
  });
  if (!chiamata.ok) return chiamata.risposta;
  const { richiestaId } = chiamata;
  const sorgente = chiamata.valore;

  const encoder = new TextEncoder();
  const { readable, writable } = new TransformStream<Uint8Array, Uint8Array>();

  const inoltra = async () => {
    const writer = writable.getWriter();
    const lettore = sorgente.getReader();
    // WI-010: l'interruttore è globale, quindi conta solo un errore LETTO dal fornitore. Una scrittura verso un
    // client che se n'è andato finisce nello stesso `catch` e non deve poter spegnere l'AI a tutti.
    let guastoFornitore = false;
    let consuntivata = false;
    let completata = false;
    const scadenza = Date.now() + LETTURA_MASSIMA_MS;
    try {
      let raccolta = "";
      let verificabile = true;
      while (true) {
        const { done, value } = await leggiEntroScadenza(lettore.read(), Math.min(timeoutMs(), scadenza - Date.now()))
          .catch((errore: unknown) => {
            guastoFornitore = true;
            throw errore;
          });
        if (done) break;
        raccolta += value;
        if (raccolta.length > RISPOSTA_VERIFICABILE_MAX_CHARS) {
          verificabile = false;
          void lettore.cancel().catch(() => {});
          break;
        }
        await writer.write(encoder.encode(IN_VERIFICA));
      }

      await registraEsitoFornitore(supabase, "ai:chat", true);
      await registraConsuntivo(supabase, richiestaId, verificabile ? "ok" : "formato_non_valido", chiamata.uso());
      consuntivata = true;

      // La verifica guarda la risposta INTERA, prima del troncamento: un segreto a cavallo del tetto si vede.
      const bloccata = !verificabile || rilevaDatiSensibili(raccolta) !== null;
      if (bloccata) {
        if (verificabile) await segnalaSicurezza(supabase, userId, "ai:chat", "output_scartato");
        await ingresso.chiudi(false);
        await writer.write(
          encoder.encode(sse({ error: verificabile ? RISPOSTA_BLOCCATA : "Il Sommelier non è al momento disponibile." })),
        );
        return;
      }

      // Troncamento in uscita, come `remaining_chars`
      // (`backend/ai_routes.py:72`, `:79-87`): vale su ciò che si trasmette e
      // su ciò che si salva.
      const trasmessa = raccolta.slice(0, RISPOSTA_MAX_CHARS);
      if (trasmessa) await writer.write(encoder.encode(sse({ delta: trasmessa })));
      const risposta = trasmessa.trim();
      if (risposta) {
        // Si salva solo qui: a stream concluso e non vuoto. Una risposta
        // interrotta a metà non entra nello storico, perché diventerebbe il
        // contesto delle battute successive.
        const { error } = await supabase.rpc("sommelier_scambio_registra", {
          p_owner_id: userId,
          p_session_id: sessionId,
          p_domanda: messaggio,
          p_risposta: risposta,
        });
        if (error) {
          // Il testo è già arrivato all'utente: qui non si può più cambiare la
          // risposta, si può solo non mentire sul fatto che non è stata
          // salvata. Resta nel log della function, come vuole la 7.5.
          console.error("[ai-sommelier] scambio non salvato", { code: error.code });
        }
      }
      completata = true;
      // la porta si chiude PRIMA di «done»: chi ripete subito la domanda non deve trovarla ancora in corso
      await ingresso.chiudi(true);
      await writer.write(encoder.encode(sse({ done: true })));
    } catch (errore) {
      // Evento generico dentro lo stream e nessun salvataggio, come
      // `backend/ai_routes.py:88-90`. Il messaggio del fornitore non esce.
      if (guastoFornitore) await registraEsitoFornitore(supabase, "ai:chat", false);
      // In ogni caso si ferma la lettura dal fornitore (client andato via o fornitore muto). Senza attendere:
      // un fornitore muto potrebbe non confermare mai l'annullamento.
      void lettore.cancel().catch(() => {});
      if (!consuntivata) {
        await registraConsuntivo(supabase, richiestaId, guastoFornitore ? "guasto_fornitore" : "interrotta_client", chiamata.uso());
      }
      console.error("[ai-sommelier] stream interrotto", {
        tipo: errore instanceof Error ? errore.name : "sconosciuto",
      });
      await ingresso.chiudi(completata);
      try {
        await writer.write(
          encoder.encode(sse({ error: "Il Sommelier non è al momento disponibile." })),
        );
      } catch {
        // Il lato scrivente è già chiuso: non c'è nessuno da avvisare.
      }
    } finally {
      try {
        await writer.close();
      } catch {
        // Idem.
      }
      await ingresso.chiudi(completata);
    }
  };

  // Il punto: senza questo, la piattaforma può ritirare il worker appena la
  // `Response` è restituita, e i chunk ancora in arrivo dal fornitore vanno
  // persi a metà risposta.
  const attendi = (globalThis as { EdgeRuntime?: { waitUntil?: (p: Promise<unknown>) => void } })
    .EdgeRuntime?.waitUntil;
  const lavoro = inoltra();
  if (typeof attendi === "function") attendi(lavoro);

  return new Response(readable, {
    status: 200,
    headers: {
      ...cors,
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      // Stesso header del legacy (`backend/ai_routes.py:107`): senza, un proxy
      // che bufferizza annulla il vantaggio dello streaming.
      "X-Accel-Buffering": "no",
    },
  });
};
