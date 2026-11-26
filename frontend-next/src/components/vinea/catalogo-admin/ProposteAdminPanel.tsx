"use client";

// WI-012 — proposte dalle attività del sito: dato proposto, corrispondenze trovate e decisione motivata. Nessuna
// proposta entra nel catalogo senza una di queste decisioni; il solo nome non collega nulla.

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { PER_PAGINA, type Decisione, type PropostaAdmin, type ServiziCatalogoAdmin } from "@/lib/catalogo-admin/catalogo-admin";
import { Campo, Esito, Letto, Scelta, data, useLettura } from "./comune";

const STATI: [string, string][] = [
  ["aperta", "Aperte"],
  ["creata", "Create"],
  ["collegata", "Collegate"],
  ["gia_collegata", "Chiuse perché già note"],
  ["rifiutata", "Rifiutate"],
  ["duplicata", "Duplicate"],
  ["ritirata", "Ritirate"],
];

const MOTIVO: Record<string, string> = {
  collegamento_approvato: "collegamento già approvato",
  lwin_dichiarato: "LWIN dichiarato (non verificato)",
  nome_identico: "stesso produttore e nome",
  simile: "nome simile",
  fonte_lwin_non_promossa: "presente nella fonte LWIN, non ancora canonico",
};

const CORRISPONDENZA: Record<string, string> = {
  autorevole: "Corrispondenza autorevole",
  probabile: "Corrispondenza probabile",
  ambiguo: "Più identità possibili",
  sconosciuto: "Identità sconosciuta",
};

const AFFIDABILITA: Record<string, string> = {
  dichiarato_utente: "dichiarato dall'utente, non verificato",
  ocr_confermato_utente: "letto da etichetta e confermato dall'utente, non verificato",
  annuncio_pubblico: "dichiarato in un annuncio pubblico, non verificato",
};

export function ProposteAdminPanel({ servizi }: { servizi: ServiziCatalogoAdmin }) {
  const [stato, setStato] = useState("aperta");
  const [pagina, setPagina] = useState(1);
  const { esito, ricarica } = useLettura(() => servizi.proposte(stato, pagina), `${stato}|${pagina}`);
  return (
    <div className="space-y-3">
      <Scelta
        etichetta="Stato"
        valore={stato}
        onCambio={(v) => {
          setStato(v);
          setPagina(1);
        }}
        opzioni={STATI}
      />
      <Letto esito={esito} ricarica={ricarica}>
        {(d) => (
          <>
            <p className="text-sm text-muted-foreground">{d.totale} proposte</p>
            <ul className="space-y-3">
              {d.righe.map((p) => (
                <li key={p.id}>
                  <Proposta servizi={servizi} proposta={p} dopo={ricarica} />
                </li>
              ))}
            </ul>
            <div className="flex gap-2">
              <Button type="button" size="sm" variant="outline" disabled={pagina <= 1} onClick={() => setPagina(pagina - 1)}>
                Precedenti
              </Button>
              <Button type="button" size="sm" variant="outline" disabled={pagina * PER_PAGINA >= d.totale} onClick={() => setPagina(pagina + 1)}>
                Successive
              </Button>
            </div>
          </>
        )}
      </Letto>
    </div>
  );
}

function Proposta({ servizi, proposta, dopo }: { servizi: ServiziCatalogoAdmin; proposta: PropostaAdmin; dopo: () => void }) {
  const [nota, setNota] = useState("");
  const [vino, setVino] = useState("");
  const [produttoreId, setProduttoreId] = useState("");
  const [confermaDuplicato, setConfermaDuplicato] = useState(false);
  const [confermaProduttore, setConfermaProduttore] = useState(false);
  const [collega, setCollega] = useState(false);
  const [creaAnnata, setCreaAnnata] = useState(true);
  const [inCorso, setInCorso] = useState(false);
  const [errore, setErrore] = useState<string | null>(null);

  const decidi = async (decisione: Decisione) => {
    setInCorso(true);
    setErrore(null);
    const dati: Record<string, unknown> =
      decisione === "collega"
        ? { wine_id: vino.trim(), crea_annata: creaAnnata, collega_vino_app: collega }
        : decisione === "crea"
          ? {
              crea_annata: creaAnnata,
              collega_vino_app: collega,
              conferma_non_duplicato: confermaDuplicato,
              conferma_produttore_distinto: confermaProduttore,
              ...(produttoreId.trim() ? { produttore_id: produttoreId.trim() } : {}),
            }
          : {};
    const r = await servizi.decidiProposta(proposta.id, decisione, dati, nota);
    setInCorso(false);
    if (r.ok) dopo();
    else setErrore(r.error);
  };

  const d = proposta.dati;
  const canonici = proposta.candidati.filter((c) => c.wine_id);
  return (
    <article className="space-y-2 rounded-2xl border border-border bg-card p-3 text-sm" data-testid={`proposta-admin-${proposta.id}`}>
      <p className="font-semibold">
        {String(d.produttore)} — {String(d.nome)}
        {d.annata ? ` ${String(d.annata)}` : d.non_millesimato ? " (non millesimato)" : ""}
      </p>
      <p className="text-xs text-muted-foreground">
        Origine {proposta.origine} · {AFFIDABILITA[proposta.affidabilita] ?? proposta.affidabilita} · {proposta.invii} invii ·{" "}
        {data((proposta as { ultima?: string }).ultima)}
      </p>
      <p className="text-xs">
        {Object.entries(d)
          .filter(([k]) => !["produttore", "nome", "annata", "non_millesimato"].includes(k))
          .map(([k, v]) => `${k}: ${String(v)}`)
          .join(" · ") || "Nessun altro dato"}
        {proposta.mancanti.length ? ` · mancano: ${proposta.mancanti.join(", ")}` : ""}
      </p>
      <div>
        <p className="text-xs font-semibold">{CORRISPONDENZA[proposta.corrispondenza] ?? proposta.corrispondenza}</p>
        <ul className="list-disc pl-5 text-xs">
          {proposta.candidati.map((c) => (
            <li key={c.wine_id ?? `fonte-${c.source_record_id}`}>
              {c.produttore} — {c.nome} ({MOTIVO[c.motivo] ?? c.motivo}
              {c.lwin7 ?? c.lwin7_attuale ? `, LWIN ${c.lwin7 ?? c.lwin7_attuale}` : ""})
              {c.wine_id ? (
                <button type="button" className="ml-2 underline" onClick={() => setVino(c.wine_id as string)}>
                  usa questo
                </button>
              ) : null}
            </li>
          ))}
        </ul>
      </div>

      {proposta.stato === "aperta" ? (
        <fieldset className="space-y-2" disabled={inCorso}>
          <Campo etichetta="Motivo o nota di provenienza" valore={nota} onCambio={setNota} massimo={500} />
          <div className="flex flex-wrap gap-3 text-xs">
            <label className="flex items-center gap-1">
              <input type="checkbox" checked={creaAnnata} onChange={(e) => setCreaAnnata(e.target.checked)} />
              Registra annata e formato dichiarati
            </label>
            <label className="flex items-center gap-1">
              <input type="checkbox" checked={collega} onChange={(e) => setCollega(e.target.checked)} />
              Proponi il collegamento al vino dell&apos;app
            </label>
          </div>
          <div className="flex flex-wrap items-end gap-2">
            <Campo etichetta={canonici.length ? "ID del vino da collegare" : "ID di un vino canonico"} valore={vino} onCambio={setVino} massimo={36} />
            <Button type="button" size="sm" disabled={!vino.trim()} onClick={() => void decidi("collega")}>
              Collega
            </Button>
          </div>
          <div className="flex flex-wrap items-end gap-2">
            <Campo etichetta="ID produttore esistente (facoltativo)" valore={produttoreId} onCambio={setProduttoreId} massimo={36} />
            <label className="flex items-center gap-1 text-xs">
              <input type="checkbox" checked={confermaDuplicato} onChange={(e) => setConfermaDuplicato(e.target.checked)} />
              Ho verificato: non è un duplicato
            </label>
            <label className="flex items-center gap-1 text-xs">
              <input type="checkbox" checked={confermaProduttore} onChange={(e) => setConfermaProduttore(e.target.checked)} />
              È un produttore diverso dall&apos;omonimo
            </label>
            <Button type="button" size="sm" variant="outline" disabled={!nota.trim()} onClick={() => void decidi("crea")}>
              Crea nuovo vino
            </Button>
          </div>
          <div className="flex gap-2">
            <Button type="button" size="sm" variant="outline" disabled={!nota.trim()} onClick={() => void decidi("duplicata")}>
              Segna duplicata
            </Button>
            <Button type="button" size="sm" variant="outline" disabled={!nota.trim()} onClick={() => void decidi("rifiuta")}>
              Rifiuta
            </Button>
          </div>
        </fieldset>
      ) : (
        <p className="text-xs text-muted-foreground">{proposta.nota ?? "Decisione registrata nello storico."}</p>
      )}
      <Esito errore={errore} />
    </article>
  );
}
