"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import type { StatoInterruttoriCantina } from "@/lib/cantina-accessori/cantina-accessori";
import { getSupabaseClient } from "@/lib/supabase/client";
import { creaCantinaAccessoriAdminService } from "@/services/cantina-accessori-service";

/**
 * Interruttori della Cantina Accessori personale (VPM-015B1), nell'area admin.
 *
 * Due interruttori nel database, distinti fra loro e dal catalogo centrale:
 * la FUNZIONE (la sezione «Accessori» nella Cantina degli utenti) e la
 * VISIBILITÀ degli accessori che i proprietari hanno scelto di esporre. Sono
 * spenti di default. Accendere richiede il ruolo di rilascio (decisione del
 * titolare, registrata con motivo); spegnere basta un admin. Un admin reale
 * può comunque collaudare la funzione e l'anteprima pubblica anche da spenta.
 */

const PAROLA_DI_RILASCIO = "ATTIVA";

type Interruttore = "funzione" | "visibilita_pubblica";

const VOCI: Readonly<Record<Interruttore, { titolo: string; acceso: string; spento: string; effetto: string }>> = {
  funzione: {
    titolo: "Funzione Cantina Accessori",
    acceso: "ACCESA",
    spento: "SPENTA",
    effetto:
      "Accesa, gli utenti vedono la sezione «Accessori» nella propria Cantina e possono aggiungere i loro accessori (privati di default).",
  },
  visibilita_pubblica: {
    titolo: "Visibilità degli accessori esposti",
    acceso: "ACCESA",
    spento: "SPENTA",
    effetto:
      "Accesa (e a funzione accesa), profilo e Cantina pubblica mostrano gli accessori che i proprietari hanno scelto di esporre. Mai le note private. Non sono in vendita.",
  },
};

export function CantinaAccessoriAdmin() {
  const client = useMemo(() => getSupabaseClient(), []);
  const servizio = useMemo(() => creaCantinaAccessoriAdminService(client), [client]);
  const [stato, setStato] = useState<StatoInterruttoriCantina | null>(null);
  const [errore, setErrore] = useState<string | null>(null);
  const [esito, setEsito] = useState<string | null>(null);

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

  return (
    <section
      aria-labelledby="cantina-acc-admin"
      data-testid="cantina-accessori-admin"
      className="space-y-4 rounded-xl border border-border bg-card p-4"
    >
      <h2 id="cantina-acc-admin" className="font-serif text-lg font-semibold text-antracite">
        Cantina Accessori personale
      </h2>
      <p className="text-sm text-antracite/75">
        Gli accessori che gli utenti possiedono, nella loro Cantina. Due interruttori nel database, spenti di
        default e indipendenti dal catalogo qui sopra.
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
        <div className="space-y-4">
          <Riga
            interruttore="funzione"
            attivo={stato.funzioneAttiva}
            puoRilasciare={stato.puoRilasciare}
            servizio={servizio}
            onFatto={async (testo) => {
              setEsito(testo);
              await ricarica();
            }}
            onErrore={setErrore}
          />
          <Riga
            interruttore="visibilita_pubblica"
            attivo={stato.visibilitaPubblica}
            puoRilasciare={stato.puoRilasciare}
            servizio={servizio}
            onFatto={async (testo) => {
              setEsito(testo);
              await ricarica();
            }}
            onErrore={setErrore}
          />
        </div>
      ) : null}
    </section>
  );
}

function Riga({
  interruttore,
  attivo,
  puoRilasciare,
  servizio,
  onFatto,
  onErrore,
}: {
  interruttore: Interruttore;
  attivo: boolean;
  puoRilasciare: boolean;
  servizio: ReturnType<typeof creaCantinaAccessoriAdminService>;
  onFatto: (testo: string) => Promise<void>;
  onErrore: (testo: string | null) => void;
}) {
  const voce = VOCI[interruttore];
  const [motivo, setMotivo] = useState("");
  const [conferma, setConferma] = useState("");
  const [invio, setInvio] = useState(false);
  const idMotivo = `cantina-acc-motivo-${interruttore}`;
  const idConferma = `cantina-acc-conferma-${interruttore}`;

  const applica = async (nuovo: boolean) => {
    setInvio(true);
    onErrore(null);
    const r = await servizio.imposta(interruttore, nuovo, motivo.trim());
    setInvio(false);
    if (!r.ok) return onErrore(r.error);
    setMotivo("");
    setConferma("");
    await onFatto(`${voce.titolo}: ${nuovo ? "accesa" : "spenta"}.`);
  };

  const motivoOk = motivo.trim().length > 0;

  return (
    <div className="space-y-2 border-t border-border pt-3 first:border-t-0 first:pt-0" data-testid={`cantina-acc-${interruttore}`}>
      <p className="text-sm">
        {voce.titolo}: <strong>{attivo ? voce.acceso : voce.spento}</strong>
      </p>
      <p className="text-xs text-antracite/70">{voce.effetto}</p>
      {attivo ? (
        <>
          <Label htmlFor={idMotivo}>Motivo (spegnere non richiede l&apos;approvazione del titolare)</Label>
          <Input id={idMotivo} value={motivo} maxLength={500} onChange={(e) => setMotivo(e.target.value)} />
          <Button type="button" variant="outline" disabled={invio || !motivoOk} onClick={() => void applica(false)}>
            Spegni
          </Button>
        </>
      ) : puoRilasciare ? (
        <>
          <Label htmlFor={idMotivo}>Motivo e riferimento dell&apos;approvazione del titolare</Label>
          <Input id={idMotivo} value={motivo} maxLength={500} onChange={(e) => setMotivo(e.target.value)} />
          <Label htmlFor={idConferma}>
            Per confermare scrivi <strong>{PAROLA_DI_RILASCIO}</strong>
          </Label>
          <Input
            id={idConferma}
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
          rilascio. Puoi comunque collaudare la funzione, che per un admin è usabile anche da spenta.
        </p>
      )}
    </div>
  );
}
