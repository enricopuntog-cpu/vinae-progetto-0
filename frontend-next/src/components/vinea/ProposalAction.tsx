"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { getSupabaseClient } from "@/lib/supabase/client";
import { useVinea } from "@/lib/vinea-store";
import { createProposalService } from "@/services/phase7/proposal-service";
import { creaPreventivoService, type PreventivoEconomico } from "@/services/preventivo-service";
import type { ProposalRecord } from "@/services/types";

const euro = (cents: number) => new Intl.NumberFormat("it-IT", { style: "currency", currency: "EUR" }).format(cents / 100);
const ATTIVE = new Set(["inviata", "controproposta", "accettata"]);

const ProposalStatus = ({ proposal, listingSlug }: { proposal: ProposalRecord; listingSlug: string }) => (
  <div className="rounded-xl border border-oro/40 bg-oro/10 p-3 text-sm">
    {proposal.stato === "controproposta" ? `Controproposta ricevuta: ${euro(proposal.controproposta_cents ?? 0)}.` : null}
    {proposal.stato === "inviata" ? `Proposta registrata: ${euro(proposal.prezzo_proposto_cents)}.` : null}
    {proposal.stato === "accettata" ? <><span>Proposta accettata. </span><Link href={`/checkout/${listingSlug}?prop=${proposal.id}`} className="text-bordeaux underline">Vai al checkout</Link></> : null}
  </div>
);

/**
 * VP-D: quanto pagherebbe l'acquirente al prezzo che sta proponendo, chiesto
 * al database con la classe del venditore dell'annuncio (mai un'aliquota
 * scelta qui). Un'attesa breve evita una richiesta a ogni tasto; senza
 * risposta la stima semplicemente non compare.
 */
const usePreventivoProposta = (listingId: string, cents: number | null) => {
  const client = getSupabaseClient();
  const service = useMemo(() => creaPreventivoService(client), [client]);
  const [preventivo, setPreventivo] = useState<PreventivoEconomico | null>(null);
  useEffect(() => {
    setPreventivo(null);
    if (!client || cents === null) return;
    let attivo = true;
    const timer = setTimeout(() => {
      void service.annuncio(listingId, { prezzoUnitarioCents: cents }).then((esito) => {
        if (attivo && esito.ok) setPreventivo(esito.data.preventivo);
      });
    }, 300);
    return () => {
      attivo = false;
      clearTimeout(timer);
    };
  }, [client, service, listingId, cents]);
  return preventivo;
};

export const ProposalAction = ({ listingId, listingSlug, prezzo, disabled }: { listingId: string; listingSlug: string; prezzo: number; disabled?: boolean }) => {
  const { authUser } = useVinea();
  const client = getSupabaseClient();
  const service = useMemo(() => createProposalService(client), [client]);
  const [proposal, setProposal] = useState<ProposalRecord | null>(null);
  const [open, setOpen] = useState(false);
  const [value, setValue] = useState(String(Math.round(prezzo * 0.9)));
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const centsProposti = (() => {
    const cents = Math.round(Number(value) * 100);
    return Number.isSafeInteger(cents) && cents > 0 ? cents : null;
  })();
  const stima = usePreventivoProposta(listingId, open ? centsProposti : null);

  useEffect(() => {
    if (!authUser || !client) return;
    let active = true;
    void service.mie().then((result) => {
      if (!active || !result.ok) return;
      setProposal(result.data.find((row) => row.listing_id === listingId && ATTIVE.has(row.stato)) ?? null);
    });
    return () => { active = false; };
  }, [authUser, client, listingId, service]);

  const send = async () => {
    const cents = Math.round(Number(value) * 100);
    if (!Number.isSafeInteger(cents) || cents <= 0) return setError("Inserisci un prezzo valido.");
    setLoading(true);
    setError(null);
    const result = await service.invia(listingId, cents);
    setLoading(false);
    if (!result.ok) return setError(result.error);
    setProposal(result.data);
    setOpen(false);
  };

  if (proposal) return <ProposalStatus proposal={proposal} listingSlug={listingSlug} />;
  if (!authUser) return <Button asChild variant="outline"><Link href="/accedi">Accedi per proporre</Link></Button>;
  if (!client) return null;
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild><Button variant="outline" disabled={disabled}>Proponi</Button></DialogTrigger>
      <DialogContent>
        <DialogHeader><DialogTitle className="font-serif text-2xl">Fai una proposta</DialogTitle></DialogHeader>
        <p className="text-sm text-muted-foreground">Prezzo richiesto: <b>{euro(Math.round(prezzo * 100))}</b>. L'offerta resta valida 7 giorni.</p>
        <Input type="number" min="1" value={value} onChange={(event) => setValue(event.target.value)} />
        {stima ? (
          <p className="text-sm text-muted-foreground" data-testid="proposta-stima">
            Se accettata pagherai circa <b>{euro(stima.totaleCents)}</b> ({euro(stima.prezzoUnitarioCents)} al
            venditore + {euro(stima.commissioneCents)} di servizio Vinea), imballaggio e spedizione esclusi.
          </p>
        ) : null}
        {error ? <p role="alert" className="text-sm text-destructive">{error}</p> : null}
        <DialogFooter><Button variant="outline" onClick={() => setOpen(false)}>Annulla</Button><Button onClick={() => void send()} disabled={loading} className="bg-bordeaux hover:bg-bordeaux/90">{loading ? "Invio…" : "Invia proposta"}</Button></DialogFooter>
      </DialogContent>
    </Dialog>
  );
};
