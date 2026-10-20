"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import type { StatoInterruttoreAnnunci } from "@/lib/accessori-vendita/annunci-accessori";
import { getSupabaseClient } from "@/lib/supabase/client";
import { creaAnnunciAccessoriAdminService } from "@/services/annunci-accessori-service";

/**
 * Interruttore della preparazione degli annunci Accessori (VPM-015B2), nell'area
 * admin. Uno solo, nel database, spento di default. Accendere richiede il ruolo
 * di rilascio (decisione del titolare, registrata con motivo); spegnere basta
 * un admin. NON esiste un interruttore di pubblicazione: in questo blocco non
 * c'è alcun percorso di vendita da accendere.
 */

const PAROLA_DI_RILASCIO = "ATTIVA";

export function AnnunciAccessoriAdmin() {
  const client = useMemo(() => getSupabaseClient(), []);
  const servizio = useMemo(() => creaAnnunciAccessoriAdminService(client), [client]);
  const [stato, setStato] = useState<StatoInterruttoreAnnunci | null>(null);
  const [errore, setErrore] = useState<string | null>(null);
  const [esito, setEsito] = useState<string | null>(null);
  const [motivo, setMotivo] = useState("");
  const [conferma, setConferma] = useState("");
  const [invio, setInvio] = useState(false);

  const ricarica = useCallback(async () => {
    const r = await servizio.stato();
    if (r.ok) {
      setStato(r.data);
      setErrore(null);
    } else {
      setErrore(r.error);
    }
  }, [servizio]);

  useEffect(() => {
    void ricarica();
  }, [ricarica]);

  const applica = async (nuovo: boolean) => {
    setInvio(true);
    setErrore(null);
    const r = await servizio.imposta(nuovo, motivo.trim());
    setInvio(false);
    if (!r.ok) return setErrore(r.error);
    setMotivo("");
    setConferma("");
    setEsito(`Preparazione degli annunci: ${nuovo ? "accesa" : "spenta"}.`);
    await ricarica();
  };

  const motivoOk = motivo.trim().length > 0;

  return (
    <section
      aria-labelledby="annunci-acc-admin"
      data-testid="annunci-accessori-admin"
      className="space-y-3 rounded-xl border border-border bg-card p-4"
    >
      <h2 id="annunci-acc-admin" className="font-serif text-lg font-semibold text-antracite">
        Annunci Accessori (preparazione)
      </h2>
      <p className="text-sm text-antracite/75">
        Bozze e revisione degli annunci di accessori posseduti. Nessuna vendita: non esiste un annuncio
        acquistabile, né un interruttore di pubblicazione. Spenta di default; richiede anche la funzione Cantina
        Accessori.
      </p>
      {errore ? (
        <p role="alert" className="rounded-lg border border-bordeaux/40 bg-bordeaux/5 px-3 py-2 text-sm text-bordeaux">
          {errore}
        </p>
      ) : null}
      {esito ? (
        <p role="status" className="rounded-lg border border-salvia/40 bg-salvia/10 px-3 py-2 text-sm text-antracite">
          {esito}
        </p>
      ) : null}
      {stato ? (
        <div className="space-y-2" data-testid="annunci-acc-preparazione">
          <p className="text-sm">
            Preparazione degli annunci: <strong>{stato.preparazioneAttiva ? "ACCESA" : "SPENTA"}</strong>
            {stato.cantinaFunzioneAttiva ? "" : " (la funzione Cantina Accessori è spenta)"}
          </p>
          {stato.preparazioneAttiva ? (
            <>
              <Label htmlFor="annunci-acc-motivo">Motivo (spegnere non richiede l&apos;approvazione del titolare)</Label>
              <Input id="annunci-acc-motivo" value={motivo} maxLength={500} onChange={(e) => setMotivo(e.target.value)} />
              <Button type="button" variant="outline" disabled={invio || !motivoOk} onClick={() => void applica(false)}>
                Spegni
              </Button>
            </>
          ) : stato.puoRilasciare ? (
            <>
              <Label htmlFor="annunci-acc-motivo">Motivo e riferimento dell&apos;approvazione del titolare</Label>
              <Input id="annunci-acc-motivo" value={motivo} maxLength={500} onChange={(e) => setMotivo(e.target.value)} />
              <Label htmlFor="annunci-acc-conferma">
                Per confermare scrivi <strong>{PAROLA_DI_RILASCIO}</strong>
              </Label>
              <Input
                id="annunci-acc-conferma"
                value={conferma}
                autoComplete="off"
                onChange={(e) => setConferma(e.target.value)}
              />
              <Button
                type="button"
                disabled={invio || !motivoOk || conferma !== PAROLA_DI_RILASCIO}
                onClick={() => void applica(true)}
              >
                Accendi
              </Button>
            </>
          ) : (
            <p className="text-sm text-antracite/80">
              Accendere richiede l&apos;approvazione esplicita del titolare: il tuo account non ha il permesso di
              rilascio. Puoi comunque collaudare la preparazione, che per un admin è usabile anche da spenta.
            </p>
          )}
        </div>
      ) : null}
    </section>
  );
}
