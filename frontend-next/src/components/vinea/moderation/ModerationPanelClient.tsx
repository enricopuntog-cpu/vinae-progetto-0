"use client";

// Fase 9a/9b - pannello di moderazione.
//
// Tre schede come in frontend/src/routes/admin.tsx:158-168 — coda segnalazioni,
// controversie ordini, audit log. La scheda contestazioni non ha il selettore
// d'ambito piattaforma/club del mock, perche l'ambito club non e esprimibile:
// user_roles e (user_id, role) senza colonna d'ambito, e la decisione 7.1 ha
// rinviato il moderatore di club.
//
// Il 9b aggiunge i comandi. Due differenze dichiarate rispetto al mock:
//  * niente «Prendi in carico» — decisione 7.5, la coda e condivisa e la
//    colonna di assegnazione non esiste nemmeno a database;
//  * la motivazione e obbligatoria anche per il ripristino, che nel mock ne
//    faceva a meno (frontend/src/routes/admin.tsx:486). A database
//    audit_log.motivazione e NOT NULL con CHECK: l'eccezione del mock non e
//    riproducibile, e non e una regressione ma un vincolo che il mock non aveva.

import { useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Textarea } from "@/components/ui/textarea";
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
  modActionTone,
  reportStatusLabel,
  reportStatusTone,
  reportTargetLabel,
} from "@/data/moderation";
import type { AuditEntry, ModAction, Priorita, Report } from "@/data/moderation";
import type {
  AzionePraticaInput,
  DisputeQueueRow,
  EsitoContestazioneAdmin,
  TransizioneAnnuncio,
} from "@/services/phase9/supabase-moderation-service";

// Le sette azioni della decisione, nell'ordine in cui il mock le presenta.
const AZIONI: ModAction[] = [
  "info_richieste",
  "richiesta_modifiche",
  "ammonizione",
  "sospensione",
  "rimozione",
  "ripristino",
  "chiusura",
];

const DURATE = ["24 ore", "7 giorni", "30 giorni", "Indefinita"];

// Una pratica chiusa non si rilavora: le RPC la rifiutano con P0001, e mostrare
// comandi che il database respinge sarebbe un invito a un errore.
const chiusa = (report: Report) => report.stato === "risolta" || report.stato === "respinta";

const prioritaTono: Record<Priorita, string> = {
  alta: "bg-bordeaux/10 text-bordeaux",
  media: "bg-oro/20 text-antracite",
  bassa: "bg-muted text-muted-foreground",
};

const data = (iso: string) =>
  new Date(iso).toLocaleString("it-IT", { dateStyle: "medium", timeStyle: "short" });

const euro = (cents: number) =>
  new Intl.NumberFormat("it-IT", { style: "currency", currency: "EUR" }).format(cents / 100);

// ---------------------------------------------------------------------------
// Il dialogo delle azioni
// ---------------------------------------------------------------------------

// Montato solo quando una pratica e aperta, e con `key` sull'id: lo stato del
// modulo e locale, e un dialogo che sopravvive al cambio di pratica porterebbe
// la motivazione scritta per una sulla successiva.
type DialogoProps = {
  report: Report;
  inCorso: string | null;
  onChiudi: () => void;
  onAzione: (input: AzionePraticaInput) => Promise<void>;
  onTransizione: (
    listingId: string,
    transizione: TransizioneAnnuncio,
    motivazione: string,
  ) => Promise<void>;
};

const DialogoAzioni = ({
  report,
  inCorso,
  onChiudi,
  onAzione,
  onTransizione,
}: DialogoProps) => {
  const [motivazione, setMotivazione] = useState("");
  const [durata, setDurata] = useState(DURATE[1]);
  const [notaInterna, setNotaInterna] = useState("");

  const pronta = motivazione.trim().length > 0;
  const occupato = inCorso !== null;
  const suAnnuncio = report.targetType === "annuncio" && report.targetId.length > 0;

  const esegui = async (azione: ModAction) => {
    try {
      await onAzione({
        reportId: report.id,
        azione,
        motivazione,
        durata: azione === "sospensione" ? durata : undefined,
        notaInterna: notaInterna || undefined,
      });
      onChiudi();
    } catch {
      // L'errore e gia nello stato del controller e la pagina lo mostra: qui
      // conta solo non chiudere il dialogo, cosi il testo scritto non si perde.
    }
  };

  return (
    <Dialog open onOpenChange={(aperto) => !aperto && onChiudi()}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle className="font-serif text-xl">{report.targetLabel}</DialogTitle>
        </DialogHeader>

        <div className="space-y-3 text-sm">
          <p className="text-muted-foreground">
            {reportTargetLabel[report.targetType]} · {report.reason}
          </p>
          {report.descrizione ? <p>{report.descrizione}</p> : null}

          <div>
            <Label htmlFor="mod-motivazione" className="text-xs uppercase">
              Motivazione (obbligatoria)
            </Label>
            <Textarea
              id="mod-motivazione"
              rows={3}
              value={motivazione}
              onChange={(e) => setMotivazione(e.target.value)}
              placeholder="Perche stai eseguendo questa azione?"
              className="mt-1"
            />
          </div>

          <div>
            <Label htmlFor="mod-durata" className="text-xs uppercase">
              Durata (solo per la sospensione)
            </Label>
            <Select value={durata} onValueChange={setDurata}>
              <SelectTrigger id="mod-durata" className="mt-1">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {DURATE.map((d) => (
                  <SelectItem key={d} value={d}>
                    {d}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div>
            <Label htmlFor="mod-nota" className="text-xs uppercase">
              Nota interna (facoltativa, mai visibile al segnalante)
            </Label>
            <Textarea
              id="mod-nota"
              rows={2}
              value={notaInterna}
              onChange={(e) => setNotaInterna(e.target.value)}
              className="mt-1"
            />
          </div>

          {suAnnuncio ? (
            <Button
              variant="outline"
              size="sm"
              disabled={!pronta || occupato}
              onClick={() => {
                void onTransizione(report.targetId, "in_revisione", motivazione).then(
                  onChiudi,
                  () => {},
                );
              }}
            >
              Metti l&apos;annuncio in revisione
            </Button>
          ) : null}
        </div>

        <DialogFooter className="flex-wrap gap-2">
          {AZIONI.map((azione) => (
            <Button
              key={azione}
              variant="outline"
              size="sm"
              className={modActionTone[azione]}
              disabled={!pronta || occupato}
              onClick={() => void esegui(azione)}
            >
              {modActionLabel[azione]}
            </Button>
          ))}
          <Button variant="ghost" size="sm" onClick={onChiudi}>
            Chiudi
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};

const RigaSegnalazione = ({
  report,
  onApri,
}: {
  report: Report;
  onApri: ((report: Report) => void) | null;
}) => (
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

    {onApri && !chiusa(report) ? (
      <Button variant="outline" size="sm" onClick={() => onApri(report)}>
        Azioni di moderazione
      </Button>
    ) : null}
  </Card>
);

// D10. Una pratica si lavora finche e aperta o in valutazione: gli altri tre
// stati sono terminali, e la porta li rifiuta uscendo senza scrivere. Mostrare
// comandi che il database ignora sarebbe la stessa promessa vuota che `chiusa`
// evita per le segnalazioni.
const contestazioneLavorabile = (riga: DisputeQueueRow) =>
  riga.stato === "aperta" || riga.stato === "in_valutazione";

const RigaContestazione = ({
  riga,
  inCorso,
  onRisolvi,
}: {
  riga: DisputeQueueRow;
  inCorso: string | null;
  onRisolvi: ((orderId: string, esito: EsitoContestazioneAdmin, nota: string) => Promise<void>) | null;
}) => {
  const [nota, setNota] = useState("");
  const pronta = nota.trim().length > 0;
  // `inCorso` e la chiave dell'azione in volo, per ordine. Non un booleano
  // locale: la coda ha piu righe, e il controller la spegne da solo quando la
  // rilettura e finita — cosi il pulsante non si riaccende prima dei dati.
  const occupato = inCorso !== null;
  const lavorabile = contestazioneLavorabile(riga);

  const esegui = async (esito: EsitoContestazioneAdmin) => {
    if (!onRisolvi || !pronta || occupato) return;
    try {
      await onRisolvi(riga.orderId, esito, nota);
      setNota("");
    } catch {
      // L'errore e gia nello stato del controller e la pagina lo mostra. Qui
      // conta solo non azzerare la nota: chi riprova non deve riscriverla.
    }
  };

  return (
    <Card className="space-y-2 p-4" data-testid={`controversia-${riga.orderId}`}>
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

      {onRisolvi && lavorabile ? (
        <div className="space-y-2 border-t pt-3">
          <Label htmlFor={`controversia-nota-${riga.orderId}`} className="text-xs uppercase">
            Motivazione (obbligatoria)
          </Label>
          <Textarea
            id={`controversia-nota-${riga.orderId}`}
            data-testid={`controversia-nota-${riga.orderId}`}
            rows={2}
            value={nota}
            onChange={(e) => setNota(e.target.value)}
            placeholder="Perche stai chiudendo questa controversia?"
            disabled={occupato}
          />
          <div className="flex flex-wrap gap-2">
            <Button
              variant="outline"
              size="sm"
              data-testid={`controversia-risolvi-${riga.orderId}`}
              disabled={!pronta || occupato}
              onClick={() => void esegui("risolta")}
            >
              {inCorso === `${riga.orderId}:risolta` ? "Risoluzione…" : "Risolvi"}
            </Button>
            <Button
              variant="outline"
              size="sm"
              data-testid={`controversia-respingi-${riga.orderId}`}
              disabled={!pronta || occupato}
              onClick={() => void esegui("respinta")}
            >
              {inCorso === `${riga.orderId}:respinta` ? "Rifiuto…" : "Respingi"}
            </Button>
          </div>
          {/*
            Nessun terzo pulsante. `rimborsata` non e nella firma della porta
            browser-admin: finche refund e provider restano spenti, disporre un
            rimborso e una leva di back-office. Il testo lo dice invece di
            lasciare un vuoto che sembra una dimenticanza.
          */}
          <p className="text-xs text-muted-foreground">
            Il rimborso non si dispone da qui: resta al back-office finche i pagamenti sono spenti.
          </p>
        </div>
      ) : null}
    </Card>
  );
};

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
  // D10: `authRuolo` e non `ruolo`. Il secondo, con lo switcher demo acceso, e
  // quello scelto a mano nel selettore Guest/User/Admin: leggerlo qui
  // significava che chiunque potesse scegliere «Admin» e vedere il pannello -
  // vuoto, perche il database non gli dava righe, ma aperto. Il primo viene da
  // `user_roles` e il selettore non lo tocca.
  //
  // Il cancello vero resta comunque a database: le viste `moderation_*` sono
  // `security_invoker = off` e filtrano su `user_roles`, e ogni RPC di
  // moderazione rifiuta con 42501. Questo e cio che si mostra, non cio che si
  // autorizza. La route `/admin` fa la stessa verifica sul server, prima di
  // rendere.
  const { authRuolo } = useVinea();
  const online = useOnline();
  const [tab, setTab] = useState("coda");
  const [aperta, setAperta] = useState<Report | null>(null);
  const moderatore = authRuolo === "admin";
  const {
    coda,
    audit,
    contestazioni,
    loading,
    error,
    reload,
    agisci,
    transizioneAnnuncio,
    risolviControversia,
    inCorso,
  } = usePhase9Moderation({ moderatore });

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

      {error ? (
        <p className="rounded-md border border-bordeaux/40 bg-bordeaux/5 p-3 text-sm text-bordeaux">
          {error}
        </p>
      ) : null}

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
            coda.map((report) => (
              <RigaSegnalazione
                key={report.id}
                report={report}
                onApri={agisci ? setAperta : null}
              />
            ))
          )}
        </TabsContent>

        <TabsContent value="controversie" className="space-y-3">
          {contestazioni.length === 0 ? (
            <EmptyState title="Nessuna controversia" message="Nessuna pratica aperta." />
          ) : (
            contestazioni.map((riga) => (
              <RigaContestazione
                key={riga.id}
                riga={riga}
                inCorso={inCorso}
                onRisolvi={risolviControversia}
              />
            ))
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

      {agisci && transizioneAnnuncio && aperta ? (
        <DialogoAzioni
          key={aperta.id}
          report={aperta}
          inCorso={inCorso}
          onChiudi={() => setAperta(null)}
          onAzione={agisci}
          onTransizione={transizioneAnnuncio}
        />
      ) : null}
    </div>
  );
};
