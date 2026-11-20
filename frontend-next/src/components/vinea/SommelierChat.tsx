"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { MessageSquareText, Send, Sparkles, X, Trash2, Loader2, ShieldCheck } from "lucide-react";
import { getSupabaseClient } from "@/lib/supabase/client";
import { AiTransparencyLabel } from "@/components/vinea/AiTransparencyLabel";
import { BetaActionNotice } from "@/components/vinea/BetaActionNotice";
import { createSupabaseAiService } from "@/services/phase10/supabase-ai-service";
import {
  depositoBrowser,
  sessionIdPersistente,
} from "@/lib/phase10/sommelier-session";
import {
  ascoltaRichiesteSommelier,
  concediConsenso,
  consensoAttivo,
  richiestaContestoServer,
  type Consenso,
  type ContestoUi,
} from "@/lib/phase10/sommelier-contesto-ui";
import { useVinea } from "@/lib/vinea-store";
import { AZIONI_IA_ABILITATE } from "@/config/features";

/**
 * Pannello Sommelier, portato da `frontend/src/components/vinea/SommelierChat.tsx`.
 *
 * Cambia il trasporto, non il comportamento: al posto di `apiJson`/`apiResponse`
 * verso FastAPI ci sono i tre metodi di `AiService` — storico dalla vista,
 * cancellazione via RPC, chat in streaming dalla Edge Function.
 *
 * Tre punti che non sono estetici:
 *
 * 1. **Il pulsante resta disponibile per tutti**, anche senza sessione (7.9). È
 *    parità con `frontend/`, dove il rifiuto arriva dall'API e non dalla UI:
 *    chi non è autenticato vede il pannello, prova, e riceve un messaggio che
 *    dice di accedere. Nascondere il trigger sarebbe una decisione di prodotto
 *    che nessuna sessione ha preso.
 * 2. **Il troncamento è un caso atteso** (7.7). Una Edge Function che inoltra
 *    uno stream può essere interrotta quando il worker viene ritirato: il testo
 *    già arrivato si tiene e si segnala con una riga discreta, non con un
 *    errore. `troncato` viene dall'adapter, che lo mette a falso solo quando
 *    arriva l'evento di chiusura.
 * 3. **Un cambio di utente azzera tutto.** Lo storico appartiene a chi lo ha
 *    scritto: `my_sommelier_messages` filtra su `auth.uid()` dentro la vista,
 *    quindi dopo un logout la lettura sarebbe vuota — ma i messaggi già a
 *    schermo resterebbero visibili al successivo. È la stessa disciplina della
 *    Fase 8 sui canali Realtime.
 */

type Battuta = {
  ruolo: "utente" | "sommelier";
  contenuto: string;
  troncato?: boolean;
};

const SUGGERIMENTI = [
  "Consigliami un vino per una cena a base di pesce",
  "Come conservo un Barolo da invecchiamento?",
  "Che differenza c'è tra Brunello e Rosso di Montalcino?",
];

// WI-004: domande di partenza coerenti con il contesto attivo.
const SUGGERIMENTI_VINO = [
  "Quando è il momento migliore per berlo?",
  "Con quali piatti lo abbino?",
  "Cosa non sai di questo vino?",
];
const SUGGERIMENTI_CANTINA = [
  "Quali vini della mia Cantina potrei aprire questa sera?",
  "Ho qualche bottiglia adatta a una cena di pesce?",
  "Quali bottiglie hanno una finestra di consumo documentata?",
];

export default function SommelierChat({
  inizialmenteAperto = false,
  contestoIniziale = null,
}: {
  inizialmenteAperto?: boolean;
  contestoIniziale?: ContestoUi | null;
}) {
  const { authUser } = useVinea();
  const [aperto, setAperto] = useState(inizialmenteAperto);
  const [montato, setMontato] = useState(false);
  const [battute, setBattute] = useState<Battuta[]>([]);
  const [testo, setTesto] = useState("");
  const [inCorso, setInCorso] = useState(false);
  const [azioneBloccata, setAzioneBloccata] = useState(false);
  const [sessionId, setSessionId] = useState<string | null>(null);
  // WI-004: contesto scelto dalla pagina e consenso alla Cantina. Il consenso nasce
  // spento, vive solo in memoria (mai in localStorage) ed è legato a utente e
  // sessione: logout, cambio account o nuova conversazione lo rendono inerte.
  const [contesto, setContesto] = useState<ContestoUi | null>(contestoIniziale);
  const [consenso, setConsenso] = useState<Consenso | null>(null);
  const scrollerRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const storicoRichiesto = useRef<string | null>(null);
  // Generazione della risposta in corso. Ogni invio ne apre una nuova; cambio di utente, revoca del
  // consenso, chiusura del pannello e «Cancella conversazione» la invalidano: i frammenti tardivi di
  // un flusso partito per un altro utente (o con un consenso poi revocato) vengono scartati.
  const generazione = useRef(0);
  const inVolo = useRef(false);

  const aiService = useMemo(
    () => (AZIONI_IA_ABILITATE ? createSupabaseAiService(getSupabaseClient()) : null),
    [],
  );
  const utenteCorrente = authUser?.userId ?? null;
  const invalidaRisposta = useCallback(() => {
    generazione.current += 1;
    if (inVolo.current) {
      inVolo.current = false;
      // La bolla in attesa non resta vuota: dice che la risposta è stata interrotta.
      setBattute((precedenti) =>
        precedenti.length > 0 && precedenti[precedenti.length - 1].ruolo === "sommelier"
          ? [...precedenti.slice(0, -1), { ruolo: "sommelier", contenuto: "⚠️ Risposta interrotta." }]
          : precedenti,
      );
    }
    setInCorso(false);
  }, []);
  const consensoCantina = consensoAttivo(consenso, utenteCorrente, sessionId);

  // Una richiesta dalla pagina cambia il contesto e NON porta con sé il consenso.
  useEffect(
    () =>
      ascoltaRichiesteSommelier((nuovo) => {
        setContesto(nuovo);
        setConsenso(null);
        setAperto(true);
      }),
    [],
  );

  // Chiudere il pannello revoca il consenso: la lettura della Cantina non
  // sopravvive a una conversazione che l'utente ha chiuso.
  useEffect(() => {
    if (!aperto) {
      setConsenso(null);
      invalidaRisposta();
    }
  }, [aperto, invalidaRisposta]);

  // Logout o cambio di account: si porta via anche il contesto e il consenso.
  const utentePrecedente = useRef(utenteCorrente);
  useEffect(() => {
    if (utentePrecedente.current !== null && utentePrecedente.current !== utenteCorrente) {
      setContesto(null);
      setConsenso(null);
    }
    if (utentePrecedente.current !== utenteCorrente) invalidaRisposta();
    utentePrecedente.current = utenteCorrente;
  }, [utenteCorrente, invalidaRisposta]);

  // Il montaggio controlla soltanto l'animazione del pannello.
  useEffect(() => {
    setMontato(true);
  }, []);

  useEffect(() => {
    if (!montato) return;
    if (aperto) inputRef.current?.focus({ preventScroll: true });
    else triggerRef.current?.focus({ preventScroll: true });
    if (!aperto) return;
    const chiudiConEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") setAperto(false);
    };
    window.addEventListener("keydown", chiudiConEscape);
    return () => window.removeEventListener("keydown", chiudiConEscape);
  }, [aperto, montato]);

  // Memoria soltanto dopo l'apertura esplicita di una chat disponibile.
  // Nessun identificatore viene letto o creato durante la navigazione normale.
  useEffect(() => {
    if (!aperto || !AZIONI_IA_ABILITATE || sessionId) return;
    setSessionId(sessionIdPersistente(depositoBrowser()));
  }, [aperto, sessionId]);

  // Cambio di utente (login, logout, altro account): la conversazione a schermo
  // non è più la sua.
  useEffect(() => {
    setBattute([]);
  }, [utenteCorrente]);

  // Quale conversazione va letta: `null` finché il pannello è chiuso, e diversa
  // per utente, così un cambio di sessione ne provoca la rilettura.
  //
  // Senza utente non si legge affatto. Non è una scorciatoia di prodotto: la
  // vista filtra su `owner_id = (select auth.uid())` al proprio interno, e per
  // un client anonimo `auth.uid()` è nullo, quindi la risposta sarebbe zero
  // righe con certezza. Chiedere lo stesso significherebbe una richiesta di
  // rete garantita inutile a ogni apertura del pannello, che per i visitatori
  // non autenticati sono la maggioranza.
  const chiaveStorico =
    aperto && sessionId && utenteCorrente ? `${utenteCorrente}:${sessionId}` : null;

  useEffect(() => {
    if (!chiaveStorico || !sessionId || !aiService) return;
    if (storicoRichiesto.current === chiaveStorico) return;
    // Il segno «già chiesto» sta in una ref e non nello stato di proposito. Da
    // stato provocherebbe un render, il render rieseguirebbe questo effetto
    // perché il segno è fra le sue dipendenze, e la pulizia della passata
    // precedente annullerebbe la richiesta appena partita: lo storico non
    // arriverebbe mai, e il pannello si aprirebbe sempre vuoto su una
    // conversazione che nel database c'è.
    storicoRichiesto.current = chiaveStorico;
    let annullato = false;
    void aiService.sommelierStorico(sessionId).then((esito) => {
      // Un anonimo non ha storico e la vista gli restituisce zero righe: non è
      // un errore e non va mostrato come tale.
      if (annullato || !esito.ok) return;
      setBattute(
        esito.data.map((messaggio) => ({
          ruolo: messaggio.ruolo,
          contenuto: messaggio.contenuto,
        })),
      );
    });
    return () => {
      annullato = true;
    };
  }, [chiaveStorico, sessionId, aiService]);

  useEffect(() => {
    scrollerRef.current?.scrollTo({
      top: scrollerRef.current.scrollHeight,
      behavior: "smooth",
    });
  }, [battute, inCorso]);

  const invia = useCallback(
    async (grezzo: string) => {
      const messaggio = grezzo.trim();
      if (!messaggio || inCorso) return;
      // Prima del controllo sulla sessione: con le azioni spente la sessione non
      // viene mai creata, e un invio senza risposta né avviso sarebbe un pulsante muto.
      if (!AZIONI_IA_ABILITATE || !aiService) {
        setAzioneBloccata(true);
        return;
      }
      if (!sessionId) return;

      setAzioneBloccata(false);
      setBattute((precedenti) => [
        ...precedenti,
        { ruolo: "utente", contenuto: messaggio },
        { ruolo: "sommelier", contenuto: "" },
      ]);
      setTesto("");
      setInCorso(true);

      // L'accumulo sta in una variabile locale e non nello stato: i frammenti
      // arrivano più fitti di quanto React ridisegni, e ricostruirlo dallo
      // stato a ogni delta significherebbe leggere un valore già vecchio.
      let accumulato = "";
      const mia = ++generazione.current;
      inVolo.current = true;
      const scriviUltima = (contenuto: string, troncato?: boolean) => {
        if (generazione.current !== mia) return;
        setBattute((precedenti) => {
          const copia = [...precedenti];
          copia[copia.length - 1] = { ruolo: "sommelier", contenuto, troncato };
          return copia;
        });
      };

      try {
        const esito = await aiService.sommelierChat(
          {
            sessionId,
            messaggio,
            // Solo una RICHIESTA di contesto: il server rilegge e decide. Senza
            // consenso attivo la Cantina non viene chiesta affatto.
            contesto: richiestaContestoServer(contesto, consensoCantina),
          },
          (delta) => {
            accumulato += delta;
            scriviUltima(accumulato);
          },
        );
        if (esito.ok) {
          scriviUltima(esito.data.testo, esito.data.troncato);
        } else {
          scriviUltima(accumulato ? `${accumulato}\n\n⚠️ ${esito.error}` : `⚠️ ${esito.error}`);
        }
      } finally {
        if (generazione.current === mia) {
          inVolo.current = false;
          setInCorso(false);
        }
      }
    },
    [aiService, inCorso, sessionId, contesto, consensoCantina],
  );

  const azzera = useCallback(async () => {
    invalidaRisposta();
    // Prima lo stato locale, poi la rete: un invio fatto durante l'attesa non viene cancellato.
    setBattute([]);
    setAzioneBloccata(false);
    // Una conversazione nuova riparte generale: né contesto né consenso restano.
    setContesto(null);
    setConsenso(null);
    if (sessionId && aiService) await aiService.sommelierCancella(sessionId);
  }, [aiService, sessionId, invalidaRisposta]);

  const suggerimenti =
    contesto?.tipo === "vino"
      ? SUGGERIMENTI_VINO
      : contesto?.tipo === "cantina" && consensoCantina && !contesto.vuota
        ? SUGGERIMENTI_CANTINA
        : SUGGERIMENTI;
  const conversazioneAperta = battute.length > 0;
  const vuoto = !conversazioneAperta && !inCorso;

  if (!montato) return null;

  return (
    <>
      <button
        ref={triggerRef}
        type="button"
        aria-label="Apri chat Sommelier AI"
        aria-haspopup="dialog"
        aria-expanded={aperto}
        aria-hidden={aperto}
        tabIndex={aperto ? -1 : 0}
        data-testid="sommelier-trigger"
        onClick={() => setAperto(true)}
        className={`fixed right-4 z-40 grid h-14 w-14 place-items-center rounded-full bg-bordeaux text-crema shadow-xl ring-4 ring-bordeaux/25 transition-transform duration-200 hover:scale-105 active:scale-95 md:h-16 md:w-16 ${
          aperto ? "pointer-events-none opacity-0 scale-90" : "opacity-100"
        }`}
        style={{ bottom: "calc(env(safe-area-inset-bottom, 0px) + 5rem)" }}
      >
        <span className="absolute -top-1 -right-1 inline-flex h-3 w-3 rounded-full bg-oro ring-2 ring-crema" />
        <MessageSquareText className="h-6 w-6" />
      </button>

      {aperto && <>
      <div
        onClick={() => setAperto(false)}
        aria-hidden
        className={`fixed inset-0 z-40 bg-antracite/40 backdrop-blur-[2px] transition-opacity duration-200 ${
          aperto ? "opacity-100" : "pointer-events-none opacity-0"
        }`}
      />

      <aside
        role="dialog"
        aria-label="Sommelier AI"
        data-testid="sommelier-panel"
        className={`fixed right-2 bottom-2 z-50 flex w-[min(94vw,420px)] flex-col overflow-hidden rounded-3xl border border-border bg-card shadow-2xl transition-all duration-300 md:right-6 md:bottom-6 md:w-[420px] ${
          aperto
            ? "translate-y-0 opacity-100 pointer-events-auto"
            : "translate-y-4 opacity-0 pointer-events-none"
        }`}
        style={{ maxHeight: "min(78vh, 720px)" }}
      >
        <header className="relative overflow-hidden bg-bordeaux px-4 py-4 text-crema">
          <div
            className="absolute inset-0 opacity-25 animate-ken-burns"
            style={{
              backgroundImage: "radial-gradient(circle at 20% 30%, #B59A63 0%, transparent 55%)",
            }}
          />
          <div className="relative flex items-center gap-3">
            <span className="grid h-10 w-10 place-items-center rounded-full bg-crema/15">
              <Sparkles className="h-5 w-5 text-oro" />
            </span>
            <div className="min-w-0 flex-1">
              <p className="text-[10px] uppercase tracking-[0.3em] text-oro">Vinea Wine Club</p>
              <h2 className="font-serif text-xl leading-none">
                Sommelier <span className="gold-shimmer">AI</span>
              </h2>
              <p className="text-[11px] text-crema/70">Assistente Vinea · risposte in italiano</p>
              <AiTransparencyLabel superficie="sommelier" variante="scura" />
            </div>
            <button
              aria-label="Cancella conversazione"
              data-testid="sommelier-reset"
              onClick={azzera}
              disabled={!conversazioneAperta}
              className="grid h-9 w-9 place-items-center rounded-full bg-crema/10 text-crema/80 transition hover:bg-crema/20 disabled:opacity-30"
            >
              <Trash2 className="h-4 w-4" />
            </button>
            <button
              aria-label="Chiudi chat"
              data-testid="sommelier-close"
              onClick={() => setAperto(false)}
              className="grid h-9 w-9 place-items-center rounded-full bg-crema/10 text-crema transition hover:bg-crema/20"
            >
              <X className="h-4 w-4" />
            </button>
          </div>
        </header>

        {contesto ? (
          <ContestoAttivo
            contesto={contesto}
            consensoAttivo={consensoCantina}
            autenticato={utenteCorrente !== null}
            iaAttiva={AZIONI_IA_ABILITATE}
            onConsenti={() => setConsenso(concediConsenso(utenteCorrente, sessionId))}
            onRevoca={() => {
              setConsenso(null);
              invalidaRisposta();
            }}
            onTogli={() => {
              setContesto(null);
              setConsenso(null);
              invalidaRisposta();
            }}
          />
        ) : null}

        <div
          ref={scrollerRef}
          className="flex-1 overflow-y-auto px-3 py-3"
          data-testid="sommelier-messages"
        >
          {vuoto && (
            <div className="space-y-3 p-2">
              <p className="text-sm text-muted-foreground">
                Ciao! Sono il tuo sommelier virtuale. Chiedimi consigli di abbinamento, curiosità
                sulle denominazioni o dubbi sul servizio.
              </p>
              <div className="grid gap-2">
                {suggerimenti.map((s) => (
                  <button
                    key={s}
                    onClick={() => void invia(s)}
                    data-testid="sommelier-suggestion"
                    className="rounded-2xl border border-border bg-secondary/50 px-3 py-2 text-left text-xs text-antracite transition hover:border-bordeaux hover:bg-bordeaux/5"
                  >
                    {s}
                  </button>
                ))}
              </div>
            </div>
          )}
          {battute.map((battuta, indice) => (
            <div
              key={indice}
              className={`mb-2 flex flex-col ${battuta.ruolo === "utente" ? "items-end" : "items-start"}`}
            >
              <div
                data-testid={
                  battuta.ruolo === "utente" ? "sommelier-msg-user" : "sommelier-msg-assistant"
                }
                className={`max-w-[85%] whitespace-pre-wrap rounded-2xl px-3 py-2 text-sm leading-relaxed shadow-sm ${
                  battuta.ruolo === "utente"
                    ? "rounded-br-md bg-bordeaux text-crema"
                    : "rounded-bl-md border border-border bg-secondary/60 text-antracite"
                }`}
              >
                {battuta.contenuto ||
                  (inCorso && indice === battute.length - 1 ? (
                    <span className="inline-flex items-center gap-1 text-muted-foreground">
                      <Loader2 className="h-3 w-3 animate-spin" /> il sommelier sta scrivendo…
                    </span>
                  ) : (
                    ""
                  ))}
              </div>
              {battuta.troncato && (
                <p
                  className="mt-1 max-w-[85%] text-[11px] text-muted-foreground"
                  data-testid="sommelier-troncato"
                >
                  Risposta interrotta prima della fine: quello che vedi è arrivato per intero, il
                  resto no. Puoi chiedere di continuare.
                </p>
              )}
            </div>
          ))}
        </div>

        {azioneBloccata ? <BetaActionNotice tipo="ia" className="mx-3 mb-3" /> : null}

        <form
          className="flex items-center gap-2 border-t border-border bg-crema/60 px-3 py-3"
          onSubmit={(e) => {
            e.preventDefault();
            void invia(testo);
          }}
        >
          <input
            ref={inputRef}
            value={testo}
            onChange={(e) => {
              setTesto(e.target.value);
              setAzioneBloccata(false);
            }}
            placeholder="Chiedi al sommelier…"
            data-testid="sommelier-input"
            className="min-w-0 flex-1 rounded-full border border-border bg-card px-4 py-2 text-sm outline-none focus:border-bordeaux focus:ring-2 focus:ring-bordeaux/30"
            maxLength={2000}
            disabled={inCorso}
          />
          <button
            type="submit"
            aria-label="Invia messaggio"
            data-testid="sommelier-send"
            disabled={inCorso || !testo.trim()}
            className="grid h-10 w-10 place-items-center rounded-full bg-bordeaux text-crema shadow transition hover:bg-bordeaux/90 disabled:opacity-40"
          >
            {inCorso ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
          </button>
        </form>
      </aside>
      </>}
    </>
  );
}

/**
 * Dice, sempre, quale contesto sta usando il Sommelier e perché: per la scheda di
 * un vino sono dati pubblici; per la Cantina serve il consenso esplicito
 * dell'utente, revocabile in ogni momento.
 */
function ContestoAttivo({
  contesto,
  consensoAttivo: consenso,
  autenticato,
  iaAttiva,
  onConsenti,
  onRevoca,
  onTogli,
}: {
  contesto: ContestoUi;
  consensoAttivo: boolean;
  autenticato: boolean;
  /** Azioni AI accese: in Beta spente il consenso non ha niente da autorizzare. */
  iaAttiva: boolean;
  onConsenti: () => void;
  onRevoca: () => void;
  onTogli: () => void;
}) {
  const bottone =
    "rounded-full border border-border bg-card px-2.5 py-1 text-[11px] font-medium text-antracite transition hover:border-bordeaux focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-bordeaux/40";
  return (
    <div
      role="region"
      aria-label="Contesto del Sommelier"
      data-testid="sommelier-contesto"
      data-tipo={contesto.tipo}
      data-consenso={contesto.tipo === "cantina" ? String(consenso) : undefined}
      className="space-y-2 border-b border-border bg-secondary/50 px-3 py-2.5 text-xs text-antracite"
    >
      {contesto.tipo === "vino" ? (
        <p>
          <span className="font-semibold">Stai chiedendo di: {contesto.etichetta || "questo vino"}.</span>{" "}
          Il Sommelier usa la scheda Vinea di questo vino, senza prezzo né dati del venditore, e distingue ciò che è
          registrato da ciò che è dichiarato o stimato.
        </p>
      ) : contesto.vuota ? (
        <p data-testid="sommelier-cantina-vuota">
          <span className="font-semibold">La tua Cantina è vuota.</span> Non c&apos;è nulla da condividere: il
          Sommelier risponderà in generale.
        </p>
      ) : !autenticato ? (
        <p>
          <span className="font-semibold">Accedi per usare la tua Cantina.</span> Senza sessione il Sommelier non può
          leggerla.
        </p>
      ) : !iaAttiva ? (
        <p data-testid="sommelier-beta-ia-spenta">
          <span className="font-semibold">La funzione IA sarà attivata in un prossimo aggiornamento.</span> Per ora il
          Sommelier non legge la tua Cantina e nessun dato viene inviato a un provider esterno.
        </p>
      ) : consenso ? (
        <p data-testid="sommelier-consenso-attivo" className="flex items-start gap-1.5">
          <ShieldCheck className="mt-0.5 h-3.5 w-3.5 shrink-0 text-bordeaux" aria-hidden />
          <span>
            <span className="font-semibold">Il Sommelier vede la tua Cantina.</span> Usa vini, annate, formati,
            quantità, finestre di consumo (comprese le tue), preferenze e abbinamenti delle tue bottiglie, solo per
            questa conversazione. Non condivide prezzi d&apos;acquisto, note, posizioni, foto né dati
            dell&apos;account. Se il campione è parziale, te lo dirà. Le risposte restano nella cronologia finché non
            la cancelli; revocare ferma le letture future.
          </span>
        </p>
      ) : (
        <p data-testid="sommelier-consenso-richiesto">
          <span className="font-semibold">Il Sommelier non vede la tua Cantina.</span> Se vuoi che risponda sulle
          bottiglie che possiedi, autorizzalo: leggerà vini, annate, formati, quantità, finestre di consumo (comprese
          le tue), preferenze e abbinamenti; non prezzi d&apos;acquisto, note, posizioni, foto né dati
          dell&apos;account. Le risposte restano nella cronologia finché non la cancelli. Puoi revocare in qualsiasi
          momento.
        </p>
      )}
      <div className="flex flex-wrap gap-2">
        {contesto.tipo === "cantina" && autenticato && iaAttiva && !contesto.vuota ? (
          consenso ? (
            <button type="button" className={bottone} onClick={onRevoca} data-testid="sommelier-consenso-revoca">
              Revoca l&apos;accesso alla Cantina
            </button>
          ) : (
            <button
              type="button"
              className={`${bottone} border-bordeaux/40 bg-bordeaux text-crema hover:bg-bordeaux/90`}
              onClick={onConsenti}
              data-testid="sommelier-consenso-concedi"
            >
              Autorizza il Sommelier a usare la mia Cantina
            </button>
          )
        ) : null}
        <button type="button" className={bottone} onClick={onTogli} data-testid="sommelier-contesto-rimuovi">
          Torna al Sommelier generale
        </button>
      </div>
    </div>
  );
}
