"use client";

// Creazione di un club da parte di un utente autenticato.
//
// Il pulsante e il modulo stanno nello stesso componente perche sono la stessa
// cosa in due stati: la pagina non deve sapere che esiste un modulo da aprire,
// le basta sapere se chi guarda ha una sessione. Cosi la regola «solo
// autenticati» ha un punto solo, che e il montaggio di questo componente.
//
// Qui non c'e nessuna logica di creazione: validazione, upload della cover,
// chiamata a `club_crea` e rimozione dell'upload se la RPC fallisce vivono in
// `lib/phase12/crea-club.ts`, dove si verificano senza un DOM. Questo file
// raccoglie i campi e mostra l'errore.

import { useRouter } from "next/navigation";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { PRESET_COVER_CLUB, type CoverPresetId } from "@/lib/phase12/club-cover";
import {
  BOZZA_VUOTA,
  LIMITI_CLUB,
  regoleDaTesto,
  validaBozzaClub,
  type BozzaClub,
  type SceltaCover,
} from "@/lib/phase12/crea-club";
import { MIME_INGRESSO } from "@/lib/phase12/prepara-cover-club";
import { useCreaClub } from "@/lib/phase12/use-crea-club";
import type { ClubPostingMode } from "@/services/types";

// Le due modalita si scrivono come le vede chi crea il club, non come le
// chiama il database. `OWNER_ONLY` non e un club privato: chiunque legge, e
// questa etichetta lo dice parlando solo di chi pubblica.
const ETICHETTE_MODALITA: Record<ClubPostingMode, string> = {
  OPEN: "Tutti possono pubblicare",
  OWNER_ONLY: "Solo io posso pubblicare",
};

export function CreaClubForm() {
  const router = useRouter();
  const { crea, inCorso, error } = useCreaClub();
  const [aperto, setAperto] = useState(false);
  const [nome, setNome] = useState(BOZZA_VUOTA.nome);
  const [descrizione, setDescrizione] = useState(BOZZA_VUOTA.descrizione);
  // Le regole si scrivono come testo libero, una per riga, e diventano un
  // elenco solo al momento dell'invio: tenere qui un array vorrebbe dire
  // decidere a ogni tasto premuto se una riga vuota e una regola.
  const [regole, setRegole] = useState("");
  const [modalita, setModalita] = useState<ClubPostingMode>(BOZZA_VUOTA.postingMode);
  const [cover, setCover] = useState<SceltaCover>(BOZZA_VUOTA.cover);
  const [problema, setProblema] = useState<string | null>(null);

  const bozza = (): BozzaClub => ({
    nome,
    descrizione,
    regole: regoleDaTesto(regole),
    postingMode: modalita,
    cover,
  });

  const invia = async () => {
    if (!crea) return;
    // La stessa validazione che `creaClub` rifa comunque. Farla anche qui
    // significa che un nome troppo corto non fa partire ne un upload ne una
    // andata e ritorno di rete.
    const locale = validaBozzaClub(bozza());
    setProblema(locale);
    if (locale) return;

    const club = await crea(bozza());
    if (club) router.push(`/community/${club.slug}`);
  };

  if (!aperto) {
    return (
      <Button
        onClick={() => setAperto(true)}
        data-testid="club-apri-creazione"
        className="bg-oro text-antracite hover:bg-oro/90"
      >
        Crea un Club
      </Button>
    );
  }

  const scegliPreset = (id: CoverPresetId) =>
    setCover((precedente) =>
      // Un secondo clic sullo stesso preset lo toglie: senza questo, una cover
      // scelta per sbaglio non si puo piu non avere.
      precedente.tipo === "preset" && precedente.id === id
        ? { tipo: "nessuna" }
        : { tipo: "preset", id },
    );

  return (
    <section
      className="rounded-2xl border border-border bg-card p-4 text-foreground"
      data-testid="club-creazione"
    >
      <p className="font-serif text-lg font-semibold">Crea un Club</p>
      <div className="mt-3 grid gap-3">
        <div>
          <Label htmlFor="club-nome">Nome</Label>
          <Input
            id="club-nome"
            value={nome}
            maxLength={LIMITI_CLUB.nomeMax}
            onChange={(e) => setNome(e.target.value)}
            placeholder="Come si chiama il Club?"
            data-testid="club-nome"
            className="mt-1"
          />
          {/* L'indirizzo lo decide il server da questo nome: dirlo qui evita
              che la scelta sembri persa quando due club si chiamano uguale e
              il secondo riceve un suffisso. */}
          <p className="mt-1 text-xs text-muted-foreground">
            L&apos;indirizzo del Club viene generato dal nome.
          </p>
        </div>

        <div>
          <Label htmlFor="club-descrizione">Descrizione</Label>
          <Textarea
            id="club-descrizione"
            value={descrizione}
            rows={4}
            maxLength={LIMITI_CLUB.descrizioneMax}
            onChange={(e) => setDescrizione(e.target.value)}
            placeholder="Di cosa si parla in questo Club?"
            data-testid="club-descrizione"
            className="mt-1"
          />
          <p className="mt-1 text-xs text-muted-foreground">
            {descrizione.length}/{LIMITI_CLUB.descrizioneMax} caratteri
          </p>
        </div>

        <div>
          <Label htmlFor="club-regole">Regole</Label>
          <Textarea
            id="club-regole"
            value={regole}
            rows={4}
            onChange={(e) => setRegole(e.target.value)}
            placeholder="Una regola per riga. Puoi lasciare vuoto."
            data-testid="club-regole-testo"
            className="mt-1"
          />
          <p className="mt-1 text-xs text-muted-foreground">
            {regoleDaTesto(regole).length}/{LIMITI_CLUB.regoleMax} regole
          </p>
        </div>

        <fieldset>
          <legend className="text-sm font-medium">Chi puo pubblicare</legend>
          <div className="mt-1 grid gap-1">
            {(Object.keys(ETICHETTE_MODALITA) as ClubPostingMode[]).map((m) => (
              <label key={m} className="flex items-center gap-2 text-sm">
                <input
                  type="radio"
                  name="club-modalita"
                  value={m}
                  checked={modalita === m}
                  onChange={() => setModalita(m)}
                  data-testid={`club-modalita-${m}`}
                />
                {ETICHETTE_MODALITA[m]}
              </label>
            ))}
          </div>
          {/* Detto una volta sola e in chiaro: la modalita restringe la
              scrittura, non la lettura. */}
          <p className="mt-1 text-xs text-muted-foreground">
            In entrambi i casi il Club resta leggibile da tutti.
          </p>
        </fieldset>

        <div>
          <p className="text-sm font-medium">Copertina</p>
          <div className="mt-2 grid grid-cols-2 gap-2 md:grid-cols-4">
            {PRESET_COVER_CLUB.map((voce) => {
              const scelto = cover.tipo === "preset" && cover.id === voce.id;
              return (
                <button
                  key={voce.id}
                  type="button"
                  onClick={() => scegliPreset(voce.id)}
                  aria-pressed={scelto}
                  data-testid={`club-cover-preset-${voce.id}`}
                  className={`overflow-hidden rounded-xl border-2 ${
                    scelto ? "border-oro" : "border-transparent"
                  }`}
                >
                  {/* eslint-disable-next-line @next/next/no-img-element -- SVG
                      statico servito da public/, senza vantaggi da next/image. */}
                  <img
                    src={voce.percorso}
                    alt={voce.etichetta}
                    className="h-16 w-full object-cover"
                  />
                </button>
              );
            })}
          </div>
          <div className="mt-2">
            <Label htmlFor="club-cover-file" className="text-xs text-muted-foreground">
              Oppure carica un&apos;immagine
            </Label>
            <Input
              id="club-cover-file"
              type="file"
              accept={MIME_INGRESSO.join(",")}
              onChange={(e) => {
                const file = e.target.files?.[0];
                setCover(file ? { tipo: "file", file } : { tipo: "nessuna" });
              }}
              data-testid="club-cover-file"
              className="mt-1"
            />
          </div>
        </div>

        {(problema || error) && (
          <p role="alert" className="rounded-xl bg-destructive/10 p-3 text-sm text-destructive">
            {problema ?? error}
          </p>
        )}

        {!crea && (
          <p className="text-sm text-muted-foreground">
            Connessione a Supabase non configurata.
          </p>
        )}

        <div className="flex gap-2">
          <Button
            onClick={() => void invia()}
            disabled={!crea || inCorso}
            data-testid="club-crea"
            className="bg-bordeaux hover:bg-bordeaux/90"
          >
            {inCorso ? "Creo…" : "Crea il Club"}
          </Button>
          <Button variant="ghost" onClick={() => setAperto(false)}>
            Annulla
          </Button>
        </div>
      </div>
    </section>
  );
}
