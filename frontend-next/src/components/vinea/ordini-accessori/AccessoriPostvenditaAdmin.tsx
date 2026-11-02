"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import type { ElencoPostVenditaAdmin } from "@/lib/accessori-postvendita/postvendita";
import { euro } from "@/lib/prezzi/classe";
import { getSupabaseClient } from "@/lib/supabase/client";
import { creaAccessoriPostvenditaService } from "@/services/accessori-postvendita-service";

const ora = (iso: string) =>
  new Intl.DateTimeFormat("it-IT", { dateStyle: "short", timeStyle: "short", timeZone: "Europe/Rome" }).format(
    new Date(iso),
  );

const ORIGINE = { dovuto_automatico: "Incasso non applicabile", contestazione: "Decisione su contestazione" } as const;

/**
 * Coda di lavoro del post-vendita Accessori per l'admin: contestazioni da
 * decidere, rimborsi non conclusi (compreso ogni `refund_due`), consegna
 * manuale e reso rientrato. Ogni porta ricontrolla il ruolo nel database.
 */
export function AccessoriPostvenditaAdmin({ iniziale }: { iniziale: ElencoPostVenditaAdmin }) {
  const [elenco, setElenco] = useState(iniziale);
  const [messaggio, setMessaggio] = useState<string | null>(null);
  const [ordine, setOrdine] = useState("");
  const [quantita, setQuantita] = useState("1");
  const [nota, setNota] = useState("");
  const [importo, setImporto] = useState("");
  const servizio = () => creaAccessoriPostvenditaService(getSupabaseClient());

  const ricarica = async () => {
    const esito = await servizio().adminElenco();
    if (esito.ok) setElenco(esito.data);
  };
  const esegui = async (azione: () => Promise<{ ok: boolean; error?: string }>) => {
    setMessaggio(null);
    const esito = await azione();
    setMessaggio(esito.ok ? "Operazione registrata." : (esito.error ?? "Operazione non riuscita."));
    if (esito.ok) await ricarica();
  };
  const centesimi = () => Math.round(Number(importo.replace(",", ".")) * 100);

  return (
    <div className="space-y-8 text-sm" data-testid="postvendita-admin">
      <section>
        <h2 className="font-display text-lg">Contestazioni aperte</h2>
        {elenco.contestazioni.length === 0 ? <p className="mt-2 text-muted-foreground">Nessuna.</p> : null}
        <ul className="mt-2 space-y-2">
          {elenco.contestazioni.map((c) => (
            <li key={c.ordineId} className="rounded-xl border p-3">
              <p className="font-medium">{c.motivo} · ordine {c.ordineId}</p>
              <p className="text-xs text-muted-foreground">
                Aperta {ora(c.apertaAt)} · risposta del venditore entro {ora(c.venditoreScadenzaAt)}
                {c.rispostaAt ? ` · risposto ${ora(c.rispostaAt)}` : ""}
                {c.pronta ? " · pronta per la decisione" : " · in attesa del venditore"}
              </p>
              <Button size="sm" variant="outline" className="mt-2" onClick={() => setOrdine(c.ordineId)}>
                Seleziona
              </Button>
            </li>
          ))}
        </ul>
      </section>

      <section>
        <h2 className="font-display text-lg">Rimborsi non conclusi</h2>
        {elenco.rimborsi.length === 0 ? <p className="mt-2 text-muted-foreground">Nessuno.</p> : null}
        <ul className="mt-2 space-y-2">
          {elenco.rimborsi.map((r) => (
            <li key={r.rimborsoId} className="rounded-xl border p-3">
              <p className="font-medium">
                {ORIGINE[r.origine]} · {euro(r.importoCents)} · {r.stato.replaceAll("_", " ")}
              </p>
              <p className="text-xs text-muted-foreground">
                Ordine {r.ordineId} · richiesto {ora(r.richiestoAt)} · tentativi {r.tentativi}
                {r.ultimoErrore ? ` · ultimo errore: ${r.ultimoErrore}` : ""}
              </p>
            </li>
          ))}
        </ul>
      </section>

      <section className="space-y-3 rounded-2xl border p-4">
        <h2 className="font-display text-lg">Operazioni sull&apos;ordine</h2>
        <label className="block">
          <span className="mb-1 block text-xs font-medium">Identificativo dell&apos;ordine</span>
          <input
            value={ordine}
            onChange={(e) => setOrdine(e.target.value.trim())}
            className="w-full rounded-md border border-input bg-background px-3 py-2"
          />
        </label>
        <label className="block">
          <span className="mb-1 block text-xs font-medium">Nota o riferimento</span>
          <input
            value={nota}
            onChange={(e) => setNota(e.target.value)}
            maxLength={1000}
            className="w-full rounded-md border border-input bg-background px-3 py-2"
          />
        </label>
        <label className="block">
          <span className="mb-1 block text-xs font-medium">Importo da rimborsare (euro, solo per «rimborsata»)</span>
          <input
            value={importo}
            onChange={(e) => setImporto(e.target.value)}
            inputMode="decimal"
            className="w-full rounded-md border border-input bg-background px-3 py-2"
          />
        </label>
        <div className="flex flex-wrap gap-2">
          {(["rimborsata", "risolta", "respinta"] as const).map((esito) => (
            <Button
              key={esito}
              size="sm"
              variant="outline"
              onClick={() =>
                esegui(() =>
                  servizio().adminDecidi({
                    ordineId: ordine,
                    esito,
                    importoCents: esito === "rimborsata" ? centesimi() : null,
                    nota,
                  }),
                )
              }
            >
              Decidi: {esito}
            </Button>
          ))}
          <Button
            size="sm"
            variant="outline"
            onClick={() => esegui(() => servizio().adminConsegna({ ordineId: ordine, riferimento: nota }))}
          >
            Registra consegna (manuale)
          </Button>
        </div>
        <div className="flex items-end gap-2">
          <label className="block">
            <span className="mb-1 block text-xs font-medium">Pezzi rientrati e riutilizzabili</span>
            <input
              value={quantita}
              onChange={(e) => setQuantita(e.target.value)}
              inputMode="numeric"
              className="w-24 rounded-md border border-input bg-background px-3 py-2"
            />
          </label>
          <Button
            size="sm"
            variant="outline"
            onClick={() => esegui(() => servizio().adminReso({ ordineId: ordine, quantita: Number(quantita), nota }))}
          >
            Registra reso rientrato
          </Button>
        </div>
        {messaggio ? <p role="status" className="text-xs">{messaggio}</p> : null}
      </section>
    </div>
  );
}
