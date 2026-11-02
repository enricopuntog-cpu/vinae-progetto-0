"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { DisputePanel } from "@/components/vinea/orders/DisputePanel";
import {
  MOTIVI_CONTESTAZIONE_ACCESSORI,
  contestazioneComeFascicolo,
  type PostVenditaAccessorio,
} from "@/lib/accessori-postvendita/postvendita";
import { MIME_PROVA_INGRESSO, preparaProvaImmagine } from "@/lib/orders/prepara-prova-contestazione";
import { euro } from "@/lib/prezzi/classe";
import { getSupabaseClient } from "@/lib/supabase/client";
import { creaAccessoriPostvenditaService } from "@/services/accessori-postvendita-service";
import type { DisputeSellerResponseKind } from "@/services/types";

const ora = (iso: string) =>
  new Intl.DateTimeFormat("it-IT", { dateStyle: "short", timeStyle: "short", timeZone: "Europe/Rome" }).format(
    new Date(iso),
  );

const TESTO_RICAVO = {
  trattenuto: "Trattenuto da Vinea fino a consegna, finestra di 48 ore e assenza di contestazioni",
  rilasciato: "Rilasciato nel tuo saldo Vinea",
  stornato: "Stornato per rimborso",
} as const;

/** Post-vendita di un ordine Accessori: consegna, contestazione e rimborsi. Riusa `DisputePanel` del vino. */
export function PostVenditaAccessorioPannello({
  postvendita,
  foto,
  ruolo,
}: {
  postvendita: PostVenditaAccessorio;
  foto: { acquirente: string[]; venditore: string[] };
  ruolo: "acquirente" | "venditore";
}) {
  const router = useRouter();
  const [inCorso, setInCorso] = useState(false);
  const [errore, setErrore] = useState<string | null>(null);
  const [motivo, setMotivo] = useState<string>(MOTIVI_CONTESTAZIONE_ACCESSORI[0]);
  const [descrizione, setDescrizione] = useState("");
  const [files, setFiles] = useState<File[]>([]);
  if (!postvendita.incassato) return null;

  const servizio = () => creaAccessoriPostvenditaService(getSupabaseClient());
  const preparate = async (daPreparare: File[]) => Promise.all(daPreparare.map((f) => preparaProvaImmagine(f)));

  const apri = async () => {
    setInCorso(true);
    setErrore(null);
    try {
      const esito = await servizio().apriContestazione({
        ordineId: postvendita.ordineId,
        motivo,
        descrizione,
        foto: await preparate(files),
      });
      if (!esito.ok) setErrore(esito.error);
      else router.refresh();
    } catch (e) {
      setErrore(e instanceof Error ? e.message : "Operazione non riuscita.");
    } finally {
      setInCorso(false);
    }
  };

  const rispondi = async (tipo: DisputeSellerResponseKind, risposta: string, daCaricare: File[]) => {
    setInCorso(true);
    try {
      const esito = await servizio().rispondi({
        ordineId: postvendita.ordineId,
        tipo,
        risposta,
        foto: await preparate(daCaricare),
      });
      if (!esito.ok) return esito.error;
      router.refresh();
      return null;
    } catch (e) {
      return e instanceof Error ? e.message : "Operazione non riuscita.";
    } finally {
      setInCorso(false);
    }
  };

  const fascicolo = contestazioneComeFascicolo(postvendita, foto);
  const { consegna, rimborso, ricavo } = postvendita;

  return (
    <section data-testid="postvendita-accessorio" className="mt-6 space-y-4 text-sm">
      <h2 className="font-display text-lg">Dopo la vendita</h2>

      <p data-testid="postvendita-consegna">
        {consegna
          ? `Consegna registrata il ${ora(consegna.registrataAt)}${
              consegna.provaVettore ? " (conferma del vettore)" : " (registrata dal supporto Vinea, senza conferma del vettore)"
            }.`
          : "La consegna non è ancora registrata."}
        {postvendita.finestraContestazioneScadeAt
          ? ` Puoi contestare entro ${ora(postvendita.finestraContestazioneScadeAt)}.`
          : ""}
      </p>

      {rimborso && (rimborso.rimborsatoCents > 0 || rimborso.inCorsoCents > 0) ? (
        <p data-testid="postvendita-rimborso">
          Rimborsato: {euro(rimborso.rimborsatoCents)}
          {rimborso.inCorsoCents > 0 ? ` · in elaborazione: ${euro(rimborso.inCorsoCents)}` : ""}
        </p>
      ) : null}

      {ruolo === "venditore" && ricavo ? (
        <p data-testid="postvendita-ricavo">
          {TESTO_RICAVO[ricavo.stato]}: {euro(ricavo.importoCents - ricavo.stornatoCents)}
          {ricavo.stornatoCents > 0 ? ` (rimborsati ${euro(ricavo.stornatoCents)})` : ""}.
        </p>
      ) : null}

      {fascicolo ? (
        <DisputePanel
          contestazione={fascicolo}
          eventi={[]}
          ruolo={ruolo === "acquirente" ? "compratore" : "venditore"}
          inCorso={inCorso}
          onRispondi={rispondi}
        />
      ) : null}

      {ruolo === "acquirente" && postvendita.puoContestare ? (
        <div className="space-y-3 rounded-2xl border p-4" data-testid="postvendita-apri">
          <p className="font-semibold">C&apos;è un problema con l&apos;ordine?</p>
          <label className="block">
            <span className="mb-1 block text-xs font-medium">Motivo</span>
            <select
              value={motivo}
              onChange={(e) => setMotivo(e.target.value)}
              className="w-full rounded-md border border-input bg-background px-3 py-2"
            >
              {MOTIVI_CONTESTAZIONE_ACCESSORI.map((m) => (
                <option key={m} value={m}>{m}</option>
              ))}
            </select>
          </label>
          <div>
            <Label htmlFor="postvendita-descrizione">Descrivi il problema</Label>
            <Textarea
              id="postvendita-descrizione"
              rows={4}
              maxLength={2000}
              value={descrizione}
              onChange={(e) => setDescrizione(e.target.value)}
            />
          </div>
          <div>
            <Label htmlFor="postvendita-foto">Fotografie (fino a 8)</Label>
            <input
              id="postvendita-foto"
              type="file"
              multiple
              accept={MIME_PROVA_INGRESSO.join(",")}
              onChange={(e) => setFiles(Array.from(e.target.files ?? []).slice(0, 8))}
              className="mt-1 block w-full text-xs"
            />
          </div>
          {errore ? <p role="alert" className="text-xs text-red-700">{errore}</p> : null}
          <Button disabled={inCorso || descrizione.trim().length < 3} onClick={apri} className="bg-bordeaux hover:bg-bordeaux/90">
            {inCorso ? "Invio…" : "Apri la contestazione"}
          </Button>
        </div>
      ) : null}
    </section>
  );
}
