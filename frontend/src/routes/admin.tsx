import { createFileRoute, Link } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import {
  Shield,
  Flag,
  Users as UsersIcon,
  Tag,
  Eye,
  PauseCircle,
  PencilLine,
  Check,
  Trash2,
  RotateCcw,
  MessageSquare,
  FileText,
  ChevronRight,
  AlertTriangle,
  Info,
} from "lucide-react";
import { adminKpi } from "@/data/extra";
import { communities } from "@/data/communities";
import { wines } from "@/data/wines";
import { Kpi } from "@/components/vinea/Layout";
import { Button } from "@/components/ui/button";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useVinea, formatEUR } from "@/lib/vinea-store";
import {
  reportStatusLabel,
  reportStatusTone,
  reportTargetLabel,
  modActionLabel,
  modActionTone,
  type Report,
  type ReportStatus,
  type Priorita,
  type ModAction,
} from "@/data/moderation";
import { colorBuyerStatus, labelBuyerStatus } from "@/data/orders";

export const Route = createFileRoute("/admin")({
  head: () => ({
    meta: [
      { title: "Pannello moderazione — Vinea" },
      { name: "description", content: "Coda moderazione, controversie e audit log (demo)." },
      { name: "robots", content: "noindex" },
    ],
  }),
  component: Admin,
});

function Admin() {
  const { ruolo, modScope, setModScope } = useVinea();

  if (ruolo !== "admin") {
    return (
      <div className="mx-auto max-w-lg space-y-3 rounded-3xl border border-border bg-card p-6 text-center md:p-10">
        <Shield className="mx-auto h-10 w-10 text-bordeaux" />
        <h1 className="font-serif text-2xl">Solo per moderatori</h1>
        <p className="text-sm text-muted-foreground">
          Attiva la modalità <b>Admin</b> dal selettore in alto per accedere al pannello di
          moderazione dimostrativo.
        </p>
      </div>
    );
  }

  const clubSlug = typeof modScope === "object" ? modScope.club : undefined;
  const isClub = clubSlug !== undefined;

  return (
    <div className="space-y-6">
      <header className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <span className="grid h-10 w-10 place-items-center rounded-full bg-antracite text-crema">
              <Shield className="h-5 w-5" />
            </span>
            <div>
              <h1 className="font-serif text-2xl md:text-3xl">Pannello moderazione</h1>
              <p className="text-xs text-muted-foreground">
                Demo — nessuna azione ha effetti reali.
              </p>
            </div>
          </div>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          <Label className="text-xs text-muted-foreground">Ambito:</Label>
          <Select
            value={clubSlug ? `club:${clubSlug}` : "piattaforma"}
            onValueChange={(v) =>
              setModScope(v === "piattaforma" ? "piattaforma" : { club: v.slice(5) })
            }
          >
            <SelectTrigger className="h-8 w-52 text-xs">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="piattaforma">Moderatore piattaforma (tutto)</SelectItem>
              {communities.map((c) => (
                <SelectItem key={c.slug} value={`club:${c.slug}`}>
                  Moderatore Club: {c.nome}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Link
            to="/admin/stati"
            className="inline-flex h-8 items-center gap-1 rounded-md border border-border bg-secondary/60 px-3 text-xs font-medium hover:bg-secondary"
          >
            Stati demo
          </Link>
        </div>
      </header>

      {isClub && (
        <div className="flex items-start gap-2 rounded-2xl border border-oro/40 bg-oro/10 p-3 text-xs">
          <Info className="mt-0.5 h-4 w-4 shrink-0 text-oro" />
          <p>
            Stai moderando come <b>Mod. Club {clubSlug}</b>: vedi solo i contenuti del tuo club,
            senza dati sensibili di ordini o note amministrative generali.
          </p>
        </div>
      )}

      {!isClub && (
        <section className="grid grid-cols-2 gap-3 md:grid-cols-5">
          <Kpi label="Utenti" value={adminKpi.utenti.toLocaleString("it-IT")} hint="totali" />
          <Kpi label="Annunci attivi" value={adminKpi.annunciAttivi.toLocaleString("it-IT")} />
          <Kpi label="Segnalazioni" value={String(adminKpi.segnalazioniAperte)} hint="aperte" />
          <Kpi label="In revisione" value={String(adminKpi.inRevisione)} />
          <Kpi label="Club" value={String(adminKpi.communityAttive)} hint="attivi" />
        </section>
      )}

      <Tabs defaultValue="coda">
        <div className="-mx-4 tab-scroll overflow-x-auto px-4 sm:mx-0 sm:px-0">
          <TabsList className="inline-flex w-max min-w-full bg-secondary">
            <TabsTrigger value="coda">
              <Flag className="h-4 w-4" /> Coda segnalazioni
            </TabsTrigger>
            {!isClub && (
              <TabsTrigger value="controversie">
                <AlertTriangle className="h-4 w-4" /> Controversie ordini
              </TabsTrigger>
            )}
            <TabsTrigger value="audit">
              <FileText className="h-4 w-4" /> Audit log
            </TabsTrigger>
          </TabsList>
        </div>

        <TabsContent value="coda" className="mt-4">
          <CodaSegnalazioni />
        </TabsContent>

        {!isClub && (
          <TabsContent value="controversie" className="mt-4">
            <Controversie />
          </TabsContent>
        )}

        <TabsContent value="audit" className="mt-4">
          <AuditLog />
        </TabsContent>
      </Tabs>
    </div>
  );
}

// ------------------------ CODA SEGNALAZIONI ------------------------

function CodaSegnalazioni() {
  const { reports, modScope } = useVinea();
  const clubSlug = typeof modScope === "object" ? modScope.club : undefined;
  const isClub = clubSlug !== undefined;

  const [priorita, setPriorita] = useState<"tutte" | Priorita>("tutte");
  const [stato, setStato] = useState<"tutti" | ReportStatus>("tutti");
  const [sel, setSel] = useState<Report | null>(null);

  const filtrate = useMemo(() => {
    let list = reports;
    if (isClub) list = list.filter((r) => r.clubSlug === clubSlug);
    if (priorita !== "tutte") list = list.filter((r) => r.priorita === priorita);
    if (stato !== "tutti") list = list.filter((r) => r.stato === stato);
    return list;
  }, [reports, isClub, clubSlug, priorita, stato]);

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <Select
          value={priorita}
          onValueChange={(value) => {
            if (value === "tutte" || value === "alta" || value === "media" || value === "bassa") {
              setPriorita(value);
            }
          }}
        >
          <SelectTrigger className="h-8 w-40 text-xs">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="tutte">Tutte le priorità</SelectItem>
            <SelectItem value="alta">Priorità alta</SelectItem>
            <SelectItem value="media">Priorità media</SelectItem>
            <SelectItem value="bassa">Priorità bassa</SelectItem>
          </SelectContent>
        </Select>
        <Select
          value={stato}
          onValueChange={(value) => {
            if (
              value === "tutti" ||
              value === "inviata" ||
              value === "in_revisione" ||
              value === "info_richieste" ||
              value === "risolta" ||
              value === "respinta"
            ) {
              setStato(value);
            }
          }}
        >
          <SelectTrigger className="h-8 w-44 text-xs">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="tutti">Tutti gli stati</SelectItem>
            <SelectItem value="inviata">Inviate</SelectItem>
            <SelectItem value="in_revisione">In revisione</SelectItem>
            <SelectItem value="info_richieste">Info richieste</SelectItem>
            <SelectItem value="risolta">Risolte</SelectItem>
            <SelectItem value="respinta">Respinte</SelectItem>
          </SelectContent>
        </Select>
        <p className="ml-auto text-xs text-muted-foreground">{filtrate.length} elementi</p>
      </div>

      {filtrate.length === 0 ? (
        <div className="rounded-2xl border border-dashed border-border bg-card p-10 text-center text-sm text-muted-foreground">
          Nessuna segnalazione in coda con i filtri correnti.
        </div>
      ) : (
        <ul className="space-y-2">
          {filtrate.map((r) => (
            <li key={r.id} className="rounded-2xl border border-border bg-card p-3">
              <button
                onClick={() => setSel(r)}
                className="grid w-full grid-cols-[1fr_auto] items-start gap-3 text-left"
              >
                <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-2 text-[11px]">
                    <PrioBadge p={r.priorita} />
                    <span className="rounded-full bg-secondary px-2 py-0.5 text-antracite">
                      {reportTargetLabel[r.targetType]}
                    </span>
                    {r.clubSlug && (
                      <span className="rounded-full bg-oro/20 px-2 py-0.5 text-antracite">
                        Club: {r.clubSlug}
                      </span>
                    )}
                    <span className="text-muted-foreground">{r.id}</span>
                  </div>
                  <p className="mt-1 truncate font-serif font-semibold">{r.targetLabel}</p>
                  <p className="text-xs text-muted-foreground">
                    {r.reason} — segnalato da {r.reporter}
                  </p>
                </div>
                <div className="flex flex-col items-end gap-1">
                  <span
                    className={`rounded-full px-2 py-0.5 text-[11px] font-medium ${reportStatusTone[r.stato]}`}
                  >
                    {reportStatusLabel[r.stato]}
                  </span>
                  <ChevronRight className="h-4 w-4 text-muted-foreground" />
                </div>
              </button>
            </li>
          ))}
        </ul>
      )}

      <ReportDetail report={sel} onClose={() => setSel(null)} />
    </div>
  );
}

function PrioBadge({ p }: { p: Priorita }) {
  const tone =
    p === "alta"
      ? "bg-bordeaux/15 text-bordeaux"
      : p === "media"
        ? "bg-oro/25 text-antracite"
        : "bg-salvia/15 text-salvia";
  return (
    <span className={`rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase ${tone}`}>
      {p}
    </span>
  );
}

function ReportDetail({ report, onClose }: { report: Report | null; onClose: () => void }) {
  const { applyModAction, addReportNote, assignReport, modScope } = useVinea();
  const isClub = typeof modScope === "object";
  const [motivazione, setMotivazione] = useState("");
  const [durata, setDurata] = useState("7 giorni");
  const [nota, setNota] = useState("");

  if (!report) return null;

  // azioni disponibili in base allo stato
  const closed = report.stato === "risolta" || report.stato === "respinta";
  const actions: ModAction[] = closed
    ? ["ripristino"]
    : [
        "richiesta_modifiche",
        "info_richieste",
        "ammonizione",
        "sospensione",
        "rimozione",
        "chiusura",
      ];

  function eseguiAzione(a: ModAction) {
    if (!motivazione.trim()) return;
    applyModAction({
      action: a,
      target: report!.targetLabel,
      motivazione,
      durata: a === "sospensione" ? durata : undefined,
      scope: isClub ? "club" : "piattaforma",
      clubSlug: isClub ? (modScope as { club: string }).club : report!.clubSlug,
      reportId: report!.id,
    });
    setMotivazione("");
    onClose();
  }

  return (
    <Dialog open={!!report} onOpenChange={(v) => !v && onClose()}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle className="font-serif text-xl">
            {report.id} — {reportTargetLabel[report.targetType]}
          </DialogTitle>
        </DialogHeader>

        <div className="grid gap-4 md:grid-cols-[1fr_240px]">
          <div className="space-y-3">
            <section className="rounded-xl border border-border bg-card p-3 text-sm">
              <p className="font-serif font-semibold">{report.targetLabel}</p>
              <p className="mt-1">
                Motivo: <b>{report.reason}</b>
              </p>
              {report.descrizione && (
                <p className="mt-1 text-muted-foreground">{report.descrizione}</p>
              )}
              <p className="mt-2 text-[11px] text-muted-foreground">
                Segnalato da {report.reporter} ·{" "}
                {new Date(report.createdAt).toLocaleString("it-IT")}
              </p>
              {report.foto.length > 0 && (
                <div className="mt-2 flex gap-1.5">
                  {report.foto.map((f) => (
                    <span
                      key={f}
                      className="grid h-14 w-14 place-items-center rounded-md border border-border bg-secondary text-[10px] text-muted-foreground"
                    >
                      {f}
                    </span>
                  ))}
                </div>
              )}
            </section>

            <section>
              <p className="mb-2 text-xs uppercase text-muted-foreground">Cronologia</p>
              <ol className="space-y-1.5 border-l border-border pl-4 text-xs">
                {report.storia.map((h, i) => (
                  <li key={i} className="relative">
                    <span className="absolute -left-[19px] top-1 h-2 w-2 rounded-full bg-bordeaux/70" />
                    <span className="text-muted-foreground">
                      {new Date(h.ts).toLocaleString("it-IT", {
                        day: "2-digit",
                        month: "short",
                        hour: "2-digit",
                        minute: "2-digit",
                      })}
                    </span>
                    <span className="mx-1">·</span>
                    <span>{h.testo}</span>
                    <span className="ml-1 text-muted-foreground">— {h.autore}</span>
                  </li>
                ))}
              </ol>
            </section>

            {!isClub && (
              <section>
                <p className="mb-2 text-xs uppercase text-muted-foreground">Note interne</p>
                {report.noteInterne.length === 0 ? (
                  <p className="text-xs text-muted-foreground">Nessuna nota interna.</p>
                ) : (
                  <ul className="space-y-1 text-xs">
                    {report.noteInterne.map((n, i) => (
                      <li key={i} className="rounded-md bg-secondary/60 p-2">
                        <span className="text-muted-foreground">
                          {new Date(n.ts).toLocaleString("it-IT")} — {n.autore}:
                        </span>{" "}
                        {n.testo}
                      </li>
                    ))}
                  </ul>
                )}
                <div className="mt-2 flex gap-2">
                  <Input
                    value={nota}
                    onChange={(e) => setNota(e.target.value)}
                    placeholder="Nota per il team…"
                    className="h-8 text-xs"
                  />
                  <Button
                    size="sm"
                    variant="outline"
                    disabled={!nota.trim()}
                    onClick={() => {
                      addReportNote(report.id, nota);
                      setNota("");
                    }}
                  >
                    Aggiungi
                  </Button>
                </div>
              </section>
            )}
          </div>

          <aside className="space-y-3">
            <div className="rounded-xl border border-border bg-card p-3 text-xs">
              <p className="mb-2 font-semibold">Metadati</p>
              <p>
                Priorità: <PrioBadge p={report.priorita} />
              </p>
              <p className="mt-1">
                Stato:{" "}
                <span
                  className={`rounded-full px-2 py-0.5 text-[10px] font-medium ${reportStatusTone[report.stato]}`}
                >
                  {reportStatusLabel[report.stato]}
                </span>
              </p>
              <p className="mt-2">
                Assegnata a: <b>{report.assignee ?? "—"}</b>
              </p>
              {!report.assignee && !isClub && (
                <Button
                  size="sm"
                  variant="outline"
                  className="mt-2 h-7 text-[11px]"
                  onClick={() => assignReport(report.id, "Mod. Vinea")}
                >
                  Prendi in carico
                </Button>
              )}
            </div>

            {!closed && (
              <div className="rounded-xl border border-border bg-card p-3 text-xs">
                <Label className="text-[11px] uppercase">Motivazione (obbligatoria)</Label>
                <Textarea
                  rows={3}
                  value={motivazione}
                  onChange={(e) => setMotivazione(e.target.value)}
                  placeholder="Perché stai eseguendo questa azione?"
                  className="mt-1 text-xs"
                />
                <div className="mt-2">
                  <Label className="text-[11px] uppercase">Durata (per sospensione)</Label>
                  <Select value={durata} onValueChange={setDurata}>
                    <SelectTrigger className="mt-1 h-8 text-xs">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="24 ore">24 ore</SelectItem>
                      <SelectItem value="7 giorni">7 giorni</SelectItem>
                      <SelectItem value="30 giorni">30 giorni</SelectItem>
                      <SelectItem value="Indefinita">Indefinita</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
              </div>
            )}
          </aside>
        </div>

        <DialogFooter className="flex-wrap gap-2">
          {actions.map((a) => (
            <ConfirmAction
              key={a}
              action={a}
              disabled={!motivazione.trim() && a !== "ripristino"}
              onConfirm={() => eseguiAzione(a)}
            />
          ))}
          <Button variant="ghost" onClick={onClose}>
            Chiudi
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function ConfirmAction({
  action,
  onConfirm,
  disabled,
}: {
  action: ModAction;
  onConfirm: () => void;
  disabled?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const Icon =
    action === "sospensione"
      ? PauseCircle
      : action === "rimozione"
        ? Trash2
        : action === "ripristino"
          ? RotateCcw
          : action === "ammonizione"
            ? AlertTriangle
            : action === "richiesta_modifiche"
              ? PencilLine
              : action === "info_richieste"
                ? MessageSquare
                : Check;

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button size="sm" variant="outline" disabled={disabled} className={modActionTone[action]}>
          <Icon className="h-3.5 w-3.5" /> {modActionLabel[action]}
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle className="font-serif text-lg">Confermi l'azione?</DialogTitle>
        </DialogHeader>
        <p className="text-sm">
          Stai per <b>{modActionLabel[action].toLowerCase()}</b>. Verrà registrata nell'audit log
          con la tua motivazione.
        </p>
        <p className="text-xs text-muted-foreground">
          L'utente segnalato potrà presentare ricorso (demo).
        </p>
        <DialogFooter>
          <Button variant="ghost" onClick={() => setOpen(false)}>
            Annulla
          </Button>
          <Button
            className="bg-bordeaux hover:bg-bordeaux/90"
            onClick={() => {
              onConfirm();
              setOpen(false);
            }}
          >
            Conferma
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// ------------------------ CONTROVERSIE ORDINI ------------------------

function Controversie() {
  const { orders, sales, resolveDispute } = useVinea();
  const tutti = [...orders, ...sales];
  const contest = tutti.filter((o) => !!o.dispute);

  if (contest.length === 0) {
    return (
      <div className="rounded-2xl border border-dashed border-border bg-card p-10 text-center text-sm text-muted-foreground">
        Nessuna controversia aperta al momento.
      </div>
    );
  }
  return (
    <ul className="space-y-3">
      {contest.map((o) => {
        const wine = wines.find((w) => w.id === o.wineId);
        const d = o.dispute!;
        return (
          <li key={o.id} className="rounded-2xl border border-border bg-card p-4">
            <div className="flex flex-wrap items-start gap-3">
              {wine && (
                <img
                  src={wine.immagini[0]}
                  alt=""
                  className="h-16 w-12 shrink-0 rounded object-cover"
                />
              )}
              <div className="min-w-0 flex-1">
                <p className="text-xs uppercase text-muted-foreground">
                  {o.id} ·{" "}
                  <span
                    className={`rounded-full px-2 py-0.5 text-[10px] ${colorBuyerStatus(o.buyerStatus)}`}
                  >
                    {labelBuyerStatus(o.buyerStatus)}
                  </span>
                </p>
                <p className="mt-0.5 truncate font-serif font-semibold">
                  {wine ? `${wine.nome} ${wine.annata}` : o.wineId}
                </p>
                <p className="text-xs text-muted-foreground">
                  Acquirente {o.buyer.nome} · Venditore {o.seller.nome} · Totale{" "}
                  {formatEUR(o.totale)}
                </p>
                <p className="mt-2 text-sm">
                  <b>Motivo:</b> {d.motivo}
                </p>
                {d.descrizione && <p className="text-sm text-muted-foreground">{d.descrizione}</p>}
                <p className="mt-1 text-[11px] text-muted-foreground">
                  Aperta il {new Date(d.aperturaTs).toLocaleString("it-IT")} · Prove:{" "}
                  {d.foto.length} (mock)
                </p>
              </div>
              <div className="flex flex-col gap-1">
                <Button asChild size="sm" variant="outline">
                  <Link to="/ordine/$id" params={{ id: o.id }}>
                    Dettaglio ordine
                  </Link>
                </Button>
              </div>
            </div>

            <div className="mt-3 flex flex-wrap gap-2">
              <Button
                size="sm"
                className="bg-salvia text-crema hover:bg-salvia/90"
                onClick={() => resolveDispute(o.id, "rimborsata", "Rimborso disposto dal team")}
              >
                Rimborsa acquirente
              </Button>
              <Button
                size="sm"
                variant="outline"
                onClick={() => resolveDispute(o.id, "risolta", "Accordo raggiunto")}
              >
                Segna risolta
              </Button>
              <Button
                size="sm"
                variant="outline"
                onClick={() => resolveDispute(o.id, "respinta", "Prove insufficienti")}
              >
                Respingi
              </Button>
            </div>
          </li>
        );
      })}
    </ul>
  );
}

// ------------------------ AUDIT LOG ------------------------

function AuditLog() {
  const { auditLog, modScope } = useVinea();
  const isClub = typeof modScope === "object";
  const list = isClub
    ? auditLog.filter(
        (e) => e.scope === "club" && e.clubSlug === (modScope as { club: string }).club,
      )
    : auditLog;

  if (list.length === 0) {
    return (
      <div className="rounded-2xl border border-dashed border-border bg-card p-10 text-center text-sm text-muted-foreground">
        Nessuna azione registrata.
      </div>
    );
  }
  return (
    <ol className="space-y-2">
      {list.map((e) => (
        <li
          key={e.id}
          className="grid grid-cols-[auto_1fr_auto] items-start gap-3 rounded-2xl border border-border bg-card p-3 text-sm"
        >
          <span
            className={`grid h-8 w-8 shrink-0 place-items-center rounded-full ${e.scope === "club" ? "bg-oro/20 text-antracite" : "bg-bordeaux/10 text-bordeaux"}`}
          >
            {e.scope === "club" ? (
              <UsersIcon className="h-4 w-4" />
            ) : (
              <Shield className="h-4 w-4" />
            )}
          </span>
          <div className="min-w-0">
            <p>
              <b>{e.attore}</b> — <span className="text-antracite">{modActionLabel[e.azione]}</span>{" "}
              su <b>{e.target}</b>
            </p>
            <p className="text-xs text-muted-foreground">
              {e.motivazione}
              {e.durata ? ` · durata ${e.durata}` : ""}
              {e.clubSlug ? ` · club ${e.clubSlug}` : ""}
            </p>
            {e.ricorso && e.ricorso !== "nessuno" && (
              <span className="mt-1 inline-block rounded-full bg-oro/15 px-2 py-0.5 text-[10px] text-oro">
                Ricorso: {e.ricorso}
              </span>
            )}
          </div>
          <span className="shrink-0 text-[11px] text-muted-foreground">
            {new Date(e.ts).toLocaleString("it-IT", {
              day: "2-digit",
              month: "short",
              hour: "2-digit",
              minute: "2-digit",
            })}
          </span>
        </li>
      ))}
    </ol>
  );
}
