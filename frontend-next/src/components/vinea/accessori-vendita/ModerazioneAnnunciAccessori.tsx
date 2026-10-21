"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { ETICHETTE_CONDIZIONE } from "@/lib/accessori/accessori";
import { ETICHETTE_STATO_ANNUNCIO, type StatoAnnuncioAccessorio } from "@/lib/accessori-vendita/annunci-accessori";
import {
  AZIONI_MODERAZIONE,
  DESCRIZIONE_AZIONE,
  ETICHETTE_AZIONE,
  ETICHETTE_FILTRO,
  FILTRI_ANNUNCI_ADMIN,
  azioniAmmesse,
  motivazioneValida,
  type AzioneModerazione,
  type DettaglioAnnuncioAdmin,
  type FiltroAnnunciAdmin,
  type RigaAnnuncioAdmin,
} from "@/lib/accessori-vendita/annunci-moderazione";
import { euro } from "@/lib/prezzi/classe";
import { getSupabaseClient } from "@/lib/supabase/client";
import { creaAnnunciAccessoriAdminService } from "@/services/annunci-accessori-service";

/**
 * Moderazione successiva degli annunci Accessori (VPM-015B3), area admin.
 *
 * Elenca gli annunci pubblicati o in moderazione (anche solo quelli con
 * segnalazioni aperte), mostra snapshot, segnalazioni e storico delle decisioni
 * e permette di oscurare, rimuovere, chiedere modifiche o ripristinare con una
 * motivazione obbligatoria (registrata nell'audit; il venditore è avvisato).
 * Mostra solo le azioni che il database ammette per lo stato. Le segnalazioni si
 * chiudono dalla coda di moderazione già esistente; qui si agisce sull'annuncio.
 */

const etichettaStato = (stato: string): string =>
  ETICHETTE_STATO_ANNUNCIO[stato as StatoAnnuncioAccessorio] ?? stato;

export function ModerazioneAnnunciAccessori() {
  const client = useMemo(() => getSupabaseClient(), []);
  const servizio = useMemo(() => creaAnnunciAccessoriAdminService(client), [client]);
  const [filtro, setFiltro] = useState<FiltroAnnunciAdmin>("tutti");
  const [righe, setRighe] = useState<RigaAnnuncioAdmin[] | null>(null);
  const [errore, setErrore] = useState<string | null>(null);
  const [aperto, setAperto] = useState<string | null>(null);

  const ricarica = useCallback(async () => {
    const r = await servizio.elencoModerazione(filtro);
    if (r.ok) {
      setRighe(r.data);
      setErrore(null);
    } else {
      setRighe([]);
      setErrore(r.error);
    }
  }, [servizio, filtro]);

  useEffect(() => {
    void ricarica();
  }, [ricarica]);

  return (
    <section
      aria-labelledby="mod-annunci-acc"
      data-testid="moderazione-annunci-accessori"
      className="space-y-3 rounded-xl border border-border bg-card p-4"
    >
      <h2 id="mod-annunci-acc" className="font-serif text-lg font-semibold text-antracite">
        Moderazione annunci Accessori
      </h2>
      <p className="text-sm text-antracite/75">
        Annunci pubblicati senza approvazione preventiva: qui si interviene dopo, da segnalazioni o controlli.
        Ogni provvedimento richiede una motivazione, resta nello storico e avvisa il venditore.
      </p>
      <div role="group" aria-label="Filtro annunci" className="flex flex-wrap gap-2">
        {FILTRI_ANNUNCI_ADMIN.map((f) => (
          <Button
            key={f}
            type="button"
            size="sm"
            variant={f === filtro ? "default" : "outline"}
            aria-pressed={f === filtro}
            onClick={() => setFiltro(f)}
          >
            {ETICHETTE_FILTRO[f]}
          </Button>
        ))}
      </div>
      {errore ? (
        <p role="alert" className="rounded-lg border border-bordeaux/40 bg-bordeaux/5 px-3 py-2 text-sm text-bordeaux">
          {errore}
        </p>
      ) : null}
      {righe === null ? (
        <p role="status" className="text-sm text-antracite/70">
          Carico gli annunci…
        </p>
      ) : righe.length === 0 ? (
        <p role="status" className="text-sm text-antracite/70" data-testid="moderazione-vuota">
          Nessun annuncio per questo filtro.
        </p>
      ) : (
        <ul className="divide-y divide-border rounded-lg border border-border">
          {righe.map((r) => (
            <li key={r.id} className="flex flex-wrap items-center justify-between gap-2 px-3 py-2 text-sm">
              <span className="min-w-0">
                <strong className="break-words">{r.nome}</strong>{" "}
                <span className="text-antracite/70">
                  di {r.venditore} · {r.quantita} pz a {euro(r.prezzoUnitarioCents)} · {etichettaStato(r.stato)}
                  {r.provvedimento ? ` (${r.provvedimento})` : ""}
                </span>
                {r.segnalazioniAperte > 0 ? (
                  <span className="ml-2 rounded-full bg-bordeaux/10 px-2 py-0.5 text-xs text-bordeaux">
                    {r.segnalazioniAperte} {r.segnalazioniAperte === 1 ? "segnalazione aperta" : "segnalazioni aperte"}
                  </span>
                ) : null}
              </span>
              <Button type="button" size="sm" variant="outline" onClick={() => setAperto(r.id)}>
                Apri
              </Button>
            </li>
          ))}
        </ul>
      )}
      {aperto ? (
        <DettaglioModerazione
          id={aperto}
          onChiudi={() => setAperto(null)}
          onCambiato={ricarica}
        />
      ) : null}
    </section>
  );
}

function DettaglioModerazione({
  id,
  onChiudi,
  onCambiato,
}: {
  id: string;
  onChiudi: () => void;
  onCambiato: () => Promise<void>;
}) {
  const client = useMemo(() => getSupabaseClient(), []);
  const servizio = useMemo(() => creaAnnunciAccessoriAdminService(client), [client]);
  const [dettaglio, setDettaglio] = useState<DettaglioAnnuncioAdmin | null>(null);
  const [foto, setFoto] = useState<Record<string, string>>({});
  const [errore, setErrore] = useState<string | null>(null);
  const [esito, setEsito] = useState<string | null>(null);
  const [azione, setAzione] = useState<AzioneModerazione | null>(null);
  const [motivazione, setMotivazione] = useState("");
  const [invio, setInvio] = useState(false);

  const carica = useCallback(async () => {
    const r = await servizio.dettaglioModerazione(id);
    if (!r.ok) return setErrore(r.error);
    if (!r.data) return setErrore("Annuncio non trovato.");
    setDettaglio(r.data);
    setErrore(null);
    const f = await servizio.urlFoto(r.data.foto);
    if (f.ok) setFoto(f.data);
  }, [servizio, id]);

  useEffect(() => {
    void carica();
  }, [carica]);

  const applica = async () => {
    if (!azione || !motivazioneValida(motivazione)) return;
    setInvio(true);
    const r = await servizio.modera(id, azione, motivazione.trim());
    setInvio(false);
    if (!r.ok) return setErrore(r.error);
    setEsito(`${ETICHETTE_AZIONE[azione]}: registrato. Il venditore è stato avvisato.`);
    setAzione(null);
    setMotivazione("");
    setErrore(null);
    await carica();
    await onCambiato();
  };

  const ammesse = dettaglio ? azioniAmmesse(dettaglio.stato, dettaglio.provvedimento) : [];

  return (
    <Dialog open onOpenChange={(a) => (a ? null : onChiudi())}>
      <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-2xl" data-testid="moderazione-dettaglio">
        <DialogHeader>
          <DialogTitle>{dettaglio ? dettaglio.nome : "Annuncio"}</DialogTitle>
          <DialogDescription>
            {dettaglio
              ? `Di ${dettaglio.venditore} (${dettaglio.venditoreStato}) · ${etichettaStato(dettaglio.stato)}${
                  dettaglio.visibile ? " · visibile al pubblico" : " · non visibile"
                }`
              : "Carico…"}
          </DialogDescription>
        </DialogHeader>

        {errore ? (
          <p role="alert" className="rounded-lg border border-bordeaux/40 bg-bordeaux/5 px-3 py-2 text-sm text-bordeaux">
            {errore}
          </p>
        ) : null}
        {esito ? (
          <p role="status" className="rounded-lg border border-salvia/40 bg-salvia/10 px-3 py-2 text-sm">
            {esito}
          </p>
        ) : null}

        {dettaglio ? (
          <div className="space-y-4 text-sm">
            {dettaglio.foto.length > 0 ? (
              <ul className="grid grid-cols-2 gap-2 sm:grid-cols-4" aria-label="Fotografie dell'annuncio">
                {dettaglio.foto.map((p) => (
                  <li key={p} className="aspect-[4/5] overflow-hidden rounded-lg border border-border bg-secondary/40">
                    {foto[p] ? (
                      /* eslint-disable-next-line @next/next/no-img-element -- URL firmata a tempo. */
                      <img src={foto[p]} alt={`${dettaglio.nome}`} className="h-full w-full object-contain" />
                    ) : null}
                  </li>
                ))}
              </ul>
            ) : null}
            <dl className="grid gap-x-4 gap-y-1 sm:grid-cols-2">
              <dt className="text-antracite/60">Categoria</dt>
              <dd>{dettaglio.categoria}</dd>
              <dt className="text-antracite/60">Condizione</dt>
              <dd>{ETICHETTE_CONDIZIONE[dettaglio.condizione]}</dd>
              <dt className="text-antracite/60">Offerta</dt>
              <dd>
                {dettaglio.quantita} pz a {euro(dettaglio.prezzoUnitarioCents)} (richiesto dal venditore)
              </dd>
              <dt className="text-antracite/60">Versione</dt>
              <dd>{dettaglio.versione}</dd>
            </dl>
            {dettaglio.descrizione ? <p className="whitespace-pre-line">{dettaglio.descrizione}</p> : null}
            {dettaglio.statoMotivo ? (
              <p className="rounded-lg border border-border px-3 py-2">
                <strong>Ultimo provvedimento:</strong> {dettaglio.statoMotivo}
              </p>
            ) : null}

            <div>
              <h3 className="font-semibold">Segnalazioni ({dettaglio.segnalazioni.length})</h3>
              {dettaglio.segnalazioni.length === 0 ? (
                <p className="text-antracite/70">Nessuna segnalazione.</p>
              ) : (
                <ul className="mt-1 space-y-1">
                  {dettaglio.segnalazioni.map((s) => (
                    <li key={s.id} className="rounded-lg border border-border px-3 py-2">
                      <span className="font-medium">{s.codice}</span> · {s.motivo} · {s.stato} · priorità {s.priorita}
                      {s.descrizione ? <span className="block text-antracite/75">{s.descrizione}</span> : null}
                    </li>
                  ))}
                </ul>
              )}
              <p className="mt-1 text-xs text-antracite/60">
                La pratica di una segnalazione si chiude dalla coda di moderazione.
              </p>
            </div>

            <div>
              <h3 className="font-semibold">Storico delle decisioni</h3>
              {dettaglio.storico.length === 0 ? (
                <p className="text-antracite/70">Nessuna decisione registrata.</p>
              ) : (
                <ul className="mt-1 space-y-1">
                  {dettaglio.storico.map((d) => (
                    <li key={`${d.ts}-${d.azione}`} className="rounded-lg border border-border px-3 py-2">
                      <span className="font-medium">{d.azione}</span> · {d.attore} ·{" "}
                      {new Date(d.ts).toLocaleString("it-IT")}
                      <span className="block text-antracite/75">{d.motivazione}</span>
                    </li>
                  ))}
                </ul>
              )}
            </div>

            {ammesse.length > 0 ? (
              <div className="space-y-2" data-testid="moderazione-azioni">
                <h3 className="font-semibold">Provvedimento</h3>
                <div role="group" aria-label="Azione" className="flex flex-wrap gap-2">
                  {AZIONI_MODERAZIONE.filter((a) => ammesse.includes(a)).map((a) => (
                    <Button
                      key={a}
                      type="button"
                      size="sm"
                      variant={a === azione ? "default" : "outline"}
                      aria-pressed={a === azione}
                      onClick={() => setAzione(a)}
                    >
                      {ETICHETTE_AZIONE[a]}
                    </Button>
                  ))}
                </div>
                {azione ? (
                  <>
                    <p className="text-xs text-antracite/70">{DESCRIZIONE_AZIONE[azione]}</p>
                    <Label htmlFor="mod-motivazione">Motivazione (obbligatoria, visibile al venditore)</Label>
                    <Textarea
                      id="mod-motivazione"
                      rows={3}
                      maxLength={1000}
                      value={motivazione}
                      onChange={(e) => setMotivazione(e.target.value)}
                    />
                  </>
                ) : null}
              </div>
            ) : (
              <p className="text-antracite/70">Nessun provvedimento disponibile per questo stato.</p>
            )}
          </div>
        ) : null}

        <DialogFooter>
          <Button type="button" variant="ghost" onClick={onChiudi}>
            Chiudi
          </Button>
          {azione ? (
            <Button type="button" disabled={invio || !motivazioneValida(motivazione)} onClick={() => void applica()}>
              {invio ? <Loader2 className="animate-spin" aria-hidden /> : null} Conferma: {ETICHETTE_AZIONE[azione]}
            </Button>
          ) : null}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
