"use client";

import { useRef, useState } from "react";
import { Camera, CheckCircle2, ClipboardCheck, Package } from "lucide-react";
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
import { puoSpedire } from "@/lib/orders/seller-status";
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
  inCorso: boolean;
  onPrepara: (checklist: VoceChecklist[]) => Promise<string | null>;
  onRegistraProva: (kind: ShippingEvidenceKind, file: File) => Promise<string | null>;
  onSpedisci: (corriere: string, tracking: string) => Promise<string | null>;
};

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
            <Camera className="h-5 w-5 text-muted-foreground" />
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
 */
export function SellerPrepPanel({
  ordine,
  prove,
  inCorso,
  onPrepara,
  onRegistraProva,
  onSpedisci,
}: Props) {
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

  const checklist = (): VoceChecklist[] =>
    VOCI_IMBALLAGGIO.map((v) => ({ id: v.id, label: v.label, done: !!spunte[v.id] }));

  const confermabile = preparazioneConfermabile(
    checklist(),
    prove.map((p) => p.evidence_kind),
  );

  return (
    <section className="rounded-2xl border border-border bg-card p-4">
      <p className="mb-3 text-sm font-semibold">Prepara spedizione</p>

      <div className="space-y-4">
        {ordine.imballaggio_etichetta && (
          <div className="flex items-start gap-2 rounded-xl border border-border bg-secondary/40 p-2 text-sm">
            <Package className="mt-0.5 h-4 w-4 shrink-0 text-bordeaux" />
            <span>
              <span className="block font-medium">{ordine.imballaggio_etichetta}</span>
              <span className="block text-xs text-muted-foreground">
                Modalità dichiarata da te sull&apos;annuncio, congelata su questo ordine.
              </span>
            </span>
          </div>
        )}

        <div>
          <Label className="text-xs uppercase">Prove fotografiche</Label>
          <div className="mt-2 grid gap-2 sm:grid-cols-2">
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
        </div>

        <div>
          <Label className="text-xs uppercase">Checklist di imballaggio</Label>
          <div className="mt-2 grid gap-2 sm:grid-cols-2">
            {VOCI_IMBALLAGGIO.map((v) => (
              <label
                key={v.id}
                className="flex items-start gap-2 rounded-xl border border-border bg-secondary/40 p-2 text-sm"
              >
                <Checkbox
                  className="mt-0.5"
                  checked={!!spunte[v.id]}
                  onCheckedChange={(c) => setSpunte((s) => ({ ...s, [v.id]: !!c }))}
                />
                <ClipboardCheck className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />
                {/* L'ultima voce è lunga: qui si manda a capo, non si tronca —
                    una dichiarazione di sicurezza tagliata a metà non si firma. */}
                <span className="min-w-0 flex-1 leading-snug">{v.label}</span>
              </label>
            ))}
          </div>
        </div>

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
            <CheckCircle2 className="h-3.5 w-3.5 text-bordeaux" /> Preparazione confermata il{" "}
            {new Date(confermataAt).toLocaleString("it-IT")}.
          </p>
        ) : (
          <p className="flex items-center gap-1 text-xs text-muted-foreground">
            <ClipboardCheck className="h-3.5 w-3.5" />{" "}
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
