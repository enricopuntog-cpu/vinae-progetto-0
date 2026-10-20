"use client";

import { useCallback, useEffect, useMemo, useRef, useState, type ChangeEvent, type FormEvent } from "react";
import { Archive, ArchiveRestore, Eye, EyeOff, GlassWater, ImageOff, ImagePlus, Loader2, Pencil, Plus, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { CONDIZIONI_ACCESSORIO, ETICHETTE_CONDIZIONE } from "@/lib/accessori/accessori";
import {
  MAX_FOTO_CANTINA_ACCESSORIO,
  etichettaCategoria,
  moduloCantinaVuoto,
  moduloDaAccessorio,
  sceltePerCategoria,
  validaModuloCantina,
  type AccessorioPersonale,
  type CategoriaTassonomia,
  type ErroriModulo,
  type ModuloCantinaAccessorio,
  type StatoCantinaAccessori,
} from "@/lib/cantina-accessori/cantina-accessori";
import { preparaImmagineVetrina } from "@/lib/partner/prepara-immagine-vetrina";
import { getSupabaseClient } from "@/lib/supabase/client";
import { creaAccessoriLetturaService } from "@/services/accessori-service";
import { creaCantinaAccessoriService } from "@/services/cantina-accessori-service";

/**
 * Sezione «Accessori» della Cantina personale (VPM-015B1).
 *
 * Vive DENTRO la pagina Cantina, accanto alle bottiglie, e non la duplica: è
 * un blocco a parte che può mancare da solo. Se la funzione non è abilitata
 * (interruttore nel database, spento di default) o la lettura fallisce, non
 * mostra nulla: fail closed, senza segnaposto che racconti una funzione
 * assente.
 *
 * L'interfaccia è una comodità: proprietario, categoria, esposizione e foto
 * sono ricontrollati dalle porte `cantina_accessori_*` e dalle policy di
 * Storage. Nessun prezzo, nessun pulsante di vendita: esporre un accessorio
 * nel profilo non lo mette in vendita.
 */

const CAMPO =
  "w-full rounded-md border border-input bg-background px-3 py-2 text-sm focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-bordeaux";

type Messaggio = { tono: "ok" | "errore"; testo: string } | null;

function Avviso({ messaggio }: { messaggio: Messaggio }) {
  if (!messaggio) return null;
  return (
    <p
      role={messaggio.tono === "errore" ? "alert" : "status"}
      className={`rounded-lg border px-3 py-2 text-sm ${
        messaggio.tono === "errore"
          ? "border-bordeaux/40 bg-bordeaux/5 text-bordeaux"
          : "border-salvia/40 bg-salvia/10 text-antracite"
      }`}
    >
      {messaggio.testo}
    </p>
  );
}

export function CantinaAccessori() {
  const client = useMemo(() => getSupabaseClient(), []);
  const servizio = useMemo(() => creaCantinaAccessoriService(client), [client]);
  const lettura = useMemo(() => creaAccessoriLetturaService(client), [client]);

  const [stato, setStato] = useState<StatoCantinaAccessori | null>(null);
  const [tassonomia, setTassonomia] = useState<CategoriaTassonomia[]>([]);
  const [elenco, setElenco] = useState<AccessorioPersonale[]>([]);
  const [archiviati, setArchiviati] = useState(false);
  const [url, setUrl] = useState<Record<string, string>>({});
  const [caricamento, setCaricamento] = useState(true);
  const [messaggio, setMessaggio] = useState<Messaggio>(null);
  const [modifica, setModifica] = useState<{ accessorio: AccessorioPersonale | null } | null>(null);
  const [daEsporre, setDaEsporre] = useState<AccessorioPersonale | null>(null);
  const [daRimuovere, setDaRimuovere] = useState<AccessorioPersonale | null>(null);
  const [occupato, setOccupato] = useState(false);
  const [schedeCatalogo, setSchedeCatalogo] = useState<{ slug: string; nome: string }[]>([]);

  const carica = useCallback(
    async (mostraArchiviati: boolean) => {
      const r = await servizio.elenco(mostraArchiviati);
      if (!r.ok) {
        setMessaggio({ tono: "errore", testo: r.error });
        return;
      }
      setElenco(r.data);
      const prime = r.data.flatMap((a) => (a.immagini[0] ? [a.immagini[0]] : []));
      const firmate = await servizio.urlFoto(prime);
      setUrl(firmate.ok ? firmate.data : {});
    },
    [servizio],
  );

  // Avvio: stato -> (se abilitata) tassonomia, elenco, schede del catalogo.
  useEffect(() => {
    let attivo = true;
    (async () => {
      const s = await servizio.stato();
      if (!attivo) return;
      if (!s.ok || !s.data.abilitata) {
        setStato(s.ok ? s.data : null);
        setCaricamento(false);
        return;
      }
      setStato(s.data);
      const [t] = await Promise.all([servizio.categorie(), carica(false)]);
      if (!attivo) return;
      if (t.ok) setTassonomia(t.data);
      else setMessaggio({ tono: "errore", testo: t.error });
      // Il legame col catalogo e facoltativo: si offre solo se il catalogo e
      // leggibile (vuoto = chiuso), e un guasto qui non toglie la sezione.
      const cat = await lettura.elenco(null, false);
      if (attivo && cat.ok) setSchedeCatalogo(cat.data.map((x) => ({ slug: x.slug, nome: x.nome })));
      setCaricamento(false);
    })();
    return () => {
      attivo = false;
    };
  }, [servizio, lettura, carica]);

  if (caricamento) {
    return (
      <p className="flex items-center gap-2 text-sm text-muted-foreground" role="status">
        <Loader2 className="h-4 w-4 animate-spin" aria-hidden /> Carico gli accessori…
      </p>
    );
  }
  if (!stato?.abilitata) return null;

  const dopoCambio = async (testo: string) => {
    setMessaggio({ tono: "ok", testo });
    await carica(archiviati);
  };

  const cambiaVisibilita = async (a: AccessorioPersonale, esponi: boolean) => {
    setOccupato(true);
    const r = await servizio.impostaVisibilita(a.id, esponi ? "cantina_pubblica" : "privata");
    setOccupato(false);
    setDaEsporre(null);
    if (!r.ok) return setMessaggio({ tono: "errore", testo: r.error });
    await dopoCambio(esponi ? "Accessorio esposto nel tuo profilo." : "Accessorio di nuovo privato.");
  };

  const archivia = async (a: AccessorioPersonale, archivia: boolean) => {
    setOccupato(true);
    const r = await servizio.archivia(a.id, archivia);
    setOccupato(false);
    if (!r.ok) return setMessaggio({ tono: "errore", testo: r.error });
    await dopoCambio(archivia ? "Accessorio archiviato." : "Accessorio ripristinato (resta privato).");
  };

  const rimuovi = async (a: AccessorioPersonale) => {
    setOccupato(true);
    const r = await servizio.rimuovi(a.id);
    setOccupato(false);
    setDaRimuovere(null);
    if (!r.ok) return setMessaggio({ tono: "errore", testo: r.error });
    await dopoCambio("Accessorio rimosso.");
  };

  return (
    <section aria-labelledby="cantina-accessori-titolo" className="space-y-4" data-testid="cantina-accessori">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-salvia">Cantina</p>
          <h2 id="cantina-accessori-titolo" className="font-serif text-2xl font-semibold">
            Accessori
          </h2>
          <p className="mt-1 max-w-xl text-sm text-muted-foreground">
            I calici, i cavatappi e gli altri strumenti che possiedi. Restano privati finché non
            scegli di esporli nel tuo profilo; esporli non li mette in vendita.
          </p>
        </div>
        <Button type="button" onClick={() => setModifica({ accessorio: null })}>
          <Plus aria-hidden /> Aggiungi accessorio
        </Button>
      </div>

      <Avviso messaggio={messaggio} />

      <label className="flex items-center gap-2 text-sm">
        <input
          type="checkbox"
          checked={archiviati}
          onChange={async (e) => {
            setArchiviati(e.target.checked);
            await carica(e.target.checked);
          }}
        />
        Mostra gli archiviati
      </label>

      {elenco.length === 0 ? (
        <div
          role="status"
          className="flex flex-col items-center rounded-2xl border border-dashed border-border bg-secondary/40 px-6 py-10 text-center"
        >
          <span className="flex h-12 w-12 items-center justify-center rounded-full bg-crema text-bordeaux">
            <GlassWater className="h-6 w-6" aria-hidden />
          </span>
          <p className="mt-3 font-serif text-lg font-semibold">
            {archiviati ? "Nessun accessorio archiviato" : "Nessun accessorio ancora"}
          </p>
          {!archiviati ? (
            <p className="mt-1 max-w-sm text-sm text-muted-foreground">
              Aggiungi il primo: scegli il tipo, dagli un nome e indica com&apos;è messo.
            </p>
          ) : null}
        </div>
      ) : (
        <ul className="grid gap-3 sm:grid-cols-2" data-testid="cantina-accessori-elenco">
          {elenco.map((a) => (
            <li
              key={a.id}
              data-testid="cantina-accessorio"
              className="flex min-w-0 flex-col overflow-hidden rounded-2xl border border-border bg-card"
            >
              <div className="aspect-[4/3] w-full overflow-hidden bg-secondary/40">
                {a.immagini[0] && url[a.immagini[0]] ? (
                  /* eslint-disable-next-line @next/next/no-img-element -- WebP gia ridotta al caricamento, URL firmata a tempo. */
                  <img src={url[a.immagini[0]]} alt={a.nome} loading="lazy" className="h-full w-full object-cover" />
                ) : (
                  <div className="flex h-full w-full items-center justify-center text-antracite/40">
                    <ImageOff className="h-8 w-8" aria-hidden />
                  </div>
                )}
              </div>
              <div className="flex flex-1 flex-col gap-2 p-4">
                <p className="text-xs font-semibold uppercase tracking-[0.14em] text-salvia">
                  {etichettaCategoria(a.categoria)}
                </p>
                <h3 className="break-words font-serif text-lg font-semibold leading-snug">{a.nome}</h3>
                <p className="text-sm text-muted-foreground">
                  {ETICHETTE_CONDIZIONE[a.condizione]} · {a.quantita === 1 ? "1 pezzo" : `${a.quantita} pezzi`}
                  {a.marchio ? ` · ${a.marchio}` : ""}
                </p>
                <p className="text-xs">
                  {a.archiviato ? (
                    <span className="rounded-full bg-secondary px-2 py-0.5">Archiviato</span>
                  ) : a.visibilita === "cantina_pubblica" ? (
                    <span className="rounded-full bg-salvia/15 px-2 py-0.5 text-antracite">
                      Esposto nel profilo
                      {stato.espostiVisibili ? "" : " (non ancora visibile al pubblico)"}
                    </span>
                  ) : (
                    <span className="rounded-full bg-secondary px-2 py-0.5">Privato</span>
                  )}
                </p>
                <div className="mt-auto flex flex-wrap gap-2 pt-1">
                  {!a.archiviato ? (
                    <Button type="button" size="sm" variant="outline" onClick={() => setModifica({ accessorio: a })}>
                      <Pencil aria-hidden /> Modifica
                    </Button>
                  ) : null}
                  {!a.archiviato ? (
                    a.visibilita === "cantina_pubblica" ? (
                      <Button type="button" size="sm" variant="outline" disabled={occupato} onClick={() => cambiaVisibilita(a, false)}>
                        <EyeOff aria-hidden /> Rendi privato
                      </Button>
                    ) : (
                      <Button type="button" size="sm" variant="outline" disabled={occupato} onClick={() => setDaEsporre(a)}>
                        <Eye aria-hidden /> Esponi
                      </Button>
                    )
                  ) : null}
                  <Button type="button" size="sm" variant="ghost" disabled={occupato} onClick={() => archivia(a, !a.archiviato)}>
                    {a.archiviato ? <ArchiveRestore aria-hidden /> : <Archive aria-hidden />}
                    {a.archiviato ? "Ripristina" : "Archivia"}
                  </Button>
                  <Button type="button" size="sm" variant="ghost" disabled={occupato} onClick={() => setDaRimuovere(a)}>
                    <Trash2 aria-hidden /> Rimuovi
                  </Button>
                </div>
              </div>
            </li>
          ))}
        </ul>
      )}

      {modifica ? (
        <ModuloAccessorioDialog
          accessorio={modifica.accessorio}
          tassonomia={tassonomia}
          schedeCatalogo={schedeCatalogo}
          servizio={servizio}
          onChiudi={() => setModifica(null)}
          onCambiato={async (testo) => {
            await dopoCambio(testo);
          }}
        />
      ) : null}

      <Dialog open={daEsporre !== null} onOpenChange={(aperto) => (aperto ? null : setDaEsporre(null))}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Esporre «{daEsporre?.nome}» nel profilo?</DialogTitle>
            <DialogDescription>
              Chiunque visiti il tuo profilo potrà vedere nome, tipo, condizione, quantità, descrizione e foto di
              questo accessorio. Le note restano private. Non è in vendita e puoi renderlo di nuovo privato
              quando vuoi.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button type="button" variant="ghost" onClick={() => setDaEsporre(null)}>
              Annulla
            </Button>
            <Button type="button" disabled={occupato} onClick={() => daEsporre && cambiaVisibilita(daEsporre, true)}>
              Sì, esponi
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={daRimuovere !== null} onOpenChange={(aperto) => (aperto ? null : setDaRimuovere(null))}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Rimuovere «{daRimuovere?.nome}»?</DialogTitle>
            <DialogDescription>
              L&apos;accessorio e le sue foto vengono eliminati definitivamente. Per tenerlo senza vederlo in
              elenco puoi archiviarlo.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button type="button" variant="ghost" onClick={() => setDaRimuovere(null)}>
              Annulla
            </Button>
            <Button type="button" disabled={occupato} onClick={() => daRimuovere && rimuovi(daRimuovere)}>
              Sì, rimuovi
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </section>
  );
}

function ModuloAccessorioDialog({
  accessorio,
  tassonomia,
  schedeCatalogo,
  servizio,
  onChiudi,
  onCambiato,
}: {
  accessorio: AccessorioPersonale | null;
  tassonomia: CategoriaTassonomia[];
  schedeCatalogo: { slug: string; nome: string }[];
  servizio: ReturnType<typeof creaCantinaAccessoriService>;
  onChiudi: () => void;
  onCambiato: (testo: string) => Promise<void>;
}) {
  // L'id di un accessorio nuovo lo sceglie il client: ripetere il salvataggio
  // dopo un errore di rete non ne crea due.
  const [idNuovo] = useState(() => crypto.randomUUID());
  const [corrente, setCorrente] = useState<AccessorioPersonale | null>(accessorio);
  const [modulo, setModulo] = useState<ModuloCantinaAccessorio>(
    accessorio ? moduloDaAccessorio(accessorio) : moduloCantinaVuoto(),
  );
  const [errori, setErrori] = useState<ErroriModulo>({});
  const [messaggio, setMessaggio] = useState<Messaggio>(null);
  const [inCorso, setInCorso] = useState(false);
  const [caricoFoto, setCaricoFoto] = useState(false);
  const [urlFoto, setUrlFoto] = useState<Record<string, string>>({});
  const inputFoto = useRef<HTMLInputElement>(null);

  const scelte = useMemo(() => sceltePerCategoria(tassonomia), [tassonomia]);
  // Una categoria disattivata dopo l'inserimento resta mostrata per chi la
  // aveva gia, senza renderla scegliibile per gli altri.
  const idValidi = useMemo(() => new Set(scelte.map((s) => s.id)), [scelte]);
  const valideConCorrente = useMemo(() => {
    const s = new Set(idValidi);
    if (corrente) s.add(corrente.categoria.id);
    return s;
  }, [idValidi, corrente]);
  const gruppi = useMemo(() => {
    const m = new Map<string, typeof scelte>();
    for (const s of scelte) {
      const k = s.gruppo ?? "";
      m.set(k, [...(m.get(k) ?? []), s]);
    }
    return [...m.entries()];
  }, [scelte]);

  const fotoCorrenti = useMemo(() => corrente?.immagini ?? [], [corrente]);
  const chiaveFoto = fotoCorrenti.join("|");
  useEffect(() => {
    if (chiaveFoto === "") return;
    let attivo = true;
    (async () => {
      const r = await servizio.urlFoto(chiaveFoto.split("|"));
      if (attivo && r.ok) setUrlFoto(r.data);
    })();
    return () => {
      attivo = false;
    };
  }, [servizio, chiaveFoto]);

  const salva = async (e: FormEvent) => {
    e.preventDefault();
    const v = validaModuloCantina(modulo, valideConCorrente);
    if (!v.ok) {
      setErrori(v.errori);
      return;
    }
    setErrori({});
    setInCorso(true);
    const r = await servizio.salva(corrente?.id ?? idNuovo, v.dati);
    setInCorso(false);
    if (!r.ok) return setMessaggio({ tono: "errore", testo: r.error });
    const eraNuovo = corrente === null;
    setCorrente(r.data);
    if (eraNuovo) {
      setMessaggio({ tono: "ok", testo: "Accessorio salvato (privato). Ora puoi aggiungere le foto." });
      await onCambiato("Accessorio aggiunto.");
    } else {
      await onCambiato("Accessorio aggiornato.");
      onChiudi();
    }
  };

  const aggiungiFoto = async (e: ChangeEvent<HTMLInputElement>) => {
    const scelto = e.target.files?.[0];
    e.target.value = "";
    if (!scelto || !corrente) return;
    if (fotoCorrenti.length >= MAX_FOTO_CANTINA_ACCESSORIO) {
      return setMessaggio({ tono: "errore", testo: `Al massimo ${MAX_FOTO_CANTINA_ACCESSORIO} foto.` });
    }
    setCaricoFoto(true);
    try {
      const client = getSupabaseClient();
      const utente = client ? (await client.auth.getUser()).data.user : null;
      if (!utente) return setMessaggio({ tono: "errore", testo: "Accedi per caricare le foto." });
      const webp = await preparaImmagineVetrina(scelto, "foto");
      const caricata = await servizio.caricaFoto(utente.id, corrente.id, webp);
      if (!caricata.ok) return setMessaggio({ tono: "errore", testo: caricata.error });
      const r = await servizio.impostaFoto(corrente.id, [...fotoCorrenti, caricata.data]);
      if (!r.ok) {
        // Il file non e collegato a niente: si toglie, senza lasciare orfani.
        await servizio.cancellaFoto([caricata.data]);
        return setMessaggio({ tono: "errore", testo: r.error });
      }
      setCorrente(r.data);
      setMessaggio({ tono: "ok", testo: "Foto aggiunta." });
      await onCambiato("Foto aggiunta.");
    } catch (err) {
      setMessaggio({ tono: "errore", testo: err instanceof Error ? err.message : "Immagine non valida." });
    } finally {
      setCaricoFoto(false);
    }
  };

  const rimuoviFoto = async (percorso: string) => {
    if (!corrente) return;
    const r = await servizio.impostaFoto(corrente.id, fotoCorrenti.filter((p) => p !== percorso));
    if (!r.ok) return setMessaggio({ tono: "errore", testo: r.error });
    // Prima si scollega, poi si cancella: il bucket rifiuta i file in uso.
    await servizio.cancellaFoto([percorso]);
    setCorrente(r.data);
    setMessaggio({ tono: "ok", testo: "Foto rimossa." });
    await onCambiato("Foto rimossa.");
  };

  const errore = (campo: keyof ModuloCantinaAccessorio) =>
    errori[campo] ? (
      <p role="alert" className="mt-1 text-xs text-bordeaux">
        {errori[campo]}
      </p>
    ) : null;

  return (
    <Dialog open onOpenChange={(aperto) => (aperto ? null : onChiudi())}>
      <DialogContent className="max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{corrente ? `Modifica «${corrente.nome}»` : "Nuovo accessorio"}</DialogTitle>
          <DialogDescription>
            L&apos;accessorio nasce privato. Tipo e nome bastano; il resto è facoltativo.
          </DialogDescription>
        </DialogHeader>

        <form onSubmit={salva} className="space-y-4" aria-label="Accessorio">
          <Avviso messaggio={messaggio} />

          <div>
            <Label htmlFor="ca-categoria">Tipo di accessorio</Label>
            <select
              id="ca-categoria"
              className={CAMPO}
              value={modulo.categoriaId}
              onChange={(e) => setModulo((m) => ({ ...m, categoriaId: e.target.value }))}
            >
              <option value="">Scegli…</option>
              {gruppi.map(([gruppo, voci]) =>
                gruppo === "" ? (
                  voci.map((s) => (
                    <option key={s.id} value={s.id}>
                      {s.etichetta}
                    </option>
                  ))
                ) : (
                  <optgroup key={gruppo} label={gruppo}>
                    {voci.map((s) => (
                      <option key={s.id} value={s.id}>
                        {s.etichetta}
                      </option>
                    ))}
                  </optgroup>
                ),
              )}
              {corrente && !idValidi.has(corrente.categoria.id) ? (
                <option value={corrente.categoria.id}>{etichettaCategoria(corrente.categoria)}</option>
              ) : null}
            </select>
            {errore("categoriaId")}
          </div>

          <div>
            <Label htmlFor="ca-nome">Nome</Label>
            <Input
              id="ca-nome"
              value={modulo.nome}
              maxLength={120}
              onChange={(e) => setModulo((m) => ({ ...m, nome: e.target.value }))}
            />
            {errore("nome")}
          </div>

          <div className="grid gap-3 sm:grid-cols-2">
            <div>
              <Label htmlFor="ca-condizione">Condizione</Label>
              <select
                id="ca-condizione"
                className={CAMPO}
                value={modulo.condizione}
                onChange={(e) =>
                  setModulo((m) => ({ ...m, condizione: e.target.value as ModuloCantinaAccessorio["condizione"] }))
                }
              >
                {CONDIZIONI_ACCESSORIO.map((c) => (
                  <option key={c} value={c}>
                    {ETICHETTE_CONDIZIONE[c]}
                  </option>
                ))}
              </select>
              {errore("condizione")}
            </div>
            <div>
              <Label htmlFor="ca-quantita">Quantità</Label>
              <Input
                id="ca-quantita"
                inputMode="numeric"
                value={modulo.quantita}
                onChange={(e) => setModulo((m) => ({ ...m, quantita: e.target.value }))}
              />
              {errore("quantita")}
            </div>
          </div>

          <div>
            <Label htmlFor="ca-marchio">Marchio (facoltativo)</Label>
            <Input
              id="ca-marchio"
              value={modulo.marchio}
              maxLength={80}
              onChange={(e) => setModulo((m) => ({ ...m, marchio: e.target.value }))}
            />
            {errore("marchio")}
          </div>

          <div>
            <Label htmlFor="ca-descrizione">Descrizione (facoltativa, visibile se esponi l&apos;accessorio)</Label>
            <Textarea
              id="ca-descrizione"
              rows={3}
              maxLength={1000}
              value={modulo.descrizione}
              onChange={(e) => setModulo((m) => ({ ...m, descrizione: e.target.value }))}
            />
            {errore("descrizione")}
          </div>

          <div>
            <Label htmlFor="ca-note">Note private (visibili solo a te)</Label>
            <Textarea
              id="ca-note"
              rows={2}
              maxLength={1000}
              value={modulo.note}
              onChange={(e) => setModulo((m) => ({ ...m, note: e.target.value }))}
            />
            {errore("note")}
          </div>

          {schedeCatalogo.length > 0 ? (
            <div>
              <Label htmlFor="ca-catalogo">Scheda Vinea collegata (facoltativa)</Label>
              <select
                id="ca-catalogo"
                className={CAMPO}
                value={modulo.catalogoSlug}
                onChange={(e) => setModulo((m) => ({ ...m, catalogoSlug: e.target.value }))}
              >
                <option value="">Nessuna</option>
                {schedeCatalogo.map((s) => (
                  <option key={s.slug} value={s.slug}>
                    {s.nome}
                  </option>
                ))}
              </select>
            </div>
          ) : null}

          <DialogFooter>
            <Button type="button" variant="ghost" onClick={onChiudi}>
              {corrente ? "Chiudi" : "Annulla"}
            </Button>
            <Button type="submit" disabled={inCorso}>
              {inCorso ? <Loader2 className="animate-spin" aria-hidden /> : null} Salva
            </Button>
          </DialogFooter>
        </form>

        {corrente ? (
          <div className="space-y-2 border-t border-border pt-4">
            <p className="text-sm font-medium">
              Foto (facoltative, massimo {MAX_FOTO_CANTINA_ACCESSORIO})
            </p>
            <p className="text-xs text-muted-foreground">
              Le foto sono private. Se esponi l&apos;accessorio nel profilo, diventano visibili insieme a lui.
            </p>
            <ul className="grid grid-cols-2 gap-2 sm:grid-cols-4">
              {fotoCorrenti.map((p, i) => (
                <li key={p} className="relative aspect-square overflow-hidden rounded-lg border border-border bg-secondary/40">
                  {urlFoto[p] ? (
                    /* eslint-disable-next-line @next/next/no-img-element -- WebP gia ridotta, URL firmata a tempo. */
                    <img src={urlFoto[p]} alt={`Foto ${i + 1}`} className="h-full w-full object-cover" />
                  ) : (
                    <span className="flex h-full w-full items-center justify-center text-antracite/40">
                      <ImageOff className="h-6 w-6" aria-hidden />
                    </span>
                  )}
                  <button
                    type="button"
                    aria-label={`Rimuovi foto ${i + 1}`}
                    onClick={() => rimuoviFoto(p)}
                    className="absolute right-1 top-1 rounded-full bg-background/90 p-1 shadow"
                  >
                    <Trash2 className="h-4 w-4" aria-hidden />
                  </button>
                </li>
              ))}
            </ul>
            <input
              ref={inputFoto}
              type="file"
              accept="image/jpeg,image/png,image/webp"
              className="sr-only"
              aria-label="Aggiungi una foto"
              onChange={aggiungiFoto}
            />
            <Button
              type="button"
              variant="outline"
              size="sm"
              disabled={caricoFoto || fotoCorrenti.length >= MAX_FOTO_CANTINA_ACCESSORIO}
              onClick={() => inputFoto.current?.click()}
            >
              {caricoFoto ? <Loader2 className="animate-spin" aria-hidden /> : <ImagePlus aria-hidden />} Aggiungi foto
            </Button>
          </div>
        ) : null}
      </DialogContent>
    </Dialog>
  );
}
