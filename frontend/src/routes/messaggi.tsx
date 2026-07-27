import { createFileRoute, Link } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import { Send, ArrowLeft, MoreHorizontal, Flag, Ban, HandCoins } from "lucide-react";
import { messagesMock, wines } from "@/data/wines";
import { systemThreadDemo, type SystemMessage } from "@/data/extra";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { toast } from "sonner";
import { useVinea, formatEUR } from "@/lib/vinea-store";
import { ReportDialog } from "@/components/vinea/ReportDialog";

export const Route = createFileRoute("/messaggi")({
  head: () => ({
    meta: [
      { title: "Messaggi — Vinea" },
      { name: "description", content: "Le tue conversazioni con acquirenti e venditori Vinea." },
      { property: "og:title", content: "Messaggi — Vinea" },
      {
        property: "og:description",
        content: "Scrivi al venditore, invia proposte e ricevi controproposte.",
      },
    ],
  }),
  component: Messaggi,
});

function Messaggi() {
  const { proponi } = useVinea();
  const [attiva, setAttiva] = useState<string | null>(null);
  const [testo, setTesto] = useState("");
  const [msgs, setMsgs] = useState<Record<string, SystemMessage[]>>({
    m1: systemThreadDemo,
    m2: [
      { me: false, t: "Grazie della proposta, accetto a 250 €.", ora: "ieri" },
      { sistema: true, me: false, t: "Hai inviato una proposta di 240 €", ora: "ieri" },
      { sistema: true, me: false, t: "La proposta è stata accettata", ora: "ieri" },
    ],
    m3: [{ me: false, t: "Il Dom Pérignon è ancora disponibile?", ora: "lun" }],
  });

  const conv = messagesMock.find((m) => m.id === attiva);
  const wine = conv ? wines.find((w) => w.id === conv.wineId) : undefined;
  const lista = attiva ? (msgs[attiva] ?? []) : [];

  const invia = () => {
    if (!attiva || !testo.trim()) return;
    const t = testo;
    setMsgs((p) => ({ ...p, [attiva]: [...(p[attiva] ?? []), { me: true, t, ora: "ora" }] }));
    setTesto("");
    setTimeout(() => {
      setMsgs((p) => ({
        ...p,
        [attiva]: [
          ...(p[attiva] ?? []),
          { me: false, t: "Grazie, ti rispondo a breve.", ora: "ora" },
        ],
      }));
    }, 900);
  };

  return (
    <div className="space-y-4">
      <h1 className="font-serif text-3xl md:text-4xl">Messaggi</h1>
      <div className="grid gap-4 md:grid-cols-[300px_1fr]">
        <aside
          className={`rounded-2xl border border-border bg-card overflow-hidden ${attiva ? "hidden md:block" : ""}`}
        >
          <ul>
            {messagesMock.map((m) => (
              <li key={m.id}>
                <button
                  onClick={() => setAttiva(m.id)}
                  className={`flex w-full items-center gap-3 border-b border-border p-3 text-left last:border-0 ${attiva === m.id ? "bg-secondary" : ""}`}
                >
                  <img src={m.avatar} alt="" className="h-10 w-10 rounded-full" />
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center justify-between gap-2">
                      <p className="truncate font-semibold text-sm">{m.utente}</p>
                      <span className="text-[10px] text-muted-foreground">{m.tempo}</span>
                    </div>
                    <p className="truncate text-xs text-muted-foreground">{m.ultimo}</p>
                  </div>
                  {m.nonLetti > 0 && (
                    <span className="grid h-5 min-w-5 place-items-center rounded-full bg-bordeaux px-1 text-[10px] text-crema">
                      {m.nonLetti}
                    </span>
                  )}
                </button>
              </li>
            ))}
          </ul>
        </aside>

        {!attiva ? (
          <section className="hidden min-h-[500px] flex-col items-center justify-center rounded-2xl border border-border bg-card p-8 text-center text-muted-foreground md:flex">
            <p className="font-serif text-xl">Seleziona una conversazione</p>
            <p className="text-sm">I dettagli dell'annuncio collegato appariranno qui.</p>
          </section>
        ) : (
          <section className="flex min-h-[500px] flex-col rounded-2xl border border-border bg-card">
            <header className="flex items-center gap-3 border-b border-border p-3">
              <button
                onClick={() => setAttiva(null)}
                className="rounded-full p-1 hover:bg-secondary md:hidden"
                aria-label="Indietro"
              >
                <ArrowLeft className="h-4 w-4" />
              </button>
              <img src={conv!.avatar} alt="" className="h-10 w-10 rounded-full" />
              <div className="min-w-0 flex-1">
                <p className="font-semibold">{conv!.utente}</p>
                {wine && (
                  <Link
                    to="/annuncio/$id"
                    params={{ id: wine.id }}
                    className="truncate text-xs text-muted-foreground hover:underline"
                  >
                    Annuncio: {wine.nome} {wine.annata} — {formatEUR(wine.prezzo)}
                  </Link>
                )}
              </div>
              <ProposalDialog
                onSubmit={(p) => {
                  if (wine) proponi(wine.id, p);
                  setMsgs((prev) => ({
                    ...prev,
                    [attiva]: [
                      ...(prev[attiva] ?? []),
                      {
                        sistema: true,
                        me: false,
                        t: `Hai inviato una proposta di ${p} €`,
                        ora: "ora",
                      },
                    ],
                  }));
                }}
              />
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <button className="rounded-full p-2 hover:bg-secondary" aria-label="Altro">
                    <MoreHorizontal className="h-4 w-4" />
                  </button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end">
                  <DropdownMenuItem asChild>
                    <ReportDialog
                      targetType="conversazione"
                      targetId={conv!.id}
                      targetLabel={`Conversazione con ${conv!.utente}`}
                      trigger={
                        <div className="flex w-full items-center gap-2">
                          <Flag className="h-4 w-4" /> Segnala conversazione
                        </div>
                      }
                    />
                  </DropdownMenuItem>
                  <DropdownMenuItem onClick={() => toast("Utente bloccato")}>
                    <Ban className="h-4 w-4" /> Blocca
                  </DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>
            </header>

            {wine && (
              <Link
                to="/annuncio/$id"
                params={{ id: wine.id }}
                className="flex items-center gap-3 border-b border-border bg-crema/60 p-3 hover:bg-crema"
              >
                <img src={wine.immagini[0]} alt="" className="h-12 w-9 rounded object-cover" />
                <div className="min-w-0 flex-1">
                  <p className="text-[11px] uppercase tracking-wide text-salvia">
                    Annuncio collegato
                  </p>
                  <p className="truncate font-serif font-semibold">
                    {wine.nome} {wine.annata}
                  </p>
                </div>
                <span className="font-serif text-lg font-semibold text-bordeaux">
                  {formatEUR(wine.prezzo)}
                </span>
              </Link>
            )}

            <div className="flex-1 space-y-3 overflow-y-auto p-4">
              {lista.map((m, i) =>
                m.sistema ? (
                  <div key={i} className="flex justify-center">
                    <span className="rounded-full bg-secondary px-3 py-1 text-[11px] text-muted-foreground">
                      {m.t} • {m.ora}
                    </span>
                  </div>
                ) : (
                  <div key={i} className={`flex ${m.me ? "justify-end" : "justify-start"}`}>
                    <div
                      className={`max-w-[75%] rounded-2xl px-4 py-2 text-sm ${m.me ? "bg-bordeaux text-crema" : "bg-secondary"}`}
                    >
                      {m.t}
                      <span className="ml-2 text-[10px] opacity-60">{m.ora}</span>
                    </div>
                  </div>
                ),
              )}
            </div>
            <div className="flex gap-2 border-t border-border p-3">
              <Input
                value={testo}
                onChange={(e) => setTesto(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter") invia();
                }}
                placeholder="Scrivi un messaggio…"
              />
              <Button className="bg-bordeaux hover:bg-bordeaux/90" onClick={invia}>
                <Send className="h-4 w-4" />
              </Button>
            </div>
          </section>
        )}
      </div>
    </div>
  );
}

function ProposalDialog({ onSubmit }: { onSubmit: (p: number) => void }) {
  const [v, setV] = useState("180");
  const [open, setOpen] = useState(false);
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button size="sm" variant="outline" className="border-oro/60">
          <HandCoins className="h-4 w-4" /> Proposta
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Invia una proposta economica</DialogTitle>
        </DialogHeader>
        <label className="text-sm">
          Prezzo proposto (€)
          <Input type="number" value={v} onChange={(e) => setV(e.target.value)} className="mt-1" />
        </label>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)}>
            Annulla
          </Button>
          <Button
            className="bg-bordeaux hover:bg-bordeaux/90"
            onClick={() => {
              onSubmit(Number(v) || 0);
              setOpen(false);
            }}
          >
            Invia proposta
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
