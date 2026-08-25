"use client";

// Fase 12b + 12c - le discussioni di un club: composizione, lettura, risposte,
// like e segnalazione.
//
// Un componente solo per le due pagine. /community mostra le discussioni di
// tutti i club e /community/[slug] quelle di uno, ma la scheda di un post e la
// stessa cosa: duplicarla vorrebbe dire che il giorno in cui una delle due
// impara a mostrare la risposta rimossa, l'altra no.
//
// LA COMPOSIZIONE STA SOLO SULLA SCHEDA DI UN CLUB. Si scrive DENTRO un club,
// quindi il modulo ha bisogno di uno slug; all'elenco quello slug non c'e, e
// aggiungere un menu "in quale club?" sarebbe una schermata che nessuno ha
// chiesto. All'elenco si legge, si mette like e si segnala.
//
// OGNI TESTO PUBBLICO HA IL SUO "SEGNALA", E QUESTO E IL PUNTO DELLA 12C.
// Non e una rifinitura: e la condizione a cui la scrittura di contenuti e stata
// ammessa. Un post e una risposta sono entrambi segnalabili, con i due bersagli
// `post` e `commento` che la decisione 7.6a teneva sospesi. Il proprio
// contenuto fa eccezione soltanto nella UI, dove il pulsante non compare;
// segnalarlo resta possibile ed e, per l'autore, l'unica richiesta di revisione
// disponibile, perche la 12b non gli da una porta per cancellare.

import Link from "next/link";
import { useState } from "react";
import { Heart, MessageSquare, Send } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { ErrorState } from "@/components/vinea/States";
import { ReportDialog } from "@/components/vinea/ReportDialog";
import { formatEUR, formatInteger } from "@/lib/format";
import {
  ETICHETTE_TIPO_POST,
  LIMITI_POST,
  TIPI_POST,
  validaNuovoPost,
  validaRisposta,
} from "@/lib/phase12/club-post-view";
import { useClubPosts } from "@/lib/phase12/use-club-posts";
import type {
  ClubPost,
  ClubPostRisposta,
  ClubPostTipo,
  NuovoClubPost,
} from "@/services/types";

// La data la formatta il browser con il fuso di chi guarda. Non si prova a
// dire "3 giorni fa" come il mock: quella stringa era un dato scritto a mano
// (frontend/src/data/communities.ts), e ricalcolarla davvero significa
// scegliere un istante di riferimento che il server e il client non hanno in
// comune - cioe l'errore di idratazione che se ne va solo per caso.
const quando = (iso: string) =>
  new Date(iso).toLocaleDateString("it-IT", {
    day: "numeric",
    month: "long",
    year: "numeric",
  });

export function ClubDiscussioni({
  iniziali,
  clubSlug,
  ordina,
  mostraClub = false,
  puoScrivere = true,
}: {
  iniziali: ClubPost[];
  // Assente all'elenco: senza un club non c'e un posto in cui scrivere, e il
  // modulo di composizione non viene montato.
  clubSlug?: string;
  ordina?: (post: ClubPost[]) => ClubPost[];
  mostraClub?: boolean;
  // Falso quando il club e OWNER_ONLY e chi guarda non e il proprietario. E una
  // cortesia della UI, non la barriera: quella sono i trigger
  // club_posts_owner_only_guard e club_post_risposte_owner_only_guard, che
  // valgono per ogni percorso.
  //
  // All'elenco di /community resta `true` anche per i post di club OWNER_ONLY:
  // `public_club_posts` non porta la modalita del club, e portarcela vorrebbe
  // dire riscrivere una vista della 12b da una PR sulla creazione. In quel caso
  // il rifiuto arriva dal database con il suo messaggio, che e fra i codici
  // leggibili e dice esattamente perche.
  puoScrivere?: boolean;
}) {
  const [post, setPost] = useState<ClubPost[]>(iniziali);
  const azioni = useClubPosts();

  // Derivazione, non effetto: l'ordinamento si ricalcola a ogni render dallo
  // stato, e non c'e un secondo stato "ordinato" da tenere allineato.
  const elenco = ordina ? ordina(post) : post;

  const sostituisci = (aggiornato: ClubPost) =>
    setPost((precedenti) =>
      precedenti.map((p) => (p.id === aggiornato.id ? aggiornato : p)),
    );

  return (
    <div className="space-y-4">
      {clubSlug && puoScrivere && azioni.pubblica && (
        <ComponiPost
          clubSlug={clubSlug}
          inCorso={azioni.inCorso === "nuovo"}
          pubblica={azioni.pubblica}
          onPubblicato={(nuovo) => setPost((precedenti) => [nuovo, ...precedenti])}
        />
      )}

      {azioni.error && (
        <ErrorState title="Operazione non riuscita" message={azioni.error} home={false} />
      )}

      {elenco.length === 0 ? (
        <div
          data-testid="club-nessuna-discussione"
          className="rounded-2xl border border-dashed border-border bg-card p-10 text-center text-muted-foreground"
        >
          <p className="font-serif text-lg text-foreground">Nessuna discussione, per ora</p>
          <p className="mt-1 text-sm">
            {clubSlug
              ? "Apri tu la prima: racconta una bottiglia, chiedi un parere, proponi un confronto."
              : "Entra in un club e apri la prima discussione."}
          </p>
        </div>
      ) : (
        <div className="space-y-4" data-testid="club-discussioni">
          {elenco.map((p) => (
            <SchedaPost
              key={p.id}
              post={p}
              mostraClub={mostraClub}
              azioni={azioni}
              puoScrivere={puoScrivere}
              onAggiornato={sostituisci}
            />
          ))}
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Composizione
// ---------------------------------------------------------------------------

function ComponiPost({
  clubSlug,
  inCorso,
  pubblica,
  onPubblicato,
}: {
  clubSlug: string;
  inCorso: boolean;
  pubblica: (input: NuovoClubPost) => Promise<ClubPost | null>;
  onPubblicato: (post: ClubPost) => void;
}) {
  const [aperto, setAperto] = useState(false);
  const [tipo, setTipo] = useState<ClubPostTipo>("discussione");
  const [titolo, setTitolo] = useState("");
  const [corpo, setCorpo] = useState("");
  const [errore, setErrore] = useState<string | null>(null);

  // `annuncio` non e fra i tipi proponibili: a database quel tipo esige un
  // listing_id, e sceglierlo qui vorrebbe dire aggiungere al modulo un
  // selettore dei propri annunci pubblicati - una schermata che nessuna
  // sessione ha chiesto. Il tipo esiste nello schema perche esiste nel mock e
  // perche il vincolo che lo governa va scritto una volta sola, non perche
  // questo checkpoint lo apra alla composizione.
  const proponibili = TIPI_POST.filter((t) => t !== "annuncio");

  const invia = async () => {
    const input: NuovoClubPost = { clubSlug, tipo, titolo, corpo };
    // La validazione replica i CHECK della migrazione, e il vincolo
    // autoritativo resta quello: qui si guadagna un messaggio in italiano
    // prima del giro di rete, non una garanzia.
    const problema = validaNuovoPost(input);
    if (problema) {
      setErrore(problema);
      return;
    }
    setErrore(null);
    const creato = await pubblica(input);
    if (!creato) return;
    onPubblicato(creato);
    setTitolo("");
    setCorpo("");
    setTipo("discussione");
    setAperto(false);
  };

  if (!aperto) {
    return (
      <Button
        onClick={() => setAperto(true)}
        data-testid="club-apri-composizione"
        className="bg-bordeaux hover:bg-bordeaux/90"
      >
        Apri una discussione
      </Button>
    );
  }

  return (
    <section
      className="rounded-2xl border border-border bg-card p-4"
      data-testid="club-composizione"
    >
      <div className="grid gap-3">
        <div>
          <Label htmlFor="post-tipo">Tipo</Label>
          <select
            id="post-tipo"
            value={tipo}
            onChange={(e) => setTipo(e.target.value as ClubPostTipo)}
            data-testid="club-post-tipo"
            className="mt-1 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
          >
            {proponibili.map((t) => (
              <option key={t} value={t}>
                {ETICHETTE_TIPO_POST[t]}
              </option>
            ))}
          </select>
        </div>

        <div>
          <Label htmlFor="post-titolo">Titolo</Label>
          <Input
            id="post-titolo"
            value={titolo}
            maxLength={LIMITI_POST.titoloMax}
            onChange={(e) => setTitolo(e.target.value)}
            placeholder="Di cosa vuoi parlare?"
            data-testid="club-post-titolo"
            className="mt-1"
          />
        </div>

        <div>
          <Label htmlFor="post-corpo">Testo</Label>
          <Textarea
            id="post-corpo"
            value={corpo}
            rows={5}
            maxLength={LIMITI_POST.corpoMax}
            onChange={(e) => setCorpo(e.target.value)}
            data-testid="club-post-corpo"
            className="mt-1"
          />
          <p className="mt-1 text-xs text-muted-foreground">
            {corpo.length}/{LIMITI_POST.corpoMax} caratteri
          </p>
        </div>

        {errore && (
          <p role="alert" className="rounded-xl bg-destructive/10 p-3 text-sm text-destructive">
            {errore}
          </p>
        )}

        <div className="flex gap-2">
          <Button
            onClick={() => void invia()}
            disabled={inCorso}
            data-testid="club-post-pubblica"
            className="bg-bordeaux hover:bg-bordeaux/90"
          >
            {inCorso ? "Pubblico…" : "Pubblica"}
          </Button>
          <Button variant="ghost" onClick={() => setAperto(false)}>
            Annulla
          </Button>
        </div>
      </div>
    </section>
  );
}

// ---------------------------------------------------------------------------
// Scheda di un post
// ---------------------------------------------------------------------------

function SchedaPost({
  post,
  mostraClub,
  azioni,
  puoScrivere,
  onAggiornato,
}: {
  post: ClubPost;
  mostraClub: boolean;
  azioni: ReturnType<typeof useClubPosts>;
  puoScrivere: boolean;
  onAggiornato: (post: ClubPost) => void;
}) {
  const [risposte, setRisposte] = useState<ClubPostRisposta[] | null>(null);
  const [apertoRisposte, setApertoRisposte] = useState(false);
  const attesa = azioni.inCorso === post.id;

  const apriRisposte = async () => {
    if (apertoRisposte) {
      setApertoRisposte(false);
      return;
    }
    setApertoRisposte(true);
    // Si rilegge a ogni apertura e non solo la prima volta: fra un'apertura e
    // l'altra qualcuno puo aver risposto, o la moderazione puo aver rimosso.
    // Un marcatore "gia lette" andrebbe in un ref e non in stato (lezione di
    // 10c); qui non serve affatto, perche la lettura la comanda il clic.
    setRisposte(await azioni.leggiRisposte(post.id));
  };

  return (
    <article
      className="rounded-2xl border border-border bg-card p-4"
      data-testid={`club-post-${post.id}`}
    >
      <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
        <span className="rounded-full bg-secondary px-2 py-0.5 font-medium text-antracite">
          {ETICHETTE_TIPO_POST[post.tipo]}
        </span>
        {mostraClub && (
          <Link href={`/community/${post.clubSlug}`} className="hover:text-foreground">
            {post.clubSlug}
          </Link>
        )}
        {/* `autoreId` era gia sulla riga del post: chi ha scritto e un dato che
            la vista porta da sempre, e la scheda ne mostrava soltanto il nome.
            Renderlo un link non aggiunge nessuna lettura. */}
        <Link
          href={`/profilo/${post.autoreId}`}
          className="hover:text-foreground hover:underline"
          data-testid={`club-post-autore-${post.id}`}
        >
          {post.autoreUsername}
        </Link>
        <span>·</span>
        <time dateTime={post.createdAt}>{quando(post.createdAt)}</time>
      </div>

      <h3 className="mt-2 font-serif text-lg font-semibold">{post.titolo}</h3>
      <p className="mt-1 whitespace-pre-line text-sm text-muted-foreground">{post.corpo}</p>

      {post.vino && (
        <p className="mt-2 text-sm">
          <span className="text-muted-foreground">Bottiglia: </span>
          {post.vino.produttore} {post.vino.nome} {post.vino.annata}
        </p>
      )}

      {post.annuncio && (
        <Link
          href={`/annuncio/${post.annuncio.slug}`}
          data-testid={`club-post-annuncio-${post.id}`}
          className="mt-2 inline-flex items-center gap-2 rounded-xl border border-border px-3 py-2 text-sm hover:bg-secondary"
        >
          Vedi l&apos;annuncio · {formatEUR(post.annuncio.prezzoCents / 100)}
        </Link>
      )}

      <div className="mt-3 flex flex-wrap items-center gap-2">
        <Button
          size="sm"
          variant={post.piaciuto ? "default" : "outline"}
          disabled={!azioni.cambiaLike || attesa}
          onClick={async () => {
            if (!azioni.cambiaLike) return;
            const aggiornato = await azioni.cambiaLike(post);
            if (aggiornato) onAggiornato(aggiornato);
          }}
          data-testid={`club-like-${post.id}`}
        >
          <Heart className="h-3.5 w-3.5" /> {formatInteger(post.miPiace)}
        </Button>

        <Button
          size="sm"
          variant="ghost"
          onClick={() => void apriRisposte()}
          data-testid={`club-risposte-${post.id}`}
        >
          <MessageSquare className="h-3.5 w-3.5" /> {formatInteger(post.risposte)} risposte
        </Button>

        {/* Il proprio contenuto non mostra "Segnala": non ci si denuncia da
            soli con un pulsante. Resta possibile dalla RPC, ed e l'unica
            richiesta di revisione che un autore ha. */}
        {!post.mio && (
          <ReportDialog
            targetType="post"
            targetId={post.id}
            targetLabel={post.titolo}
            clubSlug={post.clubSlug}
            variant="icon"
          />
        )}
      </div>

      {apertoRisposte && (
        <Risposte
          post={post}
          risposte={risposte}
          azioni={azioni}
          puoScrivere={puoScrivere}
          onNuova={(r) => {
            setRisposte((precedenti) => [...(precedenti ?? []), r]);
            // Il conteggio e del server: qui si sposta di uno perche la
            // risposta e appena stata scritta da chi guarda, non perche il
            // client lo indovini. La prossima lettura della pagina lo riporta
            // al valore canonico.
            onAggiornato({ ...post, risposte: post.risposte + 1 });
          }}
        />
      )}
    </article>
  );
}

// ---------------------------------------------------------------------------
// Risposte
// ---------------------------------------------------------------------------

function Risposte({
  post,
  risposte,
  azioni,
  puoScrivere,
  onNuova,
}: {
  post: ClubPost;
  risposte: ClubPostRisposta[] | null;
  azioni: ReturnType<typeof useClubPosts>;
  puoScrivere: boolean;
  onNuova: (risposta: ClubPostRisposta) => void;
}) {
  const [corpo, setCorpo] = useState("");
  const [errore, setErrore] = useState<string | null>(null);

  const invia = async () => {
    if (!azioni.rispondi) return;
    const problema = validaRisposta(corpo);
    if (problema) {
      setErrore(problema);
      return;
    }
    setErrore(null);
    const creata = await azioni.rispondi(post.id, corpo);
    if (!creata) return;
    onNuova(creata);
    setCorpo("");
  };

  return (
    <div className="mt-4 space-y-3 border-t border-border pt-3" data-testid={`club-thread-${post.id}`}>
      {risposte === null ? (
        <p className="text-sm text-muted-foreground">Carico le risposte…</p>
      ) : risposte.length === 0 ? (
        <p className="text-sm text-muted-foreground">Nessuna risposta. Scrivi tu la prima.</p>
      ) : (
        risposte.map((r) => (
          <div key={r.id} className="rounded-xl bg-secondary/40 p-3" data-testid={`club-risposta-${r.id}`}>
            <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
              {/* Stessa cosa per chi risponde: `autoreId` sta gia sulla riga
                  della risposta. Un commento non e meno di una persona di
                  quanto lo sia un post. */}
              <Link
                href={`/profilo/${r.autoreId}`}
                className="hover:text-foreground hover:underline"
                data-testid={`club-risposta-autore-${r.id}`}
              >
                {r.autoreUsername}
              </Link>
              <span>·</span>
              <time dateTime={r.createdAt}>{quando(r.createdAt)}</time>
              {/* Anche la risposta e segnalabile, con il bersaglio `commento`.
                  E' la meta 12c della coppia: nessun testo pubblico senza un
                  modo per segnalarlo. */}
              {!r.mio && (
                <ReportDialog
                  targetType="commento"
                  targetId={r.id}
                  targetLabel={r.corpo.slice(0, 120)}
                  clubSlug={post.clubSlug}
                  variant="icon"
                />
              )}
            </div>
            <p className="mt-1 whitespace-pre-line text-sm">{r.corpo}</p>
          </div>
        ))
      )}

      {puoScrivere && azioni.rispondi && (
        <div className="flex flex-col gap-2">
          <Textarea
            value={corpo}
            rows={3}
            maxLength={LIMITI_POST.rispostaMax}
            onChange={(e) => setCorpo(e.target.value)}
            placeholder="Scrivi una risposta…"
            aria-label="Scrivi una risposta"
            data-testid={`club-risposta-corpo-${post.id}`}
          />
          {errore && (
            <p role="alert" className="rounded-xl bg-destructive/10 p-3 text-sm text-destructive">
              {errore}
            </p>
          )}
          <Button
            size="sm"
            onClick={() => void invia()}
            disabled={azioni.inCorso === post.id}
            data-testid={`club-rispondi-${post.id}`}
            className="w-fit bg-bordeaux hover:bg-bordeaux/90"
          >
            <Send className="h-3.5 w-3.5" /> Rispondi
          </Button>
        </div>
      )}
    </div>
  );
}
