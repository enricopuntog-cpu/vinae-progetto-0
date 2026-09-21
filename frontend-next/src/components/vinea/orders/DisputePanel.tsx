"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { MIME_PROVA_INGRESSO } from "@/lib/orders/prepara-prova-contestazione";
import type {
  DisputeEventRecord,
  DisputeRecord,
  DisputeSellerResponseKind,
  DisputeStato,
} from "@/services/types";

const ETICHETTE: Record<DisputeStato, string> = {
  aperta: "Aperta",
  in_valutazione: "In valutazione",
  rimborsata: "Rimborsata",
  risolta: "Risolta",
  respinta: "Respinta",
};

const RISPOSTE: Array<{ value: DisputeSellerResponseKind; label: string }> = [
  { value: "accetta", label: "Accetto il problema" },
  { value: "contesta", label: "Contesto la segnalazione" },
  { value: "propone_soluzione", label: "Propongo una soluzione" },
];

const EVENTI: Record<DisputeEventRecord["event_kind"], string> = {
  aperta: "Contestazione aperta",
  risposta_venditore: "Risposta del venditore ricevuta",
  presa_in_carico: "Documentazione presa in carico",
  risolta: "Contestazione chiusa",
};

function EvidenceGallery({ title, urls }: { title: string; urls: string[] }) {
  if (urls.length === 0) return null;
  return (
    <div className="mt-3">
      <p className="text-xs font-medium">{title}</p>
      <div className="mt-2 grid grid-cols-2 gap-2 sm:grid-cols-4">
        {urls.map((url, index) => (
          // eslint-disable-next-line @next/next/no-img-element -- URL firmato e temporaneo.
          <img
            key={url}
            src={url}
            alt={`${title} ${index + 1}`}
            className="aspect-square rounded-lg border object-cover"
          />
        ))}
      </div>
    </div>
  );
}

export function DisputePanel({
  contestazione,
  eventi,
  ruolo,
  inCorso,
  onRispondi,
}: {
  contestazione: DisputeRecord;
  eventi: DisputeEventRecord[];
  ruolo: "compratore" | "venditore";
  inCorso: boolean;
  onRispondi: (
    tipo: DisputeSellerResponseKind,
    risposta: string,
    foto: File[],
  ) => Promise<string | null>;
}) {
  const [tipo, setTipo] = useState<DisputeSellerResponseKind>("contesta");
  const [risposta, setRisposta] = useState("");
  const [foto, setFoto] = useState<File[]>([]);
  const [errore, setErrore] = useState<string | null>(null);
  const chiusa = contestazione.chiusura_at !== null;
  const scaduta = Date.now() > Date.parse(contestazione.venditore_scadenza_at);
  const puoRispondere =
    ruolo === "venditore"
    && !chiusa
    && !scaduta
    && contestazione.venditore_risposta_at === null;

  return (
    <section className="rounded-2xl border border-red-500/30 bg-red-500/5 p-4">
      <div className="flex items-center justify-between gap-2">
        <p className="text-sm font-semibold text-red-700">
          Contestazione · {ETICHETTE[contestazione.stato]}
        </p>
        <span className="rounded-full bg-red-500/10 px-2 py-0.5 text-[10px] font-medium text-red-700">
          {new Date(contestazione.apertura_at).toLocaleDateString("it-IT")}
        </span>
      </div>

      <p className="mt-2 text-sm"><b>Motivo:</b> {contestazione.motivo}</p>
      <p className="mt-1 text-sm text-antracite/80">{contestazione.descrizione}</p>
      <EvidenceGallery title="Prove dell'acquirente" urls={contestazione.foto} />

      {contestazione.venditore_risposta ? (
        <div className="mt-4 rounded-xl border bg-card p-3">
          <p className="text-xs font-semibold uppercase tracking-wide">Risposta del venditore</p>
          <p className="mt-1 text-sm">{contestazione.venditore_risposta}</p>
          <EvidenceGallery title="Prove del venditore" urls={contestazione.venditore_foto} />
        </div>
      ) : null}

      {puoRispondere ? (
        <div className="mt-4 space-y-3 border-t border-red-500/20 pt-3">
          <p className="text-sm font-semibold">Rispondi entro 48 ore dall'apertura</p>
          <label className="block text-sm">
            <span className="mb-1 block text-xs font-medium">Posizione</span>
            <select
              value={tipo}
              onChange={(event) => setTipo(event.target.value as DisputeSellerResponseKind)}
              className="w-full rounded-md border border-input bg-background px-3 py-2"
            >
              {RISPOSTE.map((item) => (
                <option key={item.value} value={item.value}>{item.label}</option>
              ))}
            </select>
          </label>
          <div>
            <Label htmlFor="contestazione-risposta">Spiegazione o soluzione proposta</Label>
            <Textarea
              id="contestazione-risposta"
              rows={4}
              maxLength={2000}
              value={risposta}
              onChange={(event) => setRisposta(event.target.value)}
            />
          </div>
          <div>
            <Label htmlFor="contestazione-risposta-foto">Fotografie</Label>
            <input
              id="contestazione-risposta-foto"
              type="file"
              multiple
              accept={MIME_PROVA_INGRESSO.join(",")}
              onChange={(event) => setFoto(Array.from(event.target.files ?? []).slice(0, 8))}
              className="mt-1 block w-full text-xs"
            />
          </div>
          {errore ? <p role="alert" className="text-xs text-red-700">{errore}</p> : null}
          <Button
            disabled={inCorso || risposta.trim().length < 3}
            onClick={async () => setErrore(await onRispondi(tipo, risposta, foto))}
            className="bg-bordeaux hover:bg-bordeaux/90"
          >
            {inCorso ? "Invio…" : "Invia risposta"}
          </Button>
        </div>
      ) : ruolo === "venditore" && !contestazione.venditore_risposta && !chiusa ? (
        <p className="mt-3 text-xs text-muted-foreground">
          La finestra di 48 ore per la risposta del venditore è terminata.
        </p>
      ) : null}

      {eventi.length > 0 ? (
        <ol className="mt-4 space-y-1 border-t border-red-500/20 pt-3 text-xs">
          {eventi.map((event) => (
            <li key={event.id}>
              <b>{EVENTI[event.event_kind]}</b>
              {" · "}
              {new Date(event.created_at).toLocaleString("it-IT")}
            </li>
          ))}
        </ol>
      ) : null}

      {contestazione.esito_nota ? (
        <p className="mt-3 text-xs text-muted-foreground">Esito: {contestazione.esito_nota}</p>
      ) : null}

      <p className="mt-4 border-t border-red-500/20 pt-3 text-xs text-muted-foreground">
        {contestazione.stato === "rimborsata"
          ? "Rimborso disposto. I fondi restano bloccati finché il fornitore non lo conferma."
          : chiusa
            ? "Pratica chiusa."
            : "I fondi restano bloccati. Vinea mira normalmente a esaminare la contestazione entro 3 giorni lavorativi dalla ricezione della documentazione completa."}
      </p>
    </section>
  );
}
