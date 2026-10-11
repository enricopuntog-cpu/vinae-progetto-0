"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState, type ChangeEvent } from "react";
import { ExternalLink, ImagePlus, Loader2, Store, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { ErrorState, LoadingBlock } from "@/components/vinea/States";
import { routes } from "@/config/routes";
import {
  preparaImmagineVetrina,
  type RuoloImmagineVetrina,
} from "@/lib/partner/prepara-immagine-vetrina";
import {
  MAX_DESCRIZIONE,
  MAX_FOTO_VETRINA,
  MAX_PRESENTAZIONE,
  mediaNonPiuUsati,
  urlMediaVetrina,
  validaTestiVetrina,
} from "@/lib/partner/vetrina";
import { getSupabaseClient } from "@/lib/supabase/client";
import { creaVetrinaPartnerService } from "@/services/partner-vetrina-service";
import type { VetrinaPartnerMia } from "@/services/types";

/**
 * Gestione della vetrina da parte del titolare (Blocco B).
 *
 * Il flusso dei file è quello che la policy del bucket impone: si carica un
 * file NUOVO (mai sovrascrivere), si salva la vetrina che lo cita, e solo dopo
 * si cancellano i file che non cita più — la policy rifiuta la cancellazione
 * di un file ancora in uso. Ogni immagine è ricodificata in WebP nel browser
 * prima di partire. Il logo aziendale è un file della vetrina: l'avatar
 * personale non si tocca.
 */

type Media = { percorso: string; anteprima: string };

type Bozza = {
  presentazione: string;
  descrizione: string;
  logo: Media | null;
  copertina: Media | null;
  foto: Media[];
};

const ACCEPT = "image/jpeg,image/png,image/webp";

function mediaDa(v: VetrinaPartnerMia, percorso: string | null): Media | null {
  if (!percorso) return null;
  const url = urlMediaVetrina(percorso, v.titolareId, v.partnerId);
  return url ? { percorso, anteprima: url } : null;
}

function bozzaDa(v: VetrinaPartnerMia): Bozza {
  return {
    presentazione: v.presentazione ?? "",
    descrizione: v.descrizione ?? "",
    logo: mediaDa(v, v.logoPath),
    copertina: mediaDa(v, v.copertinaPath),
    foto: v.fotoPaths.map((p) => mediaDa(v, p)).filter((m): m is Media => m !== null),
  };
}

const percorsiDi = (b: Bozza) => ({
  logoPath: b.logo?.percorso ?? null,
  copertinaPath: b.copertina?.percorso ?? null,
  fotoPaths: b.foto.map((f) => f.percorso),
});

function CaricaImmagine({
  id,
  etichetta,
  aiuto,
  disabilitato,
  inCorso,
  onFile,
}: {
  id: string;
  etichetta: string;
  aiuto: string;
  disabilitato: boolean;
  inCorso: boolean;
  onFile: (file: File) => void;
}) {
  const input = useRef<HTMLInputElement>(null);
  const scelto = (e: ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (file) onFile(file);
  };
  return (
    <>
      <input
        ref={input}
        id={id}
        type="file"
        accept={ACCEPT}
        className="sr-only"
        onChange={scelto}
        disabled={disabilitato}
        aria-describedby={`${id}-aiuto`}
      />
      <Button
        type="button"
        variant="outline"
        size="sm"
        onClick={() => input.current?.click()}
        disabled={disabilitato}
      >
        {inCorso ? <Loader2 className="animate-spin" aria-hidden /> : <ImagePlus aria-hidden />}
        {etichetta}
      </Button>
      <p id={`${id}-aiuto`} className="sr-only">
        {aiuto}
      </p>
    </>
  );
}

export function VetrinaEditorClient() {
  const servizio = useMemo(() => creaVetrinaPartnerService(getSupabaseClient()), []);
  const [vetrina, setVetrina] = useState<VetrinaPartnerMia | null>(null);
  const [bozza, setBozza] = useState<Bozza | null>(null);
  const [caricamento, setCaricamento] = useState(true);
  const [errore, setErrore] = useState<string | null>(null);
  const [inCaricamento, setInCaricamento] = useState<RuoloImmagineVetrina | null>(null);
  const [salvataggio, setSalvataggio] = useState(false);
  const [messaggio, setMessaggio] = useState<{ tipo: "ok" | "errore"; testo: string } | null>(null);
  // File caricati in questa sessione e non ancora salvati: se la bozza li
  // scarta, vanno cancellati, altrimenti resterebbero orfani nel bucket.
  const caricatiNonSalvati = useRef<Set<string>>(new Set());
  const anteprimeLocali = useRef<string[]>([]);

  const carica = useCallback(async () => {
    setCaricamento(true);
    setErrore(null);
    const esito = await servizio.mia();
    if (esito.ok) {
      setVetrina(esito.data);
      setBozza(esito.data ? bozzaDa(esito.data) : null);
    } else {
      setErrore(esito.error);
    }
    setCaricamento(false);
  }, [servizio]);

  useEffect(() => {
    void carica();
    const locali = anteprimeLocali.current;
    return () => locali.forEach((u) => URL.revokeObjectURL(u));
  }, [carica]);

  if (caricamento) return <LoadingBlock />;
  if (errore) {
    return <ErrorState title="Vetrina non disponibile" message={errore} onRetry={() => void carica()} />;
  }
  // Nessun Partner: l'area lo spiega già sopra.
  if (!vetrina || !bozza) return null;

  const modificabile = vetrina.modificabile;
  const occupato = salvataggio || inCaricamento !== null;
  const erroriTesti = validaTestiVetrina(bozza);
  const fotoPiene = bozza.foto.length >= MAX_FOTO_VETRINA;

  const aggiungi = async (ruolo: RuoloImmagineVetrina, file: File) => {
    if (occupato) return;
    setInCaricamento(ruolo);
    setMessaggio(null);
    try {
      const preparata = await preparaImmagineVetrina(file, ruolo);
      const esito = await servizio.caricaMedia(vetrina.cartella, preparata);
      if (!esito.ok) {
        setMessaggio({ tipo: "errore", testo: esito.error });
        return;
      }
      caricatiNonSalvati.current.add(esito.data);
      const anteprima = URL.createObjectURL(preparata);
      anteprimeLocali.current.push(anteprima);
      const media = { percorso: esito.data, anteprima };
      setBozza((b) => {
        if (!b) return b;
        if (ruolo === "logo") return { ...b, logo: media };
        if (ruolo === "copertina") return { ...b, copertina: media };
        return { ...b, foto: [...b.foto, media].slice(0, MAX_FOTO_VETRINA) };
      });
    } catch (e) {
      setMessaggio({
        tipo: "errore",
        testo: e instanceof Error ? e.message : "Non è stato possibile preparare l'immagine.",
      });
    } finally {
      setInCaricamento(null);
    }
  };

  const salva = async () => {
    if (occupato || Object.keys(erroriTesti).length > 0) return;
    setSalvataggio(true);
    setMessaggio(null);
    const dopo = percorsiDi(bozza);
    const esito = await servizio.salva({
      presentazione: bozza.presentazione,
      descrizione: bozza.descrizione,
      ...dopo,
    });
    if (esito.ok) {
      // Ora che la vetrina salvata non li cita più, la policy ne consente la
      // cancellazione: i vecchi file sostituiti e quelli caricati e scartati.
      const daCancellare = [
        ...mediaNonPiuUsati(vetrina, dopo),
        ...[...caricatiNonSalvati.current].filter(
          (p) => p !== dopo.logoPath && p !== dopo.copertinaPath && !dopo.fotoPaths.includes(p),
        ),
      ];
      caricatiNonSalvati.current.clear();
      void servizio.cancellaMedia(daCancellare);
      setVetrina(esito.data);
      setBozza((b) => (b ? { ...b, presentazione: esito.data.presentazione ?? "", descrizione: esito.data.descrizione ?? "" } : b));
      setMessaggio({ tipo: "ok", testo: "Vetrina salvata." });
    } else {
      setMessaggio({ tipo: "errore", testo: esito.error });
    }
    setSalvataggio(false);
  };

  const annulla = () => {
    void servizio.cancellaMedia([...caricatiNonSalvati.current]);
    caricatiNonSalvati.current.clear();
    setBozza(bozzaDa(vetrina));
    setMessaggio(null);
  };

  const pubblica = vetrina.stato === "attivo";

  return (
    <section
      className="space-y-6 rounded-2xl border border-border bg-card p-6"
      aria-labelledby="vetrina-editor-titolo"
      data-testid="vetrina-editor"
    >
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 id="vetrina-editor-titolo" className="flex items-center gap-2 font-serif text-2xl">
            <Store className="size-6" aria-hidden /> La tua vetrina
          </h2>
          <p className="mt-1 text-sm text-muted-foreground">
            {pubblica
              ? "È il tuo profilo pubblico su Vinea: chi lo apre vede la tua attività."
              : vetrina.stato === "sospeso"
                ? "Il Partner è sospeso: la vetrina non è pubblica e non si modifica. I contenuti restano conservati."
                : vetrina.stato === "revocato"
                  ? "Il Partner è revocato: la vetrina non è pubblica."
                  : "Puoi prepararla ora: diventerà pubblica sul tuo profilo quando Vinea approverà il Partner."}
          </p>
        </div>
        {pubblica ? (
          <Link
            href={routes.profiloPubblico(vetrina.titolareId)}
            className="inline-flex items-center gap-1 text-sm font-medium text-bordeaux underline"
          >
            Vedi la vetrina <ExternalLink className="h-4 w-4" aria-hidden />
          </Link>
        ) : null}
      </div>

      {!modificabile && vetrina.stato !== "sospeso" && vetrina.stato !== "revocato" ? (
        <p role="note" className="rounded-lg bg-muted p-3 text-sm">
          Il tuo account non può pubblicare contenuti in questo momento.
        </p>
      ) : null}

      <div className="space-y-2">
        <Label>Copertina</Label>
        <div className="relative aspect-[16/9] w-full overflow-hidden rounded-xl bg-antracite sm:aspect-[21/9]">
          {bozza.copertina ? (
            /* eslint-disable-next-line @next/next/no-img-element -- anteprima di
               un file dello Storage o di un blob locale: next/image non serve. */
            <img src={bozza.copertina.anteprima} alt="Anteprima della copertina" className="h-full w-full object-cover" />
          ) : (
            <div className="flex h-full w-full items-center justify-center bg-gradient-to-br from-bordeaux via-antracite to-antracite text-sm text-crema/80">
              Nessuna copertina
            </div>
          )}
        </div>
        {modificabile ? (
          <div className="flex flex-wrap gap-2">
            <CaricaImmagine
              id="vetrina-copertina"
              etichetta={bozza.copertina ? "Sostituisci copertina" : "Carica copertina"}
              aiuto="Immagine orizzontale, ritagliata al centro in formato 16:9."
              disabilitato={occupato}
              inCorso={inCaricamento === "copertina"}
              onFile={(f) => void aggiungi("copertina", f)}
            />
            {bozza.copertina ? (
              <Button type="button" variant="ghost" size="sm" disabled={occupato} onClick={() => setBozza({ ...bozza, copertina: null })}>
                <Trash2 aria-hidden /> Rimuovi
              </Button>
            ) : null}
          </div>
        ) : null}
      </div>

      <div className="space-y-2">
        <Label>Logo</Label>
        <div className="flex items-center gap-4">
          <div className="h-20 w-20 shrink-0 overflow-hidden rounded-xl border border-border bg-crema">
            {bozza.logo ? (
              /* eslint-disable-next-line @next/next/no-img-element -- vedi copertina. */
              <img src={bozza.logo.anteprima} alt="Anteprima del logo" className="h-full w-full object-cover" />
            ) : (
              <div className="flex h-full w-full items-center justify-center text-xs text-muted-foreground">
                Nessun logo
              </div>
            )}
          </div>
          {modificabile ? (
            <div className="flex flex-wrap gap-2">
              <CaricaImmagine
                id="vetrina-logo"
                etichetta={bozza.logo ? "Sostituisci logo" : "Carica logo"}
                aiuto="Immagine quadrata, ritagliata al centro."
                disabilitato={occupato}
                inCorso={inCaricamento === "logo"}
                onFile={(f) => void aggiungi("logo", f)}
              />
              {bozza.logo ? (
                <Button type="button" variant="ghost" size="sm" disabled={occupato} onClick={() => setBozza({ ...bozza, logo: null })}>
                  <Trash2 aria-hidden /> Rimuovi
                </Button>
              ) : null}
            </div>
          ) : null}
        </div>
        <p className="text-xs text-muted-foreground">Il logo è dell&apos;attività: il tuo avatar personale non cambia.</p>
      </div>

      <div className="space-y-2">
        <Label htmlFor="vetrina-presentazione">Presentazione</Label>
        <Textarea
          id="vetrina-presentazione"
          rows={2}
          maxLength={MAX_PRESENTAZIONE}
          value={bozza.presentazione}
          onChange={(e) => setBozza({ ...bozza, presentazione: e.target.value })}
          disabled={!modificabile || occupato}
          aria-invalid={Boolean(erroriTesti.presentazione)}
          aria-describedby="vetrina-presentazione-aiuto"
        />
        <p id="vetrina-presentazione-aiuto" className="text-xs text-muted-foreground">
          {erroriTesti.presentazione ?? `Una frase che racconta l'attività. ${bozza.presentazione.trim().length}/${MAX_PRESENTAZIONE}`}
        </p>
      </div>

      <div className="space-y-2">
        <Label htmlFor="vetrina-descrizione">Descrizione dell&apos;attività</Label>
        <Textarea
          id="vetrina-descrizione"
          rows={6}
          maxLength={MAX_DESCRIZIONE}
          value={bozza.descrizione}
          onChange={(e) => setBozza({ ...bozza, descrizione: e.target.value })}
          disabled={!modificabile || occupato}
          aria-invalid={Boolean(erroriTesti.descrizione)}
          aria-describedby="vetrina-descrizione-aiuto"
        />
        <p id="vetrina-descrizione-aiuto" className="text-xs text-muted-foreground">
          {erroriTesti.descrizione ??
            `Storia, specialità, servizi. Non inserire partita IVA, indirizzi o recapiti: la vetrina è pubblica. ${bozza.descrizione.trim().length}/${MAX_DESCRIZIONE}`}
        </p>
      </div>

      <div className="space-y-2">
        <Label>
          Fotografie dell&apos;attività ({bozza.foto.length}/{MAX_FOTO_VETRINA})
        </Label>
        {bozza.foto.length > 0 ? (
          <ul className="grid grid-cols-2 gap-3">
            {bozza.foto.map((f, i) => (
              <li key={f.percorso} className="relative overflow-hidden rounded-xl bg-secondary">
                {/* eslint-disable-next-line @next/next/no-img-element -- vedi copertina. */}
                <img src={f.anteprima} alt={`Anteprima della fotografia ${i + 1}`} className="aspect-[4/3] h-full w-full object-cover" />
                {modificabile ? (
                  <Button
                    type="button"
                    variant="secondary"
                    size="sm"
                    className="absolute right-2 top-2"
                    disabled={occupato}
                    aria-label={`Rimuovi la fotografia ${i + 1}`}
                    onClick={() => setBozza({ ...bozza, foto: bozza.foto.filter((x) => x.percorso !== f.percorso) })}
                  >
                    <Trash2 aria-hidden />
                  </Button>
                ) : null}
              </li>
            ))}
          </ul>
        ) : (
          <p className="text-sm text-muted-foreground">Nessuna fotografia.</p>
        )}
        {modificabile && !fotoPiene ? (
          <CaricaImmagine
            id="vetrina-foto"
            etichetta="Aggiungi fotografia"
            aiuto={`Fino a ${MAX_FOTO_VETRINA} fotografie.`}
            disabilitato={occupato}
            inCorso={inCaricamento === "foto"}
            onFile={(f) => void aggiungi("foto", f)}
          />
        ) : null}
      </div>

      {messaggio ? (
        <p
          role={messaggio.tipo === "errore" ? "alert" : "status"}
          className={messaggio.tipo === "errore" ? "text-sm text-destructive" : "text-sm"}
        >
          {messaggio.testo}
        </p>
      ) : null}

      {modificabile ? (
        <div className="flex flex-wrap gap-2">
          <Button type="button" onClick={() => void salva()} disabled={occupato || Object.keys(erroriTesti).length > 0}>
            {salvataggio ? <Loader2 className="animate-spin" aria-hidden /> : null}
            Salva vetrina
          </Button>
          <Button type="button" variant="outline" onClick={annulla} disabled={occupato}>
            Annulla modifiche
          </Button>
        </div>
      ) : null}
    </section>
  );
}
