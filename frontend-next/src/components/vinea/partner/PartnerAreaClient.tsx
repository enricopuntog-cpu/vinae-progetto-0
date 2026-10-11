"use client";

import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { Building2, RefreshCw, Send } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { ErrorState, LoadingBlock } from "@/components/vinea/States";
import {
  ETICHETTA_STATO_PARTNER,
  PARTNER_TIPOLOGIE,
  SPIEGAZIONE_STATO_PARTNER,
  datiDaPartner,
  validaDatiPartner,
  type CampoPartner,
} from "@/lib/partner/partner";
import { getSupabaseClient } from "@/lib/supabase/client";
import { creaPartnerService } from "@/services/partner-service";
import type { Partner, PartnerDatiInput, PartnerTipologia } from "@/services/types";

/**
 * Area del titolare di un Partner (Blocco A).
 *
 * Qui il titolare compila l'identità aziendale finché il Partner è
 * «invitato», la consegna alla verifica e poi la vede in sola lettura con lo
 * stato spiegato. Nessun comando decide un esito: approvazione, sospensione e
 * revoca esistono solo nella porta admin del database.
 */

const CAMPI: ReadonlyArray<{ campo: Exclude<CampoPartner, "tipologia">; label: string; autoComplete?: string; maxLength: number }> = [
  { campo: "ragioneSociale", label: "Ragione sociale", autoComplete: "organization", maxLength: 200 },
  { campo: "nomeCommerciale", label: "Nome commerciale", maxLength: 120 },
  { campo: "partitaIva", label: "Partita IVA", maxLength: 16 },
  { campo: "emailCommerciale", label: "Email commerciale", autoComplete: "email", maxLength: 254 },
  { campo: "sedeIndirizzo", label: "Indirizzo della sede", autoComplete: "street-address", maxLength: 200 },
  { campo: "sedeCap", label: "CAP", autoComplete: "postal-code", maxLength: 5 },
  { campo: "sedeCitta", label: "Città", autoComplete: "address-level2", maxLength: 100 },
  { campo: "sedeProvincia", label: "Provincia (sigla)", maxLength: 2 },
];

const formatoData = (iso: string | null) =>
  iso ? new Date(iso).toLocaleDateString("it-IT", { day: "numeric", month: "long", year: "numeric" }) : "—";

function Riepilogo({ partner }: { partner: Partner }) {
  const tipologia = PARTNER_TIPOLOGIE.find((t) => t.value === partner.tipologia)?.label ?? "—";
  const righe: Array<[string, string]> = [
    ["Ragione sociale", partner.ragioneSociale ?? "—"],
    ["Nome commerciale", partner.nomeCommerciale ?? "—"],
    ["Partita IVA", partner.partitaIva ?? "—"],
    ["Tipologia", tipologia],
    ["Email commerciale", partner.emailCommerciale ?? "—"],
    [
      "Sede",
      [partner.sedeIndirizzo, [partner.sedeCap, partner.sedeCitta].filter(Boolean).join(" "), partner.sedeProvincia]
        .filter(Boolean)
        .join(", ") || "—",
    ],
    ["Paese", partner.paese === "IT" ? "Italia" : partner.paese],
    ["Inviato alla verifica", formatoData(partner.inviatoVerificaAt)],
  ];
  if (partner.attivoDal) righe.push(["Partner dal", formatoData(partner.attivoDal)]);
  return (
    <dl className="grid gap-x-6 gap-y-3 sm:grid-cols-2">
      {righe.map(([etichetta, valore]) => (
        <div key={etichetta} className="min-w-0">
          <dt className="text-xs uppercase tracking-wide text-muted-foreground">{etichetta}</dt>
          <dd className="break-words">{valore}</dd>
        </div>
      ))}
    </dl>
  );
}

export function PartnerAreaClient() {
  const servizio = useMemo(() => creaPartnerService(getSupabaseClient()), []);
  const [partner, setPartner] = useState<Partner | null>(null);
  const [caricamento, setCaricamento] = useState(true);
  const [errore, setErrore] = useState<string | null>(null);
  const [dati, setDati] = useState<PartnerDatiInput>(datiDaPartner(null));
  const [messaggio, setMessaggio] = useState<{ tipo: "ok" | "errore"; testo: string } | null>(null);
  const [inCorso, setInCorso] = useState(false);
  const inVolo = useRef(false);

  const carica = useCallback(async () => {
    setCaricamento(true);
    setErrore(null);
    const esito = await servizio.mio();
    if (esito.ok) {
      setPartner(esito.data);
      setDati(datiDaPartner(esito.data));
    } else {
      setErrore(esito.error);
    }
    setCaricamento(false);
  }, [servizio]);

  useEffect(() => {
    void carica();
  }, [carica]);

  const { errori, completo } = validaDatiPartner(dati);
  const haErrori = Object.keys(errori).length > 0;

  const salva = async (e?: FormEvent) => {
    e?.preventDefault();
    if (inVolo.current || haErrori) return;
    inVolo.current = true;
    setInCorso(true);
    setMessaggio(null);
    const esito = await servizio.aggiornaDati(dati);
    if (esito.ok) {
      setPartner(esito.data);
      setDati(datiDaPartner(esito.data));
      setMessaggio({ tipo: "ok", testo: "Dati salvati. Puoi completarli e inviarli quando vuoi." });
    } else {
      setMessaggio({ tipo: "errore", testo: esito.error });
    }
    setInCorso(false);
    inVolo.current = false;
  };

  const invia = async () => {
    if (inVolo.current || haErrori || !completo) return;
    inVolo.current = true;
    setInCorso(true);
    setMessaggio(null);
    const salvati = await servizio.aggiornaDati(dati);
    if (!salvati.ok) {
      setMessaggio({ tipo: "errore", testo: salvati.error });
    } else {
      const esito = await servizio.inviaVerifica();
      if (esito.ok) {
        setMessaggio({ tipo: "ok", testo: "Dati inviati alla verifica di Vinea." });
        await carica();
      } else {
        setMessaggio({ tipo: "errore", testo: esito.error });
      }
    }
    setInCorso(false);
    inVolo.current = false;
  };

  if (caricamento) return <LoadingBlock />;
  if (errore) return <ErrorState title="Area Partner non disponibile" message={errore} onRetry={() => void carica()} />;

  if (!partner) {
    return (
      <section className="rounded-2xl border border-border bg-card p-6">
        <h2 className="font-serif text-2xl">Nessun Partner collegato</h2>
        <p className="mt-2 text-muted-foreground">
          Vinea Partner è riservato alle attività invitate dall&apos;amministrazione Vinea. Se hai
          ricevuto un link d&apos;invito, aprilo da questo dispositivo dopo aver effettuato
          l&apos;accesso con l&apos;indirizzo email a cui è stato inviato.
        </p>
      </section>
    );
  }

  const modificabile = partner.stato === "invitato";

  return (
    <div className="space-y-6">
      <section className="rounded-2xl border border-border bg-card p-6" aria-live="polite">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h2 className="flex items-center gap-2 font-serif text-2xl">
            <Building2 className="size-6" aria-hidden /> Stato della richiesta
          </h2>
          <span className="rounded-full border border-border px-3 py-1 text-sm font-medium" data-stato={partner.stato}>
            {ETICHETTA_STATO_PARTNER[partner.stato]}
          </span>
        </div>
        <p className="mt-3 text-muted-foreground">{SPIEGAZIONE_STATO_PARTNER[partner.stato]}</p>
        {partner.ultimoMotivo && partner.stato !== "attivo" ? (
          <p className="mt-3 rounded-lg bg-muted p-3 text-sm">
            <span className="font-medium">Nota di Vinea: </span>
            {partner.ultimoMotivo}
          </p>
        ) : null}
        <Button variant="ghost" size="sm" className="mt-3" onClick={() => void carica()} disabled={inCorso}>
          <RefreshCw /> Aggiorna
        </Button>
      </section>

      {modificabile ? (
        <form onSubmit={(e) => void salva(e)} className="space-y-4 rounded-2xl border border-border bg-card p-6" noValidate>
          <div>
            <h2 className="font-serif text-2xl">Dati dell&apos;attività</h2>
            <p className="text-sm text-muted-foreground">
              Sede in Italia. Dopo l&apos;invio i dati non sono più modificabili, salvo una richiesta
              di correzione da parte di Vinea.
            </p>
          </div>
          <div className="grid gap-4 sm:grid-cols-2">
            {CAMPI.map(({ campo, label, autoComplete, maxLength }) => (
              <div key={campo} className="space-y-1.5">
                <Label htmlFor={`partner-${campo}`}>{label}</Label>
                <Input
                  id={`partner-${campo}`}
                  value={dati[campo]}
                  maxLength={maxLength}
                  autoComplete={autoComplete}
                  aria-invalid={Boolean(errori[campo])}
                  aria-describedby={errori[campo] ? `partner-${campo}-errore` : undefined}
                  onChange={(e) => setDati((d) => ({ ...d, [campo]: e.target.value }))}
                  disabled={inCorso}
                />
                {errori[campo] ? (
                  <p id={`partner-${campo}-errore`} className="text-sm text-destructive">
                    {errori[campo]}
                  </p>
                ) : null}
              </div>
            ))}
            <div className="space-y-1.5">
              <Label htmlFor="partner-tipologia">Tipologia di attività</Label>
              <select
                id="partner-tipologia"
                className="h-10 w-full rounded-md border border-input bg-background px-3 text-sm"
                value={dati.tipologia ?? ""}
                onChange={(e) =>
                  setDati((d) => ({ ...d, tipologia: (e.target.value || null) as PartnerTipologia | null }))
                }
                disabled={inCorso}
              >
                <option value="">Seleziona…</option>
                {PARTNER_TIPOLOGIE.map((t) => (
                  <option key={t.value} value={t.value}>
                    {t.label}
                  </option>
                ))}
              </select>
            </div>
          </div>
          {messaggio ? (
            <p role={messaggio.tipo === "errore" ? "alert" : "status"} className={messaggio.tipo === "errore" ? "text-sm text-destructive" : "text-sm"}>
              {messaggio.testo}
            </p>
          ) : null}
          <div className="flex flex-wrap gap-2">
            <Button type="submit" variant="outline" disabled={inCorso || haErrori}>
              Salva bozza
            </Button>
            <Button type="button" onClick={() => void invia()} disabled={inCorso || haErrori || !completo}>
              <Send /> Invia alla verifica
            </Button>
          </div>
          {!completo ? (
            <p className="text-xs text-muted-foreground">Per inviare servono tutti i campi.</p>
          ) : null}
        </form>
      ) : (
        <section className="rounded-2xl border border-border bg-card p-6">
          <h2 className="mb-4 font-serif text-2xl">Dati dell&apos;attività</h2>
          <Riepilogo partner={partner} />
          {messaggio ? (
            <p role={messaggio.tipo === "errore" ? "alert" : "status"} className="mt-4 text-sm">
              {messaggio.testo}
            </p>
          ) : null}
        </section>
      )}
    </div>
  );
}
