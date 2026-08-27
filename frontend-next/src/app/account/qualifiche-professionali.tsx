"use client";

import { useEffect, useRef, useState } from "react";
import { BadgeCheck, Paperclip, RefreshCcw, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { professionalQualificationService } from "@/services/professional-qualification-service";
import {
  etichettaStatoQualifica,
  qualificaInviabile,
  qualificaRitirabile,
  spiegazioneStato,
} from "@/lib/qualifiche/etichette";
import { MIME_DOCUMENTO_QUALIFICA } from "@/lib/qualifiche/validazione";
import type { QualificaDocumento, QualificaProfessionale } from "@/services/types";

/**
 * Le qualifiche professionali di chi è collegato.
 *
 * FAIL-SOFT: stato di caricamento, errore e mutazioni vivono qui dentro e non
 * toccano il resto di /account. Se questa lettura fallisce, l'editor del
 * profilo e le altre sezioni restano usabili — la sezione mostra il suo errore
 * e offre di riprovare, e basta.
 *
 * QUI NON SI APPROVA NIENTE. Non esiste un comando che decida un esito: il
 * browser prepara, allega e invia, e da lì in poi guarda. Non viene mostrato
 * nulla della verifica — né fornitore, né modello, né confidenza, né
 * ragionamento — perché il client non li riceve affatto.
 */

const Card = ({ children, className = "" }: { children: React.ReactNode; className?: string }) => (
  <div className={`rounded-2xl border border-border bg-card p-5 md:p-6 ${className}`}>{children}</div>
);

const CAMPI_VUOTI = {
  titolo: "",
  enteEmittente: "",
  paese: "",
  credentialReference: "",
  issuedOn: "",
  expiresOn: "",
};

export default function QualificheProfessionali() {
  const [qualifiche, setQualifiche] = useState<QualificaProfessionale[]>([]);
  const [caricamento, setCaricamento] = useState(true);
  const [errore, setErrore] = useState<string | null>(null);
  const [campi, setCampi] = useState(CAMPI_VUOTI);
  const [erroreForm, setErroreForm] = useState<string | null>(null);
  const [inCorso, setInCorso] = useState(false);
  const [erroreAzione, setErroreAzione] = useState<string | null>(null);
  const bozzaInAllegato = useRef<string | null>(null);
  const selettoreFile = useRef<HTMLInputElement | null>(null);

  const carica = async () => {
    setCaricamento(true);
    setErrore(null);
    try {
      const esito = await professionalQualificationService().elenco();
      if (esito.ok) setQualifiche(esito.data);
      else setErrore(esito.error);
    } catch {
      setErrore("Non è stato possibile leggere le tue qualifiche.");
    }
    setCaricamento(false);
  };

  useEffect(() => {
    let attivo = true;

    professionalQualificationService()
      .elenco()
      .then((esito) => {
        if (!attivo) return;
        if (esito.ok) setQualifiche(esito.data);
        else setErrore(esito.error);
        setCaricamento(false);
      })
      .catch(() => {
        if (!attivo) return;
        setErrore("Non è stato possibile leggere le tue qualifiche.");
        setCaricamento(false);
      });

    return () => {
      attivo = false;
    };
  }, []);

  const creaBozza = async () => {
    setErroreForm(null);
    setInCorso(true);
    const esito = await professionalQualificationService().crea({
      titolo: campi.titolo,
      enteEmittente: campi.enteEmittente,
      paese: campi.paese === "" ? null : campi.paese,
      credentialReference: campi.credentialReference === "" ? null : campi.credentialReference,
      issuedOn: campi.issuedOn === "" ? null : campi.issuedOn,
      expiresOn: campi.expiresOn === "" ? null : campi.expiresOn,
    });
    setInCorso(false);
    if (!esito.ok) {
      setErroreForm(esito.error);
      return;
    }
    setCampi(CAMPI_VUOTI);
    await carica();
  };

  const scegliDocumento = (qualificationId: string) => {
    bozzaInAllegato.current = qualificationId;
    selettoreFile.current?.click();
  };

  const allegaDocumento = async (file: File | undefined) => {
    const qualificationId = bozzaInAllegato.current;
    bozzaInAllegato.current = null;
    if (selettoreFile.current) selettoreFile.current.value = "";
    if (!file || !qualificationId) return;

    setErroreAzione(null);
    setInCorso(true);
    const esito = await professionalQualificationService().caricaDocumento(qualificationId, file);
    setInCorso(false);
    if (!esito.ok) {
      setErroreAzione(esito.error);
      return;
    }
    await carica();
  };

  const eliminaDocumento = async (documento: QualificaDocumento) => {
    setErroreAzione(null);
    setInCorso(true);
    const esito = await professionalQualificationService().eliminaDocumento(documento);
    setInCorso(false);
    if (!esito.ok) {
      setErroreAzione(esito.error);
      return;
    }
    await carica();
  };

  const invia = async (id: string) => {
    setErroreAzione(null);
    setInCorso(true);
    const esito = await professionalQualificationService().invia(id);
    setInCorso(false);
    if (!esito.ok) {
      setErroreAzione(esito.error);
      return;
    }
    await carica();
  };

  const ritira = async (id: string) => {
    setErroreAzione(null);
    setInCorso(true);
    const esito = await professionalQualificationService().ritira(id);
    setInCorso(false);
    if (!esito.ok) {
      setErroreAzione(esito.error);
      return;
    }
    await carica();
  };

  return (
    <section className="space-y-6" data-testid="qualifiche-professionali">
      <header>
        <h2 className="font-serif text-2xl md:text-3xl">Qualifiche professionali</h2>
        <p className="text-sm text-muted-foreground mt-1">
          Titoli rilasciati da enti terzi — sommelier, enologo, agronomo e simili. Vinea non
          rilascia la qualifica: legge i documenti che la attestano e mostra sul tuo profilo
          pubblico soltanto quelle approvate e non scadute.
        </p>
      </header>

      {caricamento && qualifiche.length === 0 && (
        <Card>
          <p className="text-sm text-muted-foreground">Carico le tue qualifiche…</p>
        </Card>
      )}

      {errore && (
        <Card className="border-red-200 bg-red-50/40">
          <p className="text-sm text-red-700">{errore}</p>
          <Button size="sm" variant="outline" className="mt-3" onClick={carica}>
            <RefreshCcw className="h-3.5 w-3.5 mr-1.5" /> Riprova
          </Button>
        </Card>
      )}

      {!errore && !caricamento && qualifiche.length === 0 && (
        <Card>
          <p className="text-sm text-muted-foreground">
            Non hai ancora aggiunto nessuna qualifica.
          </p>
        </Card>
      )}

      {qualifiche.length > 0 && (
        <Card>
          <ul className="divide-y divide-border">
            {qualifiche.map((q) => {
              const spiegazione = spiegazioneStato(q);
              return (
                <li key={q.id} className="py-4 first:pt-0 last:pb-0 space-y-2">
                  <div className="flex flex-wrap items-start justify-between gap-3">
                    <div className="min-w-0">
                      <p className="flex items-center gap-1.5 text-sm font-medium break-words">
                        {q.titolo}
                        {q.valida && (
                          <BadgeCheck
                            className="h-4 w-4 shrink-0 text-emerald-700"
                            aria-hidden="true"
                          />
                        )}
                      </p>
                      <p className="text-xs text-muted-foreground break-words">
                        {q.enteEmittente}
                        {q.paese ? ` · ${q.paese}` : ""}
                      </p>
                    </div>
                    <span className="shrink-0 rounded-full border border-border px-2.5 py-1 text-xs">
                      {etichettaStatoQualifica(q.stato)}
                    </span>
                  </div>

                  {spiegazione && <p className="text-xs text-muted-foreground">{spiegazione}</p>}

                  {q.stato === "bozza" && (
                    <div className="space-y-2">
                      {q.documenti.length === 0 ? (
                        <p className="text-xs text-muted-foreground">
                          Allega almeno un documento prima di inviare.
                        </p>
                      ) : (
                        <ul className="space-y-1">
                          {q.documenti.map((d, indice) => (
                            <li
                              key={d.id}
                              className="flex items-center justify-between gap-3 text-xs text-muted-foreground"
                            >
                              <span>
                                Documento {indice + 1} · {Math.round(d.sizeBytes / 1024)} KB
                              </span>
                              <Button
                                size="sm"
                                variant="ghost"
                                onClick={() => eliminaDocumento(d)}
                                disabled={inCorso}
                                aria-label={`Elimina documento ${indice + 1}`}
                              >
                                <Trash2 className="h-3.5 w-3.5" />
                              </Button>
                            </li>
                          ))}
                        </ul>
                      )}
                    </div>
                  )}

                  <div className="flex flex-wrap gap-2">
                    {q.stato === "bozza" && (
                      <Button
                        size="sm"
                        variant="outline"
                        onClick={() => scegliDocumento(q.id)}
                        disabled={inCorso}
                      >
                        <Paperclip className="h-3.5 w-3.5 mr-1.5" /> Allega documento
                      </Button>
                    )}
                    {qualificaInviabile(q) && (
                      <Button size="sm" onClick={() => invia(q.id)} disabled={inCorso}>
                        Invia per la verifica
                      </Button>
                    )}
                    {qualificaRitirabile(q) && (
                      <Button
                        size="sm"
                        variant="outline"
                        onClick={() => ritira(q.id)}
                        disabled={inCorso}
                      >
                        Ritira
                      </Button>
                    )}
                  </div>
                </li>
              );
            })}
          </ul>
          {erroreAzione && <p className="mt-4 text-sm text-red-700">{erroreAzione}</p>}
        </Card>
      )}

      <input
        ref={selettoreFile}
        type="file"
        className="hidden"
        accept={MIME_DOCUMENTO_QUALIFICA.join(",")}
        onChange={(e) => allegaDocumento(e.target.files?.[0])}
        data-testid="qualifiche-file"
      />

      <Card>
        <h3 className="font-serif text-xl mb-4">Nuova qualifica</h3>
        <div className="grid gap-3 sm:grid-cols-2">
          <label className="block text-sm">
            <span className="font-medium">Titolo</span>
            <input
              value={campi.titolo}
              onChange={(e) => setCampi({ ...campi, titolo: e.target.value })}
              disabled={inCorso}
              className="mt-1 w-full rounded-xl border border-border bg-background px-3 py-2 text-sm"
            />
          </label>
          <label className="block text-sm">
            <span className="font-medium">Ente che l’ha rilasciata</span>
            <input
              value={campi.enteEmittente}
              onChange={(e) => setCampi({ ...campi, enteEmittente: e.target.value })}
              disabled={inCorso}
              className="mt-1 w-full rounded-xl border border-border bg-background px-3 py-2 text-sm"
            />
          </label>
          <label className="block text-sm">
            <span className="font-medium">Paese (facoltativo)</span>
            <input
              value={campi.paese}
              onChange={(e) => setCampi({ ...campi, paese: e.target.value })}
              disabled={inCorso}
              maxLength={2}
              placeholder="IT"
              className="mt-1 w-full rounded-xl border border-border bg-background px-3 py-2 text-sm"
            />
          </label>
          <label className="block text-sm">
            <span className="font-medium">Numero o riferimento (facoltativo)</span>
            <input
              value={campi.credentialReference}
              onChange={(e) => setCampi({ ...campi, credentialReference: e.target.value })}
              disabled={inCorso}
              className="mt-1 w-full rounded-xl border border-border bg-background px-3 py-2 text-sm"
            />
          </label>
          <label className="block text-sm">
            <span className="font-medium">Data di rilascio (facoltativa)</span>
            <input
              type="date"
              value={campi.issuedOn}
              onChange={(e) => setCampi({ ...campi, issuedOn: e.target.value })}
              disabled={inCorso}
              className="mt-1 w-full rounded-xl border border-border bg-background px-3 py-2 text-sm"
            />
          </label>
          <label className="block text-sm">
            <span className="font-medium">Data di scadenza (facoltativa)</span>
            <input
              type="date"
              value={campi.expiresOn}
              onChange={(e) => setCampi({ ...campi, expiresOn: e.target.value })}
              disabled={inCorso}
              className="mt-1 w-full rounded-xl border border-border bg-background px-3 py-2 text-sm"
            />
          </label>
        </div>
        <p className="mt-3 text-xs text-muted-foreground">
          Il riferimento resta privato: non compare sul profilo pubblico. I documenti restano in
          un archivio privato e non sono scaricabili da altre persone.
        </p>
        {erroreForm && <p className="mt-3 text-sm text-red-700">{erroreForm}</p>}
        <Button size="sm" variant="outline" className="mt-4" onClick={creaBozza} disabled={inCorso}>
          Crea bozza
        </Button>
      </Card>
    </section>
  );
}
