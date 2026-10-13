"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { ArrowLeft, Copy, RefreshCw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { ErrorState, LoadingBlock } from "@/components/vinea/States";
import {
  ETICHETTA_AZIONE,
  ETICHETTA_STATO_INVITO,
  ETICHETTA_STATO_PARTNER,
  PARTNER_STATI,
  PARTNER_TIPOLOGIE,
  azioneRichiedeMotivo,
  azioniAmmesse,
  linkInvito,
} from "@/lib/partner/partner";
import { getSupabaseClient } from "@/lib/supabase/client";
import { creaPartnerAdminService } from "@/services/partner-service";
import type {
  PartnerAdmin,
  PartnerAzioneAdmin,
  PartnerInvito,
  PartnerInvitoCreato,
  PartnerStato,
} from "@/services/types";

/**
 * Amministrazione Vinea Partner (Blocco A): inviti e decisioni.
 *
 * L'interfaccia è una comodità: ogni porta ricontrolla il ruolo admin reale
 * in `public.user_roles`, rifiuta le decisioni sul proprio Partner e ammette
 * solo le transizioni dichiarate. I bottoni mostrati per stato rispecchiano
 * quelle regole, non le sostituiscono.
 *
 * Nessuna email parte da qui: il link d'invito si copia e si consegna a mano.
 * Il token compare una sola volta, subito dopo la creazione.
 */

const dataBreve = (iso: string | null) =>
  iso ? new Date(iso).toLocaleString("it-IT", { dateStyle: "short", timeStyle: "short" }) : "—";

function InvitoCreato({ invito, onChiudi }: { invito: PartnerInvitoCreato; onChiudi: () => void }) {
  const link = linkInvito(window.location.origin, invito.token);
  const [copiato, setCopiato] = useState(false);
  return (
    <div className="space-y-3 rounded-xl border border-bordeaux/40 bg-muted p-4" role="status">
      <p className="text-sm">
        Invito per <strong>{invito.email}</strong>, valido fino al {dataBreve(invito.scadeAt)}. Copia ora il
        link: non sarà più mostrato. Consegnalo solo al destinatario.
      </p>
      <Input readOnly value={link} aria-label="Link d'invito" onFocus={(e) => e.currentTarget.select()} />
      <div className="flex flex-wrap gap-2">
        <Button
          size="sm"
          onClick={() => {
            void navigator.clipboard?.writeText(link).then(() => setCopiato(true));
          }}
        >
          <Copy /> {copiato ? "Copiato" : "Copia link"}
        </Button>
        <Button size="sm" variant="outline" onClick={onChiudi}>
          Ho copiato il link
        </Button>
      </div>
    </div>
  );
}

function DecisionePartner({
  partner,
  onDecidi,
  inCorso,
}: {
  partner: PartnerAdmin;
  onDecidi: (azione: PartnerAzioneAdmin, motivo: string | null) => void;
  inCorso: boolean;
}) {
  const [motivo, setMotivo] = useState("");
  const azioni = azioniAmmesse(partner.stato);
  if (azioni.length === 0) return null;
  return (
    <div className="space-y-2 border-t border-border pt-3">
      <Label htmlFor={`motivo-${partner.id}`} className="text-xs">
        Motivo (obbligatorio per restituzione, sospensione e revoca; visibile al titolare)
      </Label>
      <Textarea
        id={`motivo-${partner.id}`}
        value={motivo}
        maxLength={500}
        rows={2}
        onChange={(e) => setMotivo(e.target.value)}
        disabled={inCorso}
      />
      <div className="flex flex-wrap gap-2">
        {azioni.map((azione) => {
          const serveMotivo = azioneRichiedeMotivo(azione);
          return (
            <Button
              key={azione}
              size="sm"
              variant={azione === "approva" || azione === "riattiva" ? "default" : "outline"}
              disabled={inCorso || (serveMotivo && !motivo.trim())}
              onClick={() => {
                if (azione === "revoca" && !window.confirm("La revoca è definitiva. Confermi?")) return;
                onDecidi(azione, motivo.trim() || null);
              }}
            >
              {ETICHETTA_AZIONE[azione]}
            </Button>
          );
        })}
      </div>
    </div>
  );
}

/**
 * Azioni di sicurezza su un Partner, in qualunque stato: sospendere gli annunci
 * aperti del titolare e, se revocato, riabilitarlo alle vendite private. Il
 * motivo è obbligatorio per entrambe; il server ricontrolla ruolo e stato.
 */
function SicurezzaPartner({
  partner,
  inCorso,
  onSospendiAnnunci,
  onRiabilita,
}: {
  partner: PartnerAdmin;
  inCorso: boolean;
  onSospendiAnnunci: (motivo: string) => void;
  onRiabilita: (motivo: string) => void;
}) {
  const [motivo, setMotivo] = useState("");
  const pulito = motivo.trim();
  return (
    <div className="space-y-2 border-t border-border pt-3">
      {partner.venditeBloccate ? (
        <p className="text-sm">
          Vendite bloccate: il titolare non può vendere, nemmeno da privato, finché non viene
          riabilitato. Gli ordini già pagati proseguono.
        </p>
      ) : null}
      <Label htmlFor={`sicurezza-${partner.id}`} className="text-xs">
        Motivo per le azioni di sicurezza (obbligatorio)
      </Label>
      <Textarea
        id={`sicurezza-${partner.id}`}
        value={motivo}
        maxLength={500}
        rows={2}
        onChange={(e) => setMotivo(e.target.value)}
        disabled={inCorso}
      />
      <div className="flex flex-wrap gap-2">
        <Button
          size="sm"
          variant="outline"
          disabled={inCorso || !pulito}
          onClick={() => {
            if (!window.confirm("Sospendere tutti gli annunci aperti di questo titolare?")) return;
            onSospendiAnnunci(pulito);
          }}
        >
          Sospendi annunci
        </Button>
        {partner.venditeBloccate ? (
          <Button
            size="sm"
            disabled={inCorso || !pulito}
            onClick={() => {
              if (!window.confirm("Riabilitare il titolare alle vendite private?")) return;
              onRiabilita(pulito);
            }}
          >
            Riabilita vendite private
          </Button>
        ) : null}
      </div>
    </div>
  );
}

function SpegnimentoEmergenza({ inCorso, onSpegni }: { inCorso: boolean; onSpegni: (motivo: string) => void }) {
  const [motivo, setMotivo] = useState("");
  const pulito = motivo.trim();
  return (
    <section className="space-y-3 rounded-2xl border border-border bg-card p-6">
      <h2 className="font-serif text-2xl">Spegnimento di emergenza</h2>
      <p className="text-sm text-muted-foreground">
        Ferma subito le nuove vendite Partner (acquisti, proposte, pubblicazioni). Gli ordini già
        creati proseguono: spedizioni, contestazioni, rimborsi e saldo non vengono toccati. La
        riaccensione non avviene da qui.
      </p>
      <Label htmlFor="emergenza-motivo" className="text-xs">
        Motivo (obbligatorio)
      </Label>
      <Textarea
        id="emergenza-motivo"
        value={motivo}
        maxLength={500}
        rows={2}
        onChange={(e) => setMotivo(e.target.value)}
        disabled={inCorso}
      />
      <Button
        variant="destructive"
        size="sm"
        disabled={inCorso || !pulito}
        onClick={() => {
          if (!window.confirm("Spegnere le vendite Partner per tutti?")) return;
          onSpegni(pulito);
          setMotivo("");
        }}
      >
        Spegni le vendite Partner
      </Button>
    </section>
  );
}

export function PartnerAdminClient() {
  const servizio = useMemo(() => creaPartnerAdminService(getSupabaseClient()), []);
  const [inviti, setInviti] = useState<PartnerInvito[]>([]);
  const [partner, setPartner] = useState<PartnerAdmin[]>([]);
  const [filtro, setFiltro] = useState<PartnerStato | null>(null);
  const [caricamento, setCaricamento] = useState(true);
  const [errore, setErrore] = useState<string | null>(null);
  const [esitoAzione, setEsitoAzione] = useState<{ tipo: "ok" | "errore"; testo: string } | null>(null);
  const [inCorso, setInCorso] = useState(false);
  const [creato, setCreato] = useState<PartnerInvitoCreato | null>(null);
  const [email, setEmail] = useState("");
  const [giorni, setGiorni] = useState("14");
  const [nota, setNota] = useState("");
  const inVolo = useRef(false);

  const carica = useCallback(async () => {
    setCaricamento(true);
    setErrore(null);
    const [i, p] = await Promise.all([servizio.inviti(), servizio.partner(filtro)]);
    if (!i.ok) setErrore(i.error);
    else if (!p.ok) setErrore(p.error);
    else {
      setInviti(i.data);
      setPartner(p.data);
    }
    setCaricamento(false);
  }, [servizio, filtro]);

  useEffect(() => {
    void carica();
  }, [carica]);

  const esegui = async (operazione: () => Promise<{ ok: boolean; error?: string }>, ok: string) => {
    if (inVolo.current) return;
    inVolo.current = true;
    setInCorso(true);
    setEsitoAzione(null);
    const esito = await operazione();
    setEsitoAzione(esito.ok ? { tipo: "ok", testo: ok } : { tipo: "errore", testo: esito.error ?? "" });
    await carica();
    setInCorso(false);
    inVolo.current = false;
  };

  const creaInvito = async (e: FormEvent) => {
    e.preventDefault();
    if (inVolo.current) return;
    inVolo.current = true;
    setInCorso(true);
    setEsitoAzione(null);
    const esito = await servizio.creaInvito({
      email: email.trim(),
      validitaGiorni: Number(giorni),
      nota: nota.trim() || null,
    });
    if (esito.ok) {
      setCreato(esito.data);
      setEmail("");
      setNota("");
    } else {
      setEsitoAzione({ tipo: "errore", testo: esito.error });
    }
    await carica();
    setInCorso(false);
    inVolo.current = false;
  };

  return (
    <div className="mx-auto max-w-5xl space-y-8 px-4 py-8">
      <header className="space-y-2">
        <Button asChild variant="ghost" size="sm">
          <Link href="/admin">
            <ArrowLeft /> Area admin
          </Link>
        </Button>
        <h1 className="font-serif text-3xl">Vinea Partner</h1>
        <p className="text-muted-foreground">
          Inviti e verifica delle attività. Ammissione solo su invito; nessuna condizione economica
          Partner è ancora applicata e la vendita da Partner attivi resta bloccata dal server.
        </p>
      </header>

      {esitoAzione ? (
        <p
          role={esitoAzione.tipo === "errore" ? "alert" : "status"}
          className={esitoAzione.tipo === "errore" ? "text-destructive" : ""}
        >
          {esitoAzione.testo}
        </p>
      ) : null}

      <section className="space-y-4 rounded-2xl border border-border bg-card p-6">
        <h2 className="font-serif text-2xl">Nuovo invito</h2>
        {creato ? <InvitoCreato invito={creato} onChiudi={() => setCreato(null)} /> : null}
        <form onSubmit={(e) => void creaInvito(e)} className="grid gap-4 sm:grid-cols-[2fr_1fr]">
          <div className="space-y-1.5">
            <Label htmlFor="invito-email">Email del destinatario</Label>
            <Input
              id="invito-email"
              type="email"
              required
              maxLength={254}
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              disabled={inCorso}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="invito-giorni">Validità (giorni, 1-30)</Label>
            <Input
              id="invito-giorni"
              type="number"
              min={1}
              max={30}
              value={giorni}
              onChange={(e) => setGiorni(e.target.value)}
              disabled={inCorso}
            />
          </div>
          <div className="space-y-1.5 sm:col-span-2">
            <Label htmlFor="invito-nota">Nota interna (facoltativa)</Label>
            <Input id="invito-nota" maxLength={500} value={nota} onChange={(e) => setNota(e.target.value)} disabled={inCorso} />
          </div>
          <div>
            <Button type="submit" disabled={inCorso || !email.trim()}>
              Crea invito
            </Button>
          </div>
        </form>
      </section>

      {caricamento ? <LoadingBlock /> : null}
      {errore ? <ErrorState title="Dati Partner non disponibili" message={errore} onRetry={() => void carica()} home={false} /> : null}

      {!caricamento && !errore ? (
        <>
          <section className="space-y-4">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <h2 className="font-serif text-2xl">Partner</h2>
              <div className="flex flex-wrap items-center gap-2">
                <Label htmlFor="filtro-stato" className="text-sm">
                  Stato
                </Label>
                <select
                  id="filtro-stato"
                  className="h-9 rounded-md border border-input bg-background px-2 text-sm"
                  value={filtro ?? ""}
                  onChange={(e) => setFiltro((e.target.value || null) as PartnerStato | null)}
                >
                  <option value="">Tutti</option>
                  {PARTNER_STATI.map((s) => (
                    <option key={s} value={s}>
                      {ETICHETTA_STATO_PARTNER[s]}
                    </option>
                  ))}
                </select>
                <Button size="sm" variant="outline" onClick={() => void carica()} disabled={inCorso}>
                  <RefreshCw /> Aggiorna
                </Button>
              </div>
            </div>
            {partner.length === 0 ? <p className="text-muted-foreground">Nessun Partner.</p> : null}
            <ul className="space-y-3">
              {partner.map((p) => (
                <li key={p.id} className="space-y-3 rounded-2xl border border-border bg-card p-5">
                  <div className="flex flex-wrap items-baseline justify-between gap-2">
                    <div className="min-w-0">
                      <p className="font-medium">{p.nomeCommerciale ?? "(dati non ancora compilati)"}</p>
                      <p className="break-words text-sm text-muted-foreground">
                        Titolare {p.titolareUsername ?? "—"} · {p.titolareEmail ?? p.invitoEmail}
                      </p>
                    </div>
                    <span className="rounded-full border border-border px-3 py-1 text-sm">
                      {ETICHETTA_STATO_PARTNER[p.stato]}
                    </span>
                  </div>
                  <dl className="grid gap-x-6 gap-y-1 text-sm sm:grid-cols-2">
                    <div><dt className="inline text-muted-foreground">Ragione sociale: </dt><dd className="inline">{p.ragioneSociale ?? "—"}</dd></div>
                    <div><dt className="inline text-muted-foreground">P.IVA: </dt><dd className="inline">{p.partitaIva ?? "—"}</dd></div>
                    <div><dt className="inline text-muted-foreground">Tipologia: </dt><dd className="inline">{PARTNER_TIPOLOGIE.find((t) => t.value === p.tipologia)?.label ?? "—"}</dd></div>
                    <div><dt className="inline text-muted-foreground">Email commerciale: </dt><dd className="inline break-words">{p.emailCommerciale ?? "—"}</dd></div>
                    <div className="sm:col-span-2"><dt className="inline text-muted-foreground">Sede: </dt><dd className="inline">{[p.sedeIndirizzo, p.sedeCap, p.sedeCitta, p.sedeProvincia].filter(Boolean).join(", ") || "—"}</dd></div>
                    <div><dt className="inline text-muted-foreground">Inviato: </dt><dd className="inline">{dataBreve(p.inviatoVerificaAt)}</dd></div>
                    <div><dt className="inline text-muted-foreground">Ultimo motivo: </dt><dd className="inline">{p.ultimoMotivo ?? "—"}</dd></div>
                  </dl>
                  <DecisionePartner
                    partner={p}
                    inCorso={inCorso}
                    onDecidi={(azione, motivo) =>
                      void esegui(() => servizio.decidi(p.id, azione, motivo), `${ETICHETTA_AZIONE[azione]}: fatto.`)
                    }
                  />
                  <SicurezzaPartner
                    partner={p}
                    inCorso={inCorso}
                    onSospendiAnnunci={(motivo) =>
                      void esegui(async () => {
                        const r = await servizio.sospendiAnnunci(p.id, motivo);
                        return r.ok ? { ok: true } : r;
                      }, "Annunci aperti sospesi.")
                    }
                    onRiabilita={(motivo) =>
                      void esegui(() => servizio.riabilitaVendite(p.id, motivo), "Vendite private riabilitate.")
                    }
                  />
                </li>
              ))}
            </ul>
          </section>

          <SpegnimentoEmergenza
            inCorso={inCorso}
            onSpegni={(motivo) =>
              void esegui(() => servizio.spegniVenditaPartner(motivo), "Vendite Partner spente.")
            }
          />

          <section className="space-y-3">
            <h2 className="font-serif text-2xl">Inviti</h2>
            {inviti.length === 0 ? <p className="text-muted-foreground">Nessun invito.</p> : null}
            <ul className="divide-y divide-border rounded-2xl border border-border bg-card">
              {inviti.map((i) => (
                <li key={i.id} className="flex flex-wrap items-center justify-between gap-3 p-4">
                  <div className="min-w-0">
                    <p className="break-words font-medium">{i.email}</p>
                    <p className="text-sm text-muted-foreground">
                      {ETICHETTA_STATO_INVITO[i.stato]} · creato {dataBreve(i.createdAt)} · scade {dataBreve(i.scadeAt)}
                      {i.notaAdmin ? ` · ${i.notaAdmin}` : ""}
                    </p>
                  </div>
                  {i.stato === "valido" || i.stato === "scaduto" ? (
                    <Button
                      size="sm"
                      variant="outline"
                      disabled={inCorso}
                      onClick={() => void esegui(() => servizio.revocaInvito(i.id, null), "Invito revocato.")}
                    >
                      Revoca
                    </Button>
                  ) : null}
                </li>
              ))}
            </ul>
          </section>
        </>
      ) : null}
    </div>
  );
}
