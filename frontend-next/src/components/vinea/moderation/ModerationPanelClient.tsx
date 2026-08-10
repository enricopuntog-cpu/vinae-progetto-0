"use client";

// Fase 9a - pannello di moderazione, SOLA LETTURA.
//
// Tre schede come in frontend/src/routes/admin.tsx:158-168 — coda segnalazioni,
// controversie ordini, audit log. Nessun comando: i sette bottoni di azione e
// il dialogo di conferma sono il checkpoint 9b. La scheda contestazioni non ha
// il selettore d'ambito piattaforma/club del mock, perche l'ambito club non e
// esprimibile: user_roles e (user_id, role) senza colonna d'ambito, e la
// decisione 7.1 ha rinviato il moderatore di club.

import { useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  EmptyState,
  ErrorState,
  LoadingBlock,
  OfflineState,
  PermissionDeniedState,
  useOnline,
} from "@/components/vinea/States";
import { usePhase9Moderation } from "@/lib/phase9/use-phase9-moderation";
import { useVinea } from "@/lib/vinea-store";
import {
  modActionLabel,
  reportStatusLabel,
  reportStatusTone,
  reportTargetLabel,
} from "@/data/moderation";
import type { AuditEntry, Priorita, Report } from "@/data/moderation";
import type { DisputeQueueRow } from "@/services/phase9/supabase-moderation-service";

const prioritaTono: Record<Priorita, string> = {
  alta: "bg-bordeaux/10 text-bordeaux",
  media: "bg-oro/20 text-antracite",
  bassa: "bg-muted text-muted-foreground",
};

const data = (iso: string) =>
  new Date(iso).toLocaleString("it-IT", { dateStyle: "medium", timeStyle: "short" });

const euro = (cents: number) =>
  new Intl.NumberFormat("it-IT", { style: "currency", currency: "EUR" }).format(cents / 100);

const RigaSegnalazione = ({ report }: { report: Report }) => (
  <Card className="space-y-3 p-4">
    <div className="flex flex-wrap items-start justify-between gap-2">
      <div>
        <p className="font-medium">{report.targetLabel}</p>
        <p className="text-sm text-muted-foreground">
          {reportTargetLabel[report.targetType]} · {report.reason}
        </p>
      </div>
      <div className="flex flex-wrap gap-2">
        <Badge className={prioritaTono[report.priorita]}>{report.priorita}</Badge>
        <Badge className={reportStatusTone[report.stato]}>{reportStatusLabel[report.stato]}</Badge>
      </div>
    </div>

    {report.descrizione ? <p className="text-sm">{report.descrizione}</p> : null}

    <p className="text-xs text-muted-foreground">
      {/* Decisione 7.4: il segnalante e visibile al moderatore e non al segnalato. */}
      Segnalata da {report.reporter || "utente"} il {data(report.createdAt)}
    </p>

    {report.storia.length > 0 ? (
      <ol className="space-y-1 border-l pl-3 text-xs text-muted-foreground">
        {report.storia.map((voce) => (
          <li key={`${voce.ts}-${voce.testo}`}>
            <span className="font-medium">{voce.autore}</span> · {voce.testo}
          </li>
        ))}
      </ol>
    ) : null}

    {report.noteInterne.length > 0 ? (
      <div className="rounded-md bg-secondary p-2 text-xs">
        <p className="mb-1 font-medium">Note interne</p>
        <ol className="space-y-1">
          {report.noteInterne.map((voce) => (
            <li key={`${voce.ts}-${voce.testo}`}>{voce.testo}</li>
          ))}
        </ol>
      </div>
    ) : null}
  </Card>
);

const RigaContestazione = ({ riga }: { riga: DisputeQueueRow }) => (
  <Card className="space-y-2 p-4">
    <div className="flex flex-wrap items-start justify-between gap-2">
      <div>
        <p className="font-medium">{riga.motivo}</p>
        <p className="text-sm text-muted-foreground">
          {riga.apertaDaUsername} contro {riga.sellerUsername}
        </p>
      </div>
      <div className="flex flex-wrap gap-2">
        <Badge>{riga.stato}</Badge>
        <Badge className="bg-muted text-muted-foreground">payout {riga.ordinePayoutStato}</Badge>
      </div>
    </div>
    {riga.descrizione ? <p className="text-sm">{riga.descrizione}</p> : null}
    <p className="text-xs text-muted-foreground">
      {/* I due totali restano distinti: l'imballaggio della 7c e nel secondo. */}
      Ordine {euro(riga.totaleCents)} · addebitato {euro(riga.addebitoTotaleCents)} · aperta il{" "}
      {data(riga.aperturaAt)}
    </p>
    {riga.esitoNota ? <p className="text-xs">Esito: {riga.esitoNota}</p> : null}
  </Card>
);

const RigaAudit = ({ voce }: { voce: AuditEntry }) => (
  <Card className="space-y-1 p-4">
    <div className="flex flex-wrap items-center justify-between gap-2">
      <p className="font-medium">{modActionLabel[voce.azione]}</p>
      <Badge className="bg-muted text-muted-foreground">{voce.scope}</Badge>
    </div>
    <p className="text-sm">{voce.target}</p>
    <p className="text-sm text-muted-foreground">{voce.motivazione}</p>
    <p className="text-xs text-muted-foreground">
      {voce.attore} · {data(voce.ts)}
      {voce.durata ? ` · durata ${voce.durata}` : ""}
    </p>
  </Card>
);

export const ModerationPanelClient = () => {
  const { ruolo } = useVinea();
  const online = useOnline();
  const [tab, setTab] = useState("coda");
  const moderatore = ruolo === "admin";
  const { mode, coda, audit, contestazioni, loading, error, reload } = usePhase9Moderation({
    moderatore,
  });

  // Stesso cancello di frontend/src/routes/admin.tsx:73-84. Il gate vero resta
  // comunque nel database: senza il ruolo admin le proiezioni non restituiscono
  // righe, quindi nascondere la pagina e comodita, non sicurezza.
  if (!moderatore) {
    return (
      <PermissionDeniedState message="Il pannello di moderazione e riservato al team Vinea." />
    );
  }
  if (!online && coda.length === 0) return <OfflineState onRetry={() => void reload()} />;
  if (loading && coda.length === 0) return <LoadingBlock label="Caricamento moderazione" />;
  if (error && coda.length === 0) return <ErrorState message={error} onRetry={() => void reload()} />;

  return (
    <div className="space-y-6">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="font-serif text-3xl md:text-4xl">Moderazione</h1>
          <p className="text-muted-foreground">
            {coda.length} segnalazioni · {contestazioni.length} controversie
          </p>
        </div>
        <Button variant="outline" onClick={() => void reload()} disabled={!online}>
          Aggiorna
        </Button>
      </header>

      {/* Il checkpoint 9a e dichiaratamente in sola lettura: dirlo in pagina
          evita che l'assenza dei comandi sembri un guasto. */}
      <p className="rounded-md border border-dashed p-3 text-sm text-muted-foreground">
        Sola lettura. Le azioni di moderazione arrivano con il checkpoint 9b.
        {mode === "mock" ? " Dati dimostrativi: Supabase non e configurato." : ""}
      </p>

      <Tabs value={tab} onValueChange={setTab}>
        <TabsList>
          <TabsTrigger value="coda">Coda</TabsTrigger>
          <TabsTrigger value="controversie">Controversie</TabsTrigger>
          <TabsTrigger value="audit">Audit log</TabsTrigger>
        </TabsList>

        <TabsContent value="coda" className="space-y-3">
          {coda.length === 0 ? (
            <EmptyState title="Nessuna segnalazione" message="La coda e vuota." />
          ) : (
            coda.map((report) => <RigaSegnalazione key={report.id} report={report} />)
          )}
        </TabsContent>

        <TabsContent value="controversie" className="space-y-3">
          {contestazioni.length === 0 ? (
            <EmptyState title="Nessuna controversia" message="Nessuna pratica aperta." />
          ) : (
            contestazioni.map((riga) => <RigaContestazione key={riga.id} riga={riga} />)
          )}
        </TabsContent>

        <TabsContent value="audit" className="space-y-3">
          {audit.length === 0 ? (
            <EmptyState title="Registro vuoto" message="Nessuna azione registrata." />
          ) : (
            audit.map((voce) => <RigaAudit key={voce.id} voce={voce} />)
          )}
        </TabsContent>
      </Tabs>
    </div>
  );
};
