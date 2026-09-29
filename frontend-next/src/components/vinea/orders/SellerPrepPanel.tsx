"use client";

import { useRef, useState } from "react";
import Image from "next/image";
import {
  Camera,
  CheckCircle2,
  ClipboardCheck,
  Info,
  Package,
  PackageOpen,
  Truck,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { BetaActionNotice } from "@/components/vinea/BetaActionNotice";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  PROVE_SPEDIZIONE,
  VOCI_IMBALLAGGIO,
  preparazioneConfermabile,
} from "@/lib/orders/imballaggio-checklist";
import {
  ID_CHECKLIST_CONFEZIONE,
  NOTA_CONTESTO_NON_DISPONIBILE,
  NOTA_FOTO_REFERENCE,
  NOTA_HANDOFF_OPERATIVA,
  TITOLO_CONFEZIONE_DICHIARATA,
  TITOLO_FOTO_REFERENCE,
  TITOLO_HANDOFF,
  altFotoConfezione,
  etichettaConfezioneDichiarata,
  etichettaHandoffScelto,
  guidaImballaggio,
} from "@/lib/orders/guida-imballaggio";
import { DISCLAIMER_IMBALLAGGIO } from "@/lib/vendi/logistica-annuncio";
import { puoSpedire } from "@/lib/orders/seller-status";
import type { LogisticaProprietario } from "@/services/listing-service";
import type {
  OrderRecord,
  ShippingEvidence,
  ShippingEvidenceKind,
  VoceChecklist,
} from "@/services/types";

const CORRIERI = ["Corriere Vinea", "BRT", "DHL", "GLS"] as const;

type Props = {
  ordine: OrderRecord;
  /**
   * Le prove CORRENTI, con URL firmate e temporanee. Non sono mai persistite:
   * arrivano da `ordine_spedizione_prove` a ogni lettura dell'ordine.
   */
  prove: ShippingEvidence[];
  /**
   * La logistica dichiarata sull'annuncio collegato, o `null` se la lettura non
   * è riuscita. `null` **non** significa «nessuna confezione»: significa che il
   * contesto manca, e il pannello lo dice invece di attestarlo.
   *
   * Contesto illustrativo, mai un permesso: qualunque valore abbia, il cancello
   * resta le sei voci più la fotografia del collo finale.
   */
  logistica: LogisticaProprietario | null;
  inCorso: boolean;
  onPrepara: (checklist: VoceChecklist[]) => Promise<string | null>;
  onRegistraProva: (kind: ShippingEvidenceKind, file: File) => Promise<string | null>;
  onSpedisci: (corriere: string, tracking: string) => Promise<string | null>;
};

/** Un blocco del pannello: titolo di terzo livello, icona decorativa, corpo. */
function Blocco({
  titolo,
  icona: Icona,
  children,
}: {
  titolo: string;
  icona: typeof Package;
  children: React.ReactNode;
}) {
  return (
    <section>
      <h3 className="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
        {/* L'icona ripete il titolo accanto a lei: per chi ascolta è rumore. */}
        <Icona className="h-4 w-4 shrink-0" aria-hidden="true" />
        {titolo}
      </h3>
      <div className="mt-2">{children}</div>
    </section>
  );
}

function RiquadroProva({
  definizione,
  prova,
  inCorso,
  caricamento,
  onScegli,
}: {
  definizione: (typeof PROVE_SPEDIZIONE)[number];
  prova: ShippingEvidence | undefined;
  inCorso: boolean;
  /** Vero solo per lo slot che sta caricando: `inCorso` è dell'ordine intero. */
  caricamento: boolean;
  onScegli: (file: File) => void;
}) {
  const input = useRef<HTMLInputElement>(null);

  return (
    <div className="rounded-xl border border-border bg-secondary/40 p-3">
      <div className="flex items-center justify-between gap-2">
        <p className="text-sm font-medium">{definizione.titolo}</p>
        <span className="text-[11px] uppercase tracking-wide text-muted-foreground">
          {definizione.obbligo}
        </span>
      </div>
      <p className="mt-1 text-xs text-muted-foreground">{definizione.aiuto}</p>

      <div className="mt-2 flex items-center gap-3">
        {prova ? (
          // eslint-disable-next-line @next/next/no-img-element -- URL firmato e temporaneo.
          <img
            src={prova.url}
            alt={definizione.titolo}
            className="h-16 w-16 rounded-lg border object-cover"
          />
        ) : (
          <div className="flex h-16 w-16 items-center justify-center rounded-lg border border-dashed border-border">
            <Camera className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
          </div>
        )}
        <div className="min-w-0 flex-1">
          <input
            ref={input}
            type="file"
            accept="image/jpeg,image/png,image/webp"
            className="hidden"
            onChange={(e) => {
              const file = e.target.files?.[0];
              // Il campo si svuota comunque: riscegliere lo stesso file non
              // emetterebbe un secondo `change`.
              e.target.value = "";
              if (file) onScegli(file);
            }}
          />
          <Button
            type="button"
            variant="outline"
            size="sm"
            disabled={inCorso}
            onClick={() => input.current?.click()}
          >
            {caricamento
              ? "Caricamento…"
              : prova
                ? "Sostituisci fotografia"
                : "Carica fotografia"}
          </Button>
          {prova && !caricamento && (
            <p className="mt-1 text-[11px] text-muted-foreground">
              Caricata il {new Date(prova.created_at).toLocaleDateString("it-IT")}. Sostituendola,
              la precedente resta archiviata.
            </p>
          )}
        </div>
      </div>
    </div>
  );
}

/**
 * Pannello «Prepara spedizione», lato venditore.
 *
 * Differenza dichiarata rispetto a `frontend/`: là il bottone «Genera
 * etichetta» simulava un numero di tracking e non produceva nulla. Qui la
 * preparazione è una transizione vera (`ordine_prepara_spedizione`) che salva
 * la checklist, e il numero di tracking lo inserisce il venditore — nessuna
 * etichetta viene prodotta, perché era simulazione e resta tale.
 *
 * Dalla WP3 la preparazione ha un cancello: senza le sei voci canoniche e senza
 * la fotografia del collo finale, `preparazione_confermata_at` resta nulla e
 * `ordine_segna_spedito` rifiuta. Quello che si spegne qui è un bottone; il
 * rifiuto vero sta nel database, e questa schermata non lo sostituisce.
 *
 * Dalla WP4 le istruzioni sono contestuali: la confezione originale dichiarata
 * sull'annuncio sceglie quale guida leggere e come è scritta la sesta voce. Una
 * cassa di legno si imballa diversamente da una bottiglia nuda, e finora il
 * pannello chiedeva a entrambe le stesse quattro parole generiche. **Cambia solo
 * la lingua**: gli ID restano sei, il cancello resta quello, e un annuncio senza
 * dichiarazione ottiene la guida prudente invece di un pannello che si rifiuta
 * di aprirsi.
 *
 * Due domini fotografici convivono qui e non devono mescolarsi. In alto le
 * immagini della confezione: vengono dal bucket pubblico `annunci`, sono
 * *reference* del prodotto e sono in sola lettura — da questo pannello non si
 * caricano, non si sostituiscono, non si cancellano. In basso le prove: bucket
 * privato, URL firmate che scadono, ed è di quelle che il database tiene conto.
 */
export function SellerPrepPanel({
  ordine,
  prove,
  logistica,
  inCorso,
  onPrepara,
  onRegistraProva,
  onSpedisci,
}: Props) {
  // `null` qui è una lettura non riuscita, non un annuncio legacy: il pannello
  // esiste solo per il venditore, e per lui `listings_select_own` la riga ce
  // l'ha sempre. I due casi si dicono diversamente perché sono diversi — uno è
  // «non lo so», l'altro è «non è stato dichiarato».
  const contestoMancante = logistica === null;
  const tipoConfezione = logistica?.confezioneOriginaleTipo ?? null;
  const fotoConfezione = logistica?.confezioneOriginaleFotoUrl ?? [];
  const guida = guidaImballaggio(tipoConfezione);

  const salvate = new Map(ordine.imballaggio_checklist.map((v) => [v.id, v.done]));
  const [spunte, setSpunte] = useState<Record<string, boolean>>(
    Object.fromEntries(VOCI_IMBALLAGGIO.map((v) => [v.id, salvate.get(v.id) ?? false])),
  );
  const [corriere, setCorriere] = useState<string>(ordine.corriere ?? "Corriere Vinea");
  const [tracking, setTracking] = useState(ordine.tracking_number ?? "");
  const [errore, setErrore] = useState<string | null>(null);
  const [caricamento, setCaricamento] = useState<ShippingEvidenceKind | null>(null);

  const perTipo = new Map(prove.map((p) => [p.evidence_kind, p]));
  const colloCaricato = perTipo.has("collo_finale");
  const confermataAt = ordine.preparazione_confermata_at;
  const trackingValido = /^[A-Za-z0-9._-]{4,64}$/.test(tracking);

  // La sesta voce cambia parole, non identità: la sostituzione è per ID e non
  // per posizione, e le altre cinque escono intatte da qui. `private.
  // imballaggio_checklist_completa()` conta gli `id` e legge `done`; la `label`
  // la registra e non la confronta, quindi quello che si salva è esattamente la
  // frase che il venditore ha letto mentre spuntava.
  const voci = VOCI_IMBALLAGGIO.map((v) =>
    v.id === ID_CHECKLIST_CONFEZIONE ? { ...v, label: guida.checklistConfezioneLabel } : v,
  );

  const checklist = (): VoceChecklist[] =>
    voci.map((v) => ({ id: v.id, label: v.label, done: !!spunte[v.id] }));

  const confermabile = preparazioneConfermabile(
    checklist(),
    prove.map((p) => p.evidence_kind),
  );

  return (
    <section className="rounded-2xl border border-border bg-card p-4">
      <h2 className="mb-3 text-sm font-semibold">Prepara spedizione</h2>

      <div className="space-y-5">
        {/* 1 — Che cosa è stato dichiarato sull'annuncio. */}
        <Blocco titolo={TITOLO_CONFEZIONE_DICHIARATA} icona={Package}>
          <p className="text-sm font-medium">
            {etichettaConfezioneDichiarata(tipoConfezione)}
          </p>
          {contestoMancante && (
            <p className="mt-1 text-xs text-muted-foreground">
              {NOTA_CONTESTO_NON_DISPONIBILE}
            </p>
          )}
          {ordine.imballaggio_etichetta && (
            <p className="mt-1 text-xs text-muted-foreground">
              {ordine.imballaggio_etichetta} — modalità dichiarata da te
              sull&apos;annuncio, congelata su questo ordine.
            </p>
          )}

          {fotoConfezione.length > 0 && (
            <div className="mt-3">
              <p className="text-xs font-medium">{TITOLO_FOTO_REFERENCE}</p>
              <p className="mt-0.5 text-xs text-muted-foreground">{NOTA_FOTO_REFERENCE}</p>
              <ul className="mt-2 grid grid-cols-2 gap-2 sm:grid-cols-4">
                {fotoConfezione.map((src, indice) => (
                  <li key={src}>
                    <Image
                      src={src}
                      width={400}
                      height={400}
                      sizes="(max-width: 639px) 45vw, 22vw"
                      alt={altFotoConfezione(tipoConfezione, indice)}
                      className="aspect-square w-full rounded-lg border border-border object-cover"
                    />
                  </li>
                ))}
              </ul>
            </div>
          )}
        </Blocco>

        {/* 2 — Come il venditore ha scelto di consegnare il pacco alla rete. */}
        <Blocco titolo={TITOLO_HANDOFF} icona={Truck}>
          <p className="text-sm font-medium">
            {etichettaHandoffScelto(logistica?.handoffVenditore ?? null)}
          </p>
          <p className="mt-1 text-xs text-muted-foreground">{NOTA_HANDOFF_OPERATIVA}</p>
        </Blocco>

        {/* 3 — La guida, numerata: l'ordine dei passi è parte dell'istruzione. */}
        <Blocco titolo="Come preparare il pacco" icona={PackageOpen}>
          <p className="text-sm font-medium">{guida.titolo}</p>
          <p className="mt-1 text-xs text-muted-foreground">{guida.introduzione}</p>
          <ol className="mt-3 grid gap-2 sm:grid-cols-2">
            {guida.passi.map((passo, indice) => (
              <li
                key={passo.id}
                className="flex items-start gap-3 rounded-xl border border-border bg-secondary/40 p-3"
              >
                {/* Il numero è già nella semantica di `<ol>`: qui è una
                    ripetizione visiva, e chi ascolta la sentirebbe due volte. */}
                <span
                  aria-hidden="true"
                  className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-bordeaux text-xs font-semibold text-white"
                >
                  {indice + 1}
                </span>
                <span className="min-w-0 flex-1">
                  <span className="block text-sm font-medium leading-snug">{passo.titolo}</span>
                  <span className="mt-0.5 block text-xs leading-snug text-muted-foreground">
                    {passo.descrizione}
                  </span>
                </span>
              </li>
            ))}
          </ol>
        </Blocco>

        {/* 4 — Il confine fra confezione originale e imballaggio di spedizione. */}
        <p className="flex items-start gap-2 rounded-xl border border-border bg-secondary/40 p-3 text-xs leading-snug text-muted-foreground">
          <Info className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
          <span>{DISCLAIMER_IMBALLAGGIO}</span>
        </p>

        {/* 5 — Le sei dichiarazioni che il database conta. */}
        <Blocco titolo="Checklist di sicurezza" icona={ClipboardCheck}>
          <div className="grid gap-2 sm:grid-cols-2">
            {voci.map((v) => (
              <label
                key={v.id}
                className="flex items-start gap-2 rounded-xl border border-border bg-secondary/40 p-2 text-sm"
              >
                <Checkbox
                  className="mt-0.5"
                  checked={!!spunte[v.id]}
                  onCheckedChange={(c) => setSpunte((s) => ({ ...s, [v.id]: !!c }))}
                />
                {/* L'ultima voce è lunga: qui si manda a capo, non si tronca —
                    una dichiarazione di sicurezza tagliata a metà non si firma. */}
                <span className="min-w-0 flex-1 leading-snug">{v.label}</span>
              </label>
            ))}
          </div>
        </Blocco>

        {/* 6 — Le prove: dominio separato da quello delle fotografie di sopra. */}
        <Blocco titolo="Prove fotografiche" icona={Camera}>
          <div className="grid gap-2 sm:grid-cols-2">
            {PROVE_SPEDIZIONE.map((definizione) => (
              <RiquadroProva
                key={definizione.kind}
                definizione={definizione}
                prova={perTipo.get(definizione.kind)}
                inCorso={inCorso}
                caricamento={caricamento === definizione.kind}
                onScegli={(file) => {
                  setCaricamento(definizione.kind);
                  void onRegistraProva(definizione.kind, file)
                    .then(setErrore)
                    .finally(() => setCaricamento(null));
                }}
              />
            ))}
          </div>
        </Blocco>

        {ordine.imballaggio_codice ? <BetaActionNotice tipo="spedizione" /> : null}

        <div className="grid gap-2 sm:grid-cols-2">
          <div>
            <Label className="text-xs uppercase">Corriere</Label>
            <Select value={corriere} onValueChange={setCorriere}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {CORRIERI.map((c) => (
                  <SelectItem key={c} value={c}>
                    {c}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div>
            <Label className="text-xs uppercase">Numero tracking</Label>
            <Input
              value={tracking}
              onChange={(e) => setTracking(e.target.value)}
              placeholder="Es. VNA-4421-773"
            />
          </div>
        </div>

        {confermataAt !== null ? (
          <p className="flex items-center gap-1 text-xs text-muted-foreground">
            <CheckCircle2 className="h-3.5 w-3.5 shrink-0 text-bordeaux" aria-hidden="true" />
            <span>
              Preparazione confermata il {new Date(confermataAt).toLocaleString("it-IT")}.
            </span>
          </p>
        ) : (
          <p className="flex items-center gap-1 text-xs text-muted-foreground">
            <ClipboardCheck className="h-3.5 w-3.5" aria-hidden="true" />{" "}
            {colloCaricato
              ? "Spunta tutte e sei le voci, poi conferma la preparazione."
              : "Carica la foto del collo finale e completa la checklist per confermare."}
          </p>
        )}
        {errore && <p className="text-xs text-red-700">{errore}</p>}

        {/*
          I due primi bottoni chiamano la stessa porta, e non è una
          duplicazione: `ordine_prepara_spedizione` confronta la checklist con
          le sei voci canoniche e con la prova corrente del collo finale, e solo
          allora valorizza `preparazione_confermata_at`. «Salva» serve a
          interrompere il lavoro a metà senza perderlo; «Conferma» dichiara che
          quella stessa chiamata chiuderà il cancello, e si accende solo quando
          lo farà davvero. Un bottone unico avrebbe nascosto la differenza fra
          un salvataggio parziale e una conferma.
        */}
        <div className="flex flex-wrap gap-2">
          <Button
            variant="outline"
            disabled={inCorso}
            onClick={async () => setErrore(await onPrepara(checklist()))}
          >
            Salva preparazione
          </Button>
          <Button
            variant="outline"
            disabled={inCorso || !confermabile}
            onClick={async () => setErrore(await onPrepara(checklist()))}
          >
            Conferma preparazione
          </Button>
          <Button
            className="bg-bordeaux hover:bg-bordeaux/90"
            disabled={inCorso || !trackingValido || !puoSpedire(ordine)}
            onClick={async () => setErrore(await onSpedisci(corriere, tracking))}
          >
            {inCorso ? "Elaborazione…" : "Segna come spedito"}
          </Button>
        </div>
      </div>
    </section>
  );
}
