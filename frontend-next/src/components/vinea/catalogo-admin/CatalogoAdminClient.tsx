"use client";

// WI-012 — gestione del catalogo dal sito. Una sola autenticazione (quella del sito) e il ruolo `admin` verificato dal
// database a ogni chiamata. Qui non ci sono interruttori: proiezione pubblica, promozione, acquisizione delle proposte
// e fusioni restano decisioni fuori dal pannello. Si mostrano solo dati realmente letti.

import Link from "next/link";
import { useMemo, useState } from "react";
import { ArrowLeft } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { ErrorState } from "@/components/vinea/States";
import { PER_PAGINA, serviziCatalogoAdmin, type Riepilogo, type ServiziCatalogoAdmin, type Territorio } from "@/lib/catalogo-admin/catalogo-admin";
import { getSupabaseClient } from "@/lib/supabase/client";
import { Campo, Esito, Letto, Scelta, data, testoValore, useLettura } from "./comune";
import { ProposteAdminPanel } from "./ProposteAdminPanel";
import { SchedaAdminPanel } from "./SchedaAdminPanel";

const INTERRUTTORI: [string, string][] = [
  ["regola", "Regola di promozione"],
  ["promozione", "Promozione"],
  ["proiezione_pubblica", "Proiezione pubblica"],
  ["proposte_utenti", "Proposte degli utenti"],
  ["acquisizione_annunci", "Acquisizione dagli annunci"],
  ["chiusura_automatica_note", "Chiusura automatica delle proposte già note"],
];

export function CatalogoAdminClient() {
  const client = useMemo(() => getSupabaseClient(), []);
  const servizi = useMemo(() => (client ? serviziCatalogoAdmin(client) : null), [client]);
  const [scheda, setScheda] = useState<string | null>(null);

  if (!servizi) return <ErrorState description="Il catalogo non è configurato in questo ambiente." />;

  return (
    <div className="mx-auto max-w-5xl space-y-4 p-4" data-testid="catalogo-admin">
      <Link href="/admin" className="inline-flex items-center gap-1 text-sm text-antracite/70 hover:text-bordeaux">
        <ArrowLeft className="h-4 w-4" /> Operazioni Admin
      </Link>
      <h1 className="font-serif text-2xl">Catalogo dei vini</h1>
      {scheda ? <SchedaAdminPanel servizi={servizi} id={scheda} chiudi={() => setScheda(null)} /> : null}
      <Tabs defaultValue="stato">
        <TabsList className="flex h-auto flex-wrap justify-start">
          <TabsTrigger value="stato">Stato</TabsTrigger>
          <TabsTrigger value="catalogo">Catalogo</TabsTrigger>
          <TabsTrigger value="proposte">Proposte</TabsTrigger>
          <TabsTrigger value="code">Da decidere</TabsTrigger>
          <TabsTrigger value="nuovo">Nuovo vino</TabsTrigger>
          <TabsTrigger value="fonti">Fonti e import</TabsTrigger>
          <TabsTrigger value="storico">Storico</TabsTrigger>
        </TabsList>
        <TabsContent value="stato">
          <Panoramica servizi={servizi} />
        </TabsContent>
        <TabsContent value="catalogo">
          <ElencoVini servizi={servizi} apri={setScheda} />
        </TabsContent>
        <TabsContent value="proposte">
          <ProposteAdminPanel servizi={servizi} />
        </TabsContent>
        <TabsContent value="code">
          <CodeDaDecidere servizi={servizi} apri={setScheda} />
        </TabsContent>
        <TabsContent value="nuovo">
          <NuovoVino servizi={servizi} apri={setScheda} />
        </TabsContent>
        <TabsContent value="fonti">
          <FontiEImportazioni servizi={servizi} apri={setScheda} />
        </TabsContent>
        <TabsContent value="storico">
          <Storico servizi={servizi} />
        </TabsContent>
      </Tabs>
    </div>
  );
}

function Panoramica({ servizi }: { servizi: ServiziCatalogoAdmin }) {
  const { esito, ricarica } = useLettura(() => servizi.riepilogo(), "riepilogo");
  return (
    <Letto esito={esito} ricarica={ricarica}>
      {(r: Riepilogo) => (
        <div className="space-y-3 text-sm">
          <dl className="grid gap-2 sm:grid-cols-3">
            {(
              [
                ["Vini canonici attivi", r.vini.attivi],
                ["Identità native Vinea", r.vini.nativi],
                ["Native pubblicate", r.vini.nativi_pubblicati],
                ["Senza codice LWIN", r.vini.senza_lwin],
                ["Produttori", r.produttori],
                ["Record della fonte LWIN", r.fonte.record],
                ["Proposte aperte", r.proposte.aperte],
                ["di cui identità sconosciute", r.proposte.aperte_identita_nuove],
                ["di cui ambigue", r.proposte.aperte_ambigue],
                ["Possibili duplicati", r.da_decidere.duplicati],
                ["Attributi proposti", r.da_decidere.attributi],
                ["Collegamenti proposti", r.da_decidere.collegamenti],
              ] as [string, number][]
            ).map(([k, v]) => (
              <div key={k} className="rounded-xl border border-border bg-card p-3">
                <dt className="text-xs text-muted-foreground">{k}</dt>
                <dd className="text-lg font-semibold">{v.toLocaleString("it-IT")}</dd>
              </div>
            ))}
          </dl>
          <div className="rounded-xl border border-border bg-card p-3">
            <h2 className="font-semibold">Interruttori (sola lettura)</h2>
            <ul className="text-xs">
              {INTERRUTTORI.map(([chiave, nome]) => {
                const v = r.interruttori[chiave];
                return (
                  <li key={chiave}>
                    {nome}: <strong>{typeof v === "boolean" ? (v ? "acceso" : "spento") : (v ?? "non disponibile")}</strong>
                  </li>
                );
              })}
            </ul>
          </div>
          <p className="text-xs text-muted-foreground">
            Ultima importazione:{" "}
            {r.fonte.ultima_importazione
              ? `${r.fonte.ultima_importazione.stato}, ${data(r.fonte.ultima_importazione.iniziata)} (${r.fonte.ultima_importazione.righe.toLocaleString("it-IT")} righe)`
              : "nessuna"}
            {` · rilievi aperti nell'import: ${r.fonte.rilievi_import}`}
          </p>
        </div>
      )}
    </Letto>
  );
}

function ElencoVini({ servizi, apri }: { servizi: ServiziCatalogoAdmin; apri: (id: string) => void }) {
  const [bozza, setBozza] = useState("");
  const [filtro, setFiltro] = useState({ testo: "", stato: "", origine: "", pagina: 1 });
  const { esito, ricarica } = useLettura(() => servizi.vini(filtro), JSON.stringify(filtro));
  return (
    <div className="space-y-3">
      <form
        className="grid gap-2 sm:grid-cols-4"
        onSubmit={(e) => {
          e.preventDefault();
          setFiltro((f) => ({ ...f, testo: bozza, pagina: 1 }));
        }}
      >
        <Campo etichetta="Produttore, nome o LWIN-7" valore={bozza} onCambio={setBozza} massimo={120} />
        <Scelta etichetta="Origine" valore={filtro.origine} onCambio={(v) => setFiltro((f) => ({ ...f, origine: v, pagina: 1 }))}
          opzioni={[["", "Tutte"], ["manual", "Native Vinea"], ["promotion", "Dalla fonte"]]} />
        <Scelta etichetta="Stato" valore={filtro.stato} onCambio={(v) => setFiltro((f) => ({ ...f, stato: v, pagina: 1 }))}
          opzioni={[["", "Tutti"], ["active", "Attivi"], ["merged", "Confluiti"], ["retired", "Ritirati"]]} />
        <Button type="submit" size="sm" className="self-end">
          Cerca
        </Button>
      </form>
      <Letto esito={esito} ricarica={ricarica}>
        {(d) => (
          <>
            <p className="text-sm text-muted-foreground">
              {d.oltre ? "Più di 1.000 risultati: restringi la ricerca." : `${d.totale} risultati`}
            </p>
            <ul className="divide-y divide-border rounded-xl border border-border bg-card">
              {d.righe.map((v) => (
                <li key={v.id} className="flex items-center justify-between gap-2 p-2 text-sm">
                  <span className="min-w-0">
                    <span className="block truncate">
                      {v.produttore} — {v.nome}
                    </span>
                    <span className="text-xs text-muted-foreground">
                      {v.lwin7 ? `LWIN ${v.lwin7}` : "senza LWIN"} · {v.origine === "manual" ? (v.pubblicato ? "nativa, pubblicata" : "nativa, non pubblicata") : "dalla fonte"} · {v.stato}
                    </span>
                  </span>
                  <Button type="button" size="sm" variant="outline" onClick={() => apri(v.id)}>
                    Apri
                  </Button>
                </li>
              ))}
            </ul>
            <div className="flex gap-2">
              <Button type="button" size="sm" variant="outline" disabled={filtro.pagina <= 1} onClick={() => setFiltro((f) => ({ ...f, pagina: f.pagina - 1 }))}>
                Precedenti
              </Button>
              <Button type="button" size="sm" variant="outline" disabled={d.righe.length < PER_PAGINA} onClick={() => setFiltro((f) => ({ ...f, pagina: f.pagina + 1 }))}>
                Successivi
              </Button>
            </div>
          </>
        )}
      </Letto>
    </div>
  );
}

function CodeDaDecidere({ servizi, apri }: { servizi: ServiziCatalogoAdmin; apri: (id: string) => void }) {
  const [pagina, setPagina] = useState(1);
  const [nota, setNota] = useState("");
  const [errore, setErrore] = useState<string | null>(null);
  const { esito, ricarica } = useLettura(() => servizi.code(pagina), String(pagina));
  const decidi = async (azione: string, dati: Record<string, unknown>) => {
    setErrore(null);
    const r = await servizi.azione(azione, dati, nota);
    if (r.ok) {
      setNota("");
      ricarica();
    } else setErrore(r.error);
  };
  return (
    <div className="space-y-3 text-sm">
      <Campo etichetta="Nota della decisione" valore={nota} onCambio={setNota} massimo={500} />
      <Esito errore={errore} />
      <Letto esito={esito} ricarica={ricarica}>
        {(c) => (
          <>
            <section>
              <h2 className="font-semibold">Possibili duplicati ({c.duplicati_totale})</h2>
              <p className="text-xs text-muted-foreground">Qui si registra il giudizio: nessuna fusione parte da questa pagina.</p>
              <ul className="space-y-2">
                {c.duplicati.map((d) => (
                  <li key={d.id} className="rounded-xl border border-border bg-card p-2">
                    <p>{d.primo}</p>
                    <p>{d.secondo}</p>
                    <div className="mt-1 flex flex-wrap gap-2">
                      <Button type="button" size="sm" variant="outline" onClick={() => void decidi("duplicato_decidi", { id: d.id, decisione: "distinct" })}>
                        Sono distinti
                      </Button>
                      <Button type="button" size="sm" variant="outline" onClick={() => void decidi("duplicato_decidi", { id: d.id, decisione: "same" })}>
                        Sono lo stesso
                      </Button>
                      <Button type="button" size="sm" variant="ghost" onClick={() => void decidi("duplicato_decidi", { id: d.id, decisione: "dismissed" })}>
                        Archivia
                      </Button>
                    </div>
                  </li>
                ))}
              </ul>
            </section>
            <section>
              <h2 className="font-semibold">Attributi proposti ({c.attributi_totale})</h2>
              <ul className="space-y-2">
                {c.attributi.map((a) => (
                  <li key={a.id} className="rounded-xl border border-border bg-card p-2">
                    <p>
                      {a.attributo}: attuale <strong>{testoValore(a.valore_attuale)}</strong> → proposto <strong>{testoValore(a.valore)}</strong>
                    </p>
                    <p className="text-xs text-muted-foreground">
                      {a.fonte}
                      {a.evidenza ? ` — ${a.evidenza}` : ""}
                    </p>
                    <div className="mt-1 flex flex-wrap gap-2">
                      <Button type="button" size="sm" onClick={() => void decidi("attributo_decidi", { id: a.id, decisione: "accepted" })}>
                        Accetta
                      </Button>
                      <Button type="button" size="sm" variant="outline" onClick={() => void decidi("attributo_decidi", { id: a.id, decisione: "rejected" })}>
                        Rifiuta
                      </Button>
                      {a.vino_id ? (
                        <Button type="button" size="sm" variant="ghost" onClick={() => apri(a.vino_id as string)}>
                          Apri il vino
                        </Button>
                      ) : null}
                    </div>
                  </li>
                ))}
              </ul>
            </section>
            <section>
              <h2 className="font-semibold">Collegamenti proposti ({c.collegamenti_totale})</h2>
              <ul className="space-y-2">
                {c.collegamenti.map((l) => (
                  <li key={l.id} className="rounded-xl border border-border bg-card p-2">
                    <p>
                      App: {l.descrizione_app ?? l.vino_app} → Catalogo: {l.produttore} — {l.nome} {l.anno ?? "NM"}
                    </p>
                    <div className="mt-1 flex gap-2">
                      <Button type="button" size="sm" onClick={() => void decidi("collegamento_decidi", { id: l.id, decisione: "activate" })}>
                        Approva
                      </Button>
                      <Button type="button" size="sm" variant="outline" onClick={() => void decidi("collegamento_decidi", { id: l.id, decisione: "revoke" })}>
                        Respingi
                      </Button>
                    </div>
                  </li>
                ))}
              </ul>
            </section>
            <div className="flex gap-2">
              <Button type="button" size="sm" variant="outline" disabled={pagina <= 1} onClick={() => setPagina(pagina - 1)}>
                Precedenti
              </Button>
              <Button type="button" size="sm" variant="outline" onClick={() => setPagina(pagina + 1)}>
                Successivi
              </Button>
            </div>
          </>
        )}
      </Letto>
    </div>
  );
}

function NuovoVino({ servizi, apri }: { servizi: ServiziCatalogoAdmin; apri: (id: string) => void }) {
  const vuoto = { produttore: "", produttore_id: "", nome: "", denominazione: "", tipo: "", colore: "", territorio: "", nota: "" };
  const [campi, setCampi] = useState(vuoto);
  const [territori, setTerritori] = useState<Territorio[]>([]);
  const [territorioId, setTerritorioId] = useState<number | null>(null);
  const [confermaDuplicato, setConfermaDuplicato] = useState(false);
  const [confermaProduttore, setConfermaProduttore] = useState(false);
  const [errore, setErrore] = useState<string | null>(null);
  const [inCorso, setInCorso] = useState(false);
  const cambia = (k: keyof typeof vuoto) => (v: string) => setCampi((p) => ({ ...p, [k]: v }));

  const crea = async () => {
    setInCorso(true);
    setErrore(null);
    const r = await servizi.azione(
      "nuovo_vino",
      {
        ...(campi.produttore_id.trim() ? { produttore_id: campi.produttore_id.trim() } : { produttore: campi.produttore }),
        nome: campi.nome,
        denominazione: campi.denominazione,
        tipo: campi.tipo,
        colore: campi.colore,
        ...(territorioId ? { territorio_id: territorioId } : {}),
        conferma_non_duplicato: confermaDuplicato,
        conferma_produttore_distinto: confermaProduttore,
      },
      campi.nota,
    );
    setInCorso(false);
    if (!r.ok) {
      setErrore(r.error);
      return;
    }
    setCampi(vuoto);
    setTerritorioId(null);
    setTerritori([]);
    setConfermaDuplicato(false);
    setConfermaProduttore(false);
    apri(String(r.data.id));
  };

  return (
    <form
      className="space-y-2 text-sm"
      onSubmit={(e) => {
        e.preventDefault();
        if (!inCorso) void crea();
      }}
    >
      <p className="text-xs text-muted-foreground">
        Il vino nasce senza codice LWIN, non pubblicato. Annate e formati si aggiungono dalla scheda, solo se documentati.
      </p>
      <div className="grid gap-2 sm:grid-cols-2">
        <Campo etichetta="Produttore (nuovo)" valore={campi.produttore} onCambio={cambia("produttore")} massimo={160} />
        <Campo etichetta="oppure ID di un produttore esistente" valore={campi.produttore_id} onCambio={cambia("produttore_id")} massimo={36} />
        <Campo etichetta="Nome del vino" valore={campi.nome} onCambio={cambia("nome")} />
        <Campo etichetta="Denominazione" valore={campi.denominazione} onCambio={cambia("denominazione")} massimo={160} />
        <Campo etichetta="Tipologia" valore={campi.tipo} onCambio={cambia("tipo")} massimo={80} />
        <Campo etichetta="Colore" valore={campi.colore} onCambio={cambia("colore")} massimo={80} />
        <div className="flex items-end gap-2">
          <Campo etichetta="Cerca il territorio" valore={campi.territorio} onCambio={cambia("territorio")} massimo={80} />
          <Button
            type="button"
            size="sm"
            variant="outline"
            onClick={() =>
              void servizi.territori(campi.territorio).then((r) => (r.ok ? setTerritori(r.data) : setErrore(r.error)))
            }
          >
            Cerca
          </Button>
        </div>
        {territori.length ? (
          <Scelta
            etichetta="Territorio"
            valore={territorioId ? String(territorioId) : ""}
            onCambio={(v) => setTerritorioId(v ? Number(v) : null)}
            opzioni={[["", "Nessuno"], ...territori.map((t): [string, string] => [String(t.id), `${t.nome} (${t.tipo})`])]}
          />
        ) : null}
      </div>
      <Campo etichetta="Nota di provenienza (obbligatoria)" valore={campi.nota} onCambio={cambia("nota")} massimo={500} />
      <VerificaFonte servizi={servizi} testo={`${campi.produttore} ${campi.nome}`.trim()} />
      <label className="flex items-center gap-1 text-xs">
        <input type="checkbox" checked={confermaDuplicato} onChange={(e) => setConfermaDuplicato(e.target.checked)} />
        Ho verificato: non è un duplicato di un vino esistente o della fonte
      </label>
      <label className="flex items-center gap-1 text-xs">
        <input type="checkbox" checked={confermaProduttore} onChange={(e) => setConfermaProduttore(e.target.checked)} />
        Il produttore è diverso da quello omonimo già presente
      </label>
      <Button type="submit" size="sm" disabled={inCorso || !campi.nome.trim() || !campi.nota.trim()}>
        Crea il vino
      </Button>
      <Esito errore={errore} />
    </form>
  );
}

function VerificaFonte({ servizi, testo }: { servizi: ServiziCatalogoAdmin; testo: string }) {
  const [richiesto, setRichiesto] = useState<string | null>(null);
  return (
    <div>
      <Button type="button" size="sm" variant="outline" disabled={testo.length < 4} onClick={() => setRichiesto(testo)}>
        Cerca nella fonte LWIN
      </Button>
      {richiesto ? <EsitoFonte key={richiesto} servizi={servizi} testo={richiesto} /> : null}
    </div>
  );
}

function EsitoFonte({ servizi, testo }: { servizi: ServiziCatalogoAdmin; testo: string }) {
  const { esito, ricarica } = useLettura(() => servizi.cercaFonte(testo), testo);
  return (
    <Letto esito={esito} ricarica={ricarica}>
      {(righe) =>
        righe.length ? (
          <ul className="mt-1 list-disc pl-5 text-xs">
            {righe.map((r) => (
              <li key={r.source_record_id}>
                LWIN {r.lwin7}: {r.produttore} — {r.nome} ({r.paese ?? "paese non indicato"}, {r.stato}
                {r.canonico ? ", già canonico" : ""})
              </li>
            ))}
          </ul>
        ) : (
          <p className="mt-1 text-xs text-muted-foreground">Nessun record con lo stesso produttore e nome.</p>
        )
      }
    </Letto>
  );
}

function FontiEImportazioni({ servizi, apri }: { servizi: ServiziCatalogoAdmin; apri: (id: string) => void }) {
  const { esito, ricarica } = useLettura(() => servizi.fonti(), "fonti");
  const [messaggio, setMessaggio] = useState<string | null>(null);
  const [errore, setErrore] = useState<string | null>(null);
  const acquisisci = async () => {
    setErrore(null);
    setMessaggio(null);
    const r = await servizi.azione("acquisisci_annunci", { limite: 100 }, "");
    if (!r.ok) {
      setErrore(r.error);
      return;
    }
    setMessaggio(
      r.data.abilitata
        ? `Annunci letti: ${testoValore(r.data.letti)}, nuove proposte: ${testoValore(r.data.nuove_proposte)}, scartati: ${testoValore(r.data.scartati)}.`
        : "L'acquisizione dagli annunci è spenta: nessun annuncio è stato letto.",
    );
  };
  return (
    <div className="space-y-3 text-sm">
      <section>
        <h2 className="font-semibold">Proposte dagli annunci pubblici</h2>
        <p className="text-xs text-muted-foreground">Legge solo i dati enologici degli annunci già pubblici.</p>
        <Button type="button" size="sm" variant="outline" onClick={() => void acquisisci()}>
          Acquisisci dagli annunci
        </Button>
        <Esito errore={errore} messaggio={messaggio} />
      </section>
      <Letto esito={esito} ricarica={ricarica}>
        {(f) => (
          <>
            <section>
              <h2 className="font-semibold">Fonti</h2>
              <ul className="list-disc pl-5 text-xs">
                {f.fonti.map((s) => (
                  <li key={s.codice}>
                    {s.nome} ({s.codice}) — {s.autorizzazione}
                    {s.licenza ? `, ${s.licenza}` : ""}
                  </li>
                ))}
              </ul>
            </section>
            <section>
              <h2 className="font-semibold">Ultime importazioni</h2>
              <ul className="list-disc pl-5 text-xs">
                {f.importazioni.map((i) => (
                  <li key={i.seq}>
                    {data(i.iniziata)} · {i.stato} · {i.file} · {i.righe.toLocaleString("it-IT")} righe · {i.impronta_file.slice(0, 12)}…
                  </li>
                ))}
              </ul>
            </section>
            <section>
              <h2 className="font-semibold">Conflitti con vini nativi ({f.conflitti_lwin_nativi.length})</h2>
              <p className="text-xs text-muted-foreground">
                Record LWIN con lo stesso nome di un vino nativo: associare il codice o registrare il duplicato prima di promuovere.
              </p>
              <ul className="list-disc pl-5 text-xs">
                {f.conflitti_lwin_nativi.map((c) => (
                  <li key={`${c.wine_id}-${c.lwin7}`}>
                    {c.produttore} — {c.nome} ↔ LWIN {c.lwin7}{" "}
                    <button type="button" className="underline" onClick={() => apri(c.wine_id)}>
                      apri
                    </button>
                  </li>
                ))}
              </ul>
            </section>
          </>
        )}
      </Letto>
    </div>
  );
}

function Storico({ servizi }: { servizi: ServiziCatalogoAdmin }) {
  const [pagina, setPagina] = useState(1);
  const { esito, ricarica } = useLettura(() => servizi.storico(pagina), String(pagina));
  return (
    <Letto esito={esito} ricarica={ricarica}>
      {(eventi) => (
        <div className="space-y-2 text-xs">
          {eventi.length === 0 ? <p>Nessun evento.</p> : null}
          <ul className="divide-y divide-border">
            {eventi.map((e) => (
              <li key={e.id} className="py-1">
                {data(e.quando)} · <strong>{e.azione}</strong> · {e.entita} {e.riferimento ?? ""} · {e.esecutore}
              </li>
            ))}
          </ul>
          <div className="flex gap-2">
            <Button type="button" size="sm" variant="outline" disabled={pagina <= 1} onClick={() => setPagina(pagina - 1)}>
              Più recenti
            </Button>
            <Button type="button" size="sm" variant="outline" disabled={eventi.length < 30} onClick={() => setPagina(pagina + 1)}>
              Più vecchi
            </Button>
          </div>
        </div>
      )}
    </Letto>
  );
}
