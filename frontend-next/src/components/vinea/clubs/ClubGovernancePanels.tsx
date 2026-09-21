"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Textarea } from "@/components/ui/textarea";
import { EmptyState, LoadingBlock } from "@/components/vinea/States";
import { getSupabaseClient } from "@/lib/supabase/client";
import {
  createClubGovernanceService,
  type ClubExternalLinkAdmin,
  type ClubJoinRequestAdmin,
  type ClubMemberAdmin,
  type ClubProposalAdmin,
  type ClubRuleVersionAdmin,
  type ManagedClub,
} from "@/services/phase12/club-governance-service";

const when = (value: string) => new Date(value).toLocaleString("it-IT");

function Notice({ error, status }: { error: string | null; status: string | null }) {
  return (
    <>
      {error ? <p role="alert" className="rounded-md border border-red-500/40 p-3 text-sm text-red-700">{error}</p> : null}
      {status ? <p role="status" className="rounded-md border border-emerald-600/30 p-3 text-sm text-emerald-800">{status}</p> : null}
    </>
  );
}

export function AdminClubGovernance() {
  const [proposals, setProposals] = useState<ClubProposalAdmin[]>([]);
  const [rules, setRules] = useState<ClubRuleVersionAdmin[]>([]);
  const [links, setLinks] = useState<ClubExternalLinkAdmin[]>([]);
  const [notes, setNotes] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);

  const load = useCallback(async () => {
    const client = getSupabaseClient();
    if (!client) { setError("Servizio Club non disponibile."); setLoading(false); return; }
    try {
      const service = createClubGovernanceService(client);
      const [nextProposals, nextRules, nextLinks] = await Promise.all([
        service.proposals(), service.rules(), service.links(),
      ]);
      setProposals(nextProposals);
      setRules(nextRules.filter((item) => item.status === "in_attesa"));
      setLinks(nextLinks.filter((item) => item.status === "in_attesa"));
      setError(null);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Caricamento non riuscito.");
    } finally { setLoading(false); }
  }, []);

  useEffect(() => { void load(); }, [load]);

  const act = async (key: string, success: string, action: () => Promise<void>) => {
    if (busy) return;
    setBusy(key); setError(null); setStatus(null);
    try { await action(); await load(); setStatus(success); }
    catch (cause) { setError(cause instanceof Error ? cause.message : "Operazione non riuscita."); }
    finally { setBusy(null); }
  };

  if (loading) return <LoadingBlock label="Caricamento governance Club" />;

  const service = () => createClubGovernanceService(getSupabaseClient());
  return (
    <section className="space-y-4" aria-labelledby="club-admin-title">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 id="club-admin-title" className="font-serif text-2xl">Governance Club</h2>
          <p className="text-sm text-muted-foreground">Proposte, regolamenti e link in attesa di revisione.</p>
        </div>
        <Button variant="outline" onClick={() => void load()} disabled={Boolean(busy)}>Aggiorna</Button>
      </div>
      <Notice error={error} status={status} />

      <h3 className="font-serif text-xl">Proposte Club</h3>
      {proposals.length === 0 ? <EmptyState title="Nessuna proposta" message="La coda proposte è vuota." /> : proposals.map((item) => (
        <Card key={item.slug} className="space-y-3 p-4" data-testid={`club-proposal-${item.slug}`}>
          <div className="flex flex-wrap justify-between gap-2"><div><p className="font-semibold">{item.nome}</p><p className="text-xs text-muted-foreground">{item.ownerUsername} · {when(item.createdAt)}</p></div><div className="flex flex-wrap gap-2"><Badge>{item.approvalStatus}</Badge><Badge>{item.accessType}</Badge></div></div>
          <p className="text-sm">{item.descrizione}</p>
          <dl className="grid gap-2 text-sm sm:grid-cols-2">
            <div><dt className="text-muted-foreground">Categoria</dt><dd>{item.categoria}</dd></div>
            <div><dt className="text-muted-foreground">Territorio</dt><dd>{item.territorio ?? "—"}</dd></div>
            <div><dt className="text-muted-foreground">Pubblicazione</dt><dd>{item.postingMode}</dd></div>
            <div><dt className="text-muted-foreground">Requisiti</dt><dd>{item.requirements ?? "Nessuno"}</dd></div>
          </dl>
          <ol className="list-decimal space-y-1 pl-5 text-sm">{item.regole.map((rule) => <li key={rule}>{rule}</li>)}</ol>
          {item.externalLinks.length ? <ul className="space-y-1 text-sm">{item.externalLinks.map((link) => <li key={link.id}><a className="underline" href={link.url} target="_blank" rel="noreferrer">{link.label ?? link.platform}</a></li>)}</ul> : null}
          <Label htmlFor={`proposal-note-${item.slug}`}>Nota di revisione</Label>
          <Textarea id={`proposal-note-${item.slug}`} value={notes[item.slug] ?? ""} onChange={(event) => setNotes((old) => ({ ...old, [item.slug]: event.target.value }))} maxLength={1000} />
          <div className="flex flex-wrap gap-2">
            <Button disabled={Boolean(busy)} onClick={() => void act(item.slug, "Club approvato.", () => service().reviewProposal(item.slug, true, notes[item.slug]?.trim() || null))}>Approva</Button>
            <Button variant="outline" disabled={Boolean(busy) || !notes[item.slug]?.trim()} onClick={() => void act(item.slug, "Club rifiutato.", () => service().reviewProposal(item.slug, false, notes[item.slug].trim()))}>Rifiuta</Button>
          </div>
        </Card>
      ))}

      <h3 className="font-serif text-xl">Regolamenti</h3>
      {rules.length === 0 ? <p className="text-sm text-muted-foreground">Nessuna versione in attesa.</p> : rules.map((item) => (
        <Card key={item.id} className="space-y-3 p-4">
          <p className="font-medium">{item.clubSlug} · versione {item.version}</p>
          <ol className="list-decimal space-y-1 pl-5 text-sm">{item.rules.map((rule) => <li key={rule}>{rule}</li>)}</ol>
          <Textarea aria-label={`Nota regolamento ${item.clubSlug}`} placeholder="Nota di revisione" value={notes[item.id] ?? ""} onChange={(event) => setNotes((old) => ({ ...old, [item.id]: event.target.value }))} />
          <div className="flex flex-wrap gap-2">
            <Button disabled={Boolean(busy)} onClick={() => void act(item.id, "Regolamento approvato.", () => service().reviewRules(item.id, true, notes[item.id]?.trim() || null))}>Approva</Button>
            <Button variant="outline" disabled={Boolean(busy) || !notes[item.id]?.trim()} onClick={() => void act(item.id, "Regolamento rifiutato.", () => service().reviewRules(item.id, false, notes[item.id].trim()))}>Rifiuta</Button>
          </div>
        </Card>
      ))}

      <h3 className="font-serif text-xl">Link esterni</h3>
      {links.length === 0 ? <p className="text-sm text-muted-foreground">Nessun link in attesa.</p> : links.map((item) => (
        <Card key={item.id} className="flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:justify-between">
          <div className="min-w-0"><p className="font-medium">{item.clubSlug} · {item.platform}</p><a href={item.url} className="block truncate text-sm underline" target="_blank" rel="noreferrer">{item.url}</a></div>
          <div className="flex gap-2"><Button disabled={Boolean(busy)} onClick={() => void act(item.id, "Link approvato.", () => service().reviewLink(item.id, true))}>Approva</Button><Button variant="outline" disabled={Boolean(busy)} onClick={() => void act(item.id, "Link rifiutato.", () => service().reviewLink(item.id, false))}>Rifiuta</Button></div>
        </Card>
      ))}
    </section>
  );
}

export function ClubManagementPanel({ slug }: { slug: string }) {
  const [club, setClub] = useState<ManagedClub | null>(null);
  const [members, setMembers] = useState<ClubMemberAdmin[]>([]);
  const [requests, setRequests] = useState<ClubJoinRequestAdmin[]>([]);
  const [rules, setRules] = useState<ClubRuleVersionAdmin[]>([]);
  const [links, setLinks] = useState<ClubExternalLinkAdmin[]>([]);
  const [currentUserId, setCurrentUserId] = useState<string | null>(null);
  const [ruleDraft, setRuleDraft] = useState("");
  const [platform, setPlatform] = useState<ClubExternalLinkAdmin["platform"]>("sito");
  const [url, setUrl] = useState("");
  const [label, setLabel] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);
  const client = useMemo(() => getSupabaseClient(), []);

  const load = useCallback(async () => {
    if (!client) return;
    try {
      const service = createClubGovernanceService(client);
      const [clubs, nextMembers, nextRequests, nextRules, nextLinks, auth] = await Promise.all([
        service.managedClubs(), service.members(slug), service.joinRequests(slug),
        service.rules(slug), service.links(slug), client.auth.getUser(),
      ]);
      setClub(clubs.find((item) => item.slug === slug) ?? null);
      setMembers(nextMembers); setRequests(nextRequests); setRules(nextRules); setLinks(nextLinks);
      setCurrentUserId(auth.data.user?.id ?? null); setError(null);
    } catch { setClub(null); }
  }, [client, slug]);

  useEffect(() => { void load(); }, [load]);

  const act = async (key: string, success: string, action: () => Promise<void>) => {
    if (busy) return;
    setBusy(key); setError(null); setStatus(null);
    try { await action(); await load(); setStatus(success); }
    catch (cause) { setError(cause instanceof Error ? cause.message : "Operazione non riuscita."); }
    finally { setBusy(null); }
  };

  if (!club || !client) return null;
  const service = () => createClubGovernanceService(client);
  const owner = currentUserId === club.ownerId;
  const moderators = members.filter((item) => item.role !== "membro");

  return (
    <section className="space-y-4 rounded-2xl border bg-card p-4 sm:p-6" aria-labelledby="club-management-title" data-testid="club-management-panel">
      <div><h2 id="club-management-title" className="font-serif text-2xl">Gestione Club</h2><p className="text-sm text-muted-foreground">Membri, richieste, moderatori, regolamento e link.</p></div>
      <Notice error={error} status={status} />
      <Tabs defaultValue="informazioni">
        <TabsList className="h-auto flex-wrap justify-start">
          <TabsTrigger value="informazioni">Informazioni</TabsTrigger><TabsTrigger value="membri">Membri</TabsTrigger>
          <TabsTrigger value="richieste">Richieste ({requests.length})</TabsTrigger><TabsTrigger value="moderatori">Moderatori</TabsTrigger>
          <TabsTrigger value="regolamento">Regolamento</TabsTrigger><TabsTrigger value="link">Link</TabsTrigger>
        </TabsList>
        <TabsContent value="informazioni" className="space-y-2 text-sm"><p><b>Accesso:</b> {club.accessType}</p><p><b>Pubblicazione:</b> {club.postingMode}</p><p><b>Categoria:</b> {club.categoria ?? "—"}</p><p><b>Territorio:</b> {club.territorio ?? "—"}</p><p><b>Requisiti:</b> {club.requirements ?? "Nessuno"}</p></TabsContent>
        <TabsContent value="membri" className="space-y-2">{members.map((item) => <Card key={item.userId} className="flex flex-wrap items-center justify-between gap-2 p-3"><div><p className="font-medium">{item.username}</p><p className="text-xs text-muted-foreground">Membro dal {when(item.createdAt)}</p></div><Badge>{item.role}</Badge></Card>)}</TabsContent>
        <TabsContent value="richieste" className="space-y-2">{requests.length === 0 ? <EmptyState title="Nessuna richiesta" message="Non ci sono ingressi da valutare." /> : requests.map((item) => <Card key={item.id} className="space-y-2 p-3"><p className="font-medium">{item.username}</p>{item.message ? <p className="text-sm">{item.message}</p> : null}<div className="flex gap-2"><Button disabled={Boolean(busy)} onClick={() => void act(item.id, "Ingresso approvato.", () => service().reviewJoinRequest(item.id, true, null))}>Approva</Button><Button variant="outline" disabled={Boolean(busy)} onClick={() => void act(item.id, "Ingresso rifiutato.", () => service().reviewJoinRequest(item.id, false, null))}>Rifiuta</Button></div></Card>)}</TabsContent>
        <TabsContent value="moderatori" className="space-y-3">
          {moderators.map((item) => <Card key={item.userId} className="flex flex-wrap items-center justify-between gap-2 p-3"><div><p className="font-medium">{item.username}</p><Badge>{item.role}</Badge></div>{owner && item.role === "moderatore" ? <Button variant="outline" disabled={Boolean(busy)} onClick={() => void act(item.userId, "Moderatore rimosso.", () => service().setModerator(slug, item.userId, false))}>Rimuovi</Button> : null}</Card>)}
          {owner ? <div className="space-y-2"><p className="text-sm font-medium">Nomina un membro</p>{members.filter((item) => item.role === "membro").map((item) => <div key={item.userId} className="flex items-center justify-between gap-2"><span className="text-sm">{item.username}</span><Button size="sm" disabled={Boolean(busy)} onClick={() => void act(item.userId, "Moderatore nominato.", () => service().setModerator(slug, item.userId, true))}>Nomina</Button></div>)}</div> : <p className="text-sm text-muted-foreground">Solo il proprietario può cambiare i moderatori.</p>}
        </TabsContent>
        <TabsContent value="regolamento" className="space-y-3">
          {rules.map((item) => <Card key={item.id} className="space-y-2 p-3"><div className="flex justify-between"><p className="font-medium">Versione {item.version}</p><Badge>{item.status}</Badge></div><ol className="list-decimal pl-5 text-sm">{item.rules.map((rule) => <li key={rule}>{rule}</li>)}</ol></Card>)}
          <Label htmlFor={`rules-${slug}`}>Nuova versione, una regola per riga</Label><Textarea id={`rules-${slug}`} value={ruleDraft} onChange={(event) => setRuleDraft(event.target.value)} rows={5} />
          <Button disabled={Boolean(busy) || ruleDraft.split("\n").filter((item) => item.trim().length >= 3).length === 0} onClick={() => void act("rules", "Regolamento inviato per approvazione.", async () => { await service().proposeRules(slug, ruleDraft.split("\n").map((item) => item.trim()).filter(Boolean)); setRuleDraft(""); })}>Proponi versione</Button>
        </TabsContent>
        <TabsContent value="link" className="space-y-3">
          {links.map((item) => <Card key={item.id} className="flex flex-col gap-2 p-3 sm:flex-row sm:items-center sm:justify-between"><div className="min-w-0"><p className="font-medium">{item.label ?? item.platform} <Badge>{item.status}</Badge></p><a className="block truncate text-sm underline" href={item.url} target="_blank" rel="noreferrer">{item.url}</a></div><Button variant="outline" disabled={Boolean(busy)} onClick={() => void act(item.id, "Link rimosso.", () => service().removeLink(item.id))}>Rimuovi</Button></Card>)}
          <div className="grid gap-2 sm:grid-cols-[160px_1fr_1fr]">
            <label><span className="text-xs">Piattaforma</span><select className="mt-1 w-full rounded-md border bg-background px-3 py-2" value={platform} onChange={(event) => setPlatform(event.target.value as ClubExternalLinkAdmin["platform"])}>{["facebook","instagram","x","telegram","discord","sito","altro"].map((value) => <option key={value}>{value}</option>)}</select></label>
            <label><span className="text-xs">URL HTTPS</span><Input className="mt-1" value={url} onChange={(event) => setUrl(event.target.value)} placeholder="https://" /></label>
            <label><span className="text-xs">Etichetta</span><Input className="mt-1" value={label} onChange={(event) => setLabel(event.target.value)} /></label>
          </div>
          <Button disabled={Boolean(busy) || !url.startsWith("https://")} onClick={() => void act("link", "Link inviato per approvazione.", async () => { await service().proposeLink(slug, platform, url, label.trim() || null); setUrl(""); setLabel(""); })}>Aggiungi link</Button>
        </TabsContent>
      </Tabs>
    </section>
  );
}
