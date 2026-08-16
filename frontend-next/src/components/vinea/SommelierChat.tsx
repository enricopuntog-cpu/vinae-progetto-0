"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { MessageSquareText, Send, Sparkles, X, Trash2, Loader2 } from "lucide-react";
import { getSupabaseClient } from "@/lib/supabase/client";
import { AiTransparencyLabel } from "@/components/vinea/AiTransparencyLabel";
import { BetaActionNotice } from "@/components/vinea/BetaActionNotice";
import { createSupabaseAiService } from "@/services/phase10/supabase-ai-service";
import {
  depositoBrowser,
  sessionIdPersistente,
} from "@/lib/phase10/sommelier-session";
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
 * 1. **Il pannello resta montato per tutti**, anche senza sessione (7.9). È
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

export default function SommelierChat() {
  const { authUser } = useVinea();
  const [aperto, setAperto] = useState(false);
  const [montato, setMontato] = useState(false);
  const [battute, setBattute] = useState<Battuta[]>([]);
  const [testo, setTesto] = useState("");
  const [inCorso, setInCorso] = useState(false);
  const [azioneBloccata, setAzioneBloccata] = useState(false);
  const [sessionId, setSessionId] = useState<string | null>(null);
  const scrollerRef = useRef<HTMLDivElement>(null);
  const storicoRichiesto = useRef<string | null>(null);

  const aiService = useMemo(
    () => (AZIONI_IA_ABILITATE ? createSupabaseAiService(getSupabaseClient()) : null),
    [],
  );
  const utenteCorrente = authUser?.userId ?? null;

  // L'identificativo di sessione si legge dopo il montaggio e mai durante il
  // render: `localStorage` non esiste sul server, e leggerlo nello stato
  // iniziale darebbe due valori diversi fra HTML servito e idratazione.
  useEffect(() => {
    setSessionId(sessionIdPersistente(depositoBrowser()));
    setMontato(true);
  }, []);

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
      if (!messaggio || inCorso || !sessionId) return;
      if (!AZIONI_IA_ABILITATE || !aiService) {
        setAzioneBloccata(true);
        return;
      }

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
      const scriviUltima = (contenuto: string, troncato?: boolean) =>
        setBattute((precedenti) => {
          const copia = [...precedenti];
          copia[copia.length - 1] = { ruolo: "sommelier", contenuto, troncato };
          return copia;
        });

      try {
        const esito = await aiService.sommelierChat(
          { sessionId, messaggio },
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
        setInCorso(false);
      }
    },
    [aiService, inCorso, sessionId],
  );

  const azzera = useCallback(async () => {
    if (sessionId && aiService) await aiService.sommelierCancella(sessionId);
    setBattute([]);
    setAzioneBloccata(false);
  }, [aiService, sessionId]);

  const conversazioneAperta = battute.length > 0;
  const vuoto = !conversazioneAperta && !inCorso;

  if (!montato) return null;

  return (
    <>
      <button
        aria-label="Apri chat Sommelier AI"
        data-testid="sommelier-trigger"
        onClick={() => setAperto(true)}
        className={`fixed right-4 z-40 grid h-14 w-14 place-items-center rounded-full bg-bordeaux text-crema shadow-xl ring-4 ring-bordeaux/25 transition-transform duration-200 hover:scale-105 active:scale-95 md:h-16 md:w-16 ${
          aperto ? "pointer-events-none opacity-0 scale-90" : "opacity-100"
        }`}
        style={{ bottom: "calc(env(safe-area-inset-bottom, 0px) + 5rem)" }}
      >
        <span className="absolute -top-1 -right-1 inline-flex h-3 w-3 rounded-full bg-oro ring-2 ring-crema animate-pulse-soft" />
        <MessageSquareText className="h-6 w-6" />
      </button>

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
                {SUGGERIMENTI.map((s) => (
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
    </>
  );
}
