"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState, type ChangeEvent, type FormEvent } from "react";
import { ArrowLeft, Eye, ImagePlus, Loader2, Plus, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { ErrorState, LoadingBlock } from "@/components/vinea/States";
import {
  CONDIZIONI_ACCESSORIO,
  ETICHETTE_CONDIZIONE,
  ETICHETTE_STATO,
  MAX_ATTRIBUTI_ACCESSORIO,
  MAX_IMMAGINI_ACCESSORIO,
  percorsiAccessori,
  slugDaNome,
  urlImmagineAccessorio,
  type CategoriaAdmin,
  type SchedaAccessorioAdmin,
} from "@/lib/accessori/accessori";
import {
  TRANSIZIONI_STATO,
  moduloCategoriaVuoto,
  moduloDaScheda,
  moduloSchedaVuoto,
  validaModuloCategoria,
  validaModuloScheda,
  type ModuloCategoria,
  type ModuloScheda,
} from "@/lib/accessori/modulo";
import { preparaImmagineVetrina } from "@/lib/partner/prepara-immagine-vetrina";
import { getSupabaseClient } from "@/lib/supabase/client";
import { creaAccessoriAdminService } from "@/services/accessori-service";

/**
 * Amministrazione degli Accessori (VPM-015A): categorie, schede e bozze.
 *
 * L'interfaccia è una comodità: ogni porta `accessori_admin_*` ricontrolla il
 * ruolo admin reale in `public.user_roles`, e i trigger del database
 * ricontrollano forma, stati e immagini. Nessun campo economico: non esistono
 * prezzo, valuta, varianti, dimensioni o peso (differiti). La visibilità
 * pubblica si MOSTRA ma non si cambia da qui: è una decisione del titolare.
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

export function AccessoriAdminClient() {
  const servizio = useMemo(() => creaAccessoriAdminService(getSupabaseClient()), []);

  const [caricamento, setCaricamento] = useState(true);
  const [errore, setErrore] = useState<string | null>(null);
  const [categorie, setCategorie] = useState<CategoriaAdmin[]>([]);
  const [schede, setSchede] = useState<SchedaAccessorioAdmin[]>([]);
  const [visibilita, setVisibilita] = useState<boolean | null>(null);
  const [messaggio, setMessaggio] = useState<Messaggio>(null);

  const ricarica = useCallback(async () => {
    setErrore(null);
    const [c, s, v] = await Promise.all([
      servizio.categorie(),
      servizio.elenco(),
      servizio.visibilitaPubblica(),
    ]);
    if (!c.ok) setErrore(c.error);
    else if (!s.ok) setErrore(s.error);
    else {
      setCategorie(c.data);
      setSchede(s.data);
    }
    setVisibilita(v.ok ? v.data : null);
    setCaricamento(false);
  }, [servizio]);

  useEffect(() => {
    void ricarica();
  }, [ricarica]);

  if (caricamento) return <LoadingBlock label="Caricamento degli accessori" />;
  if (errore) return <ErrorState message={errore} onRetry={() => void ricarica()} home={false} />;

  return (
    <div className="mx-auto max-w-5xl space-y-10 px-4 py-8">
      <header className="space-y-3">
        <Link href="/admin" className="inline-flex items-center gap-1 text-sm text-antracite/70 hover:text-bordeaux">
          <ArrowLeft className="h-4 w-4" aria-hidden /> Area admin
        </Link>
        <h1 className="font-serif text-3xl font-semibold text-antracite">Accessori — catalogo Beta</h1>
        <p className="max-w-2xl text-sm text-antracite/75">
          Bozze e schede del catalogo accessori: una vetrina in preparazione, senza vendite.
        </p>
        <div className="flex flex-wrap items-center gap-3 rounded-xl border border-border bg-crema px-4 py-3 text-sm">
          <span>
            Visibilità pubblica (database):{" "}
            <strong data-testid="accessori-visibilita">
              {visibilita === null ? "non leggibile" : visibilita ? "ACCESA" : "SPENTA"}
            </strong>
          </span>
          <Button asChild variant="outline" size="sm">
            <Link href={percorsiAccessori.indice}>
              <Eye /> Apri l'anteprima
            </Link>
          </Button>
        </div>
        <p className="text-xs text-antracite/60">
          Il pubblico vede il catalogo solo con <code>ACCESSORI_ENABLED</code> e{" "}
          <code>NEXT_PUBLIC_ACCESSORI_ENABLED</code> uguali a <code>true</code> <em>e</em> la
          visibilità del database accesa. L'accensione è una decisione del titolare.
        </p>
      </header>

      <Avviso messaggio={messaggio} />

      <SezioneSchede
        servizio={servizio}
        categorie={categorie}
        schede={schede}
        onCambiato={ricarica}
        onMessaggio={setMessaggio}
      />
      <SezioneCategorie
        servizio={servizio}
        categorie={categorie}
        onCambiato={ricarica}
        onMessaggio={setMessaggio}
      />
    </div>
  );
}

type Servizio = ReturnType<typeof creaAccessoriAdminService>;

const nomeCategoria = (categorie: readonly CategoriaAdmin[], c: CategoriaAdmin): string => {
  const genitore = categorie.find((g) => g.id === c.genitoreId);
  return genitore ? `${genitore.nome} › ${c.nome}` : c.nome;
};

// ---------------------------------------------------------------------------
// Categorie
// ---------------------------------------------------------------------------

function SezioneCategorie({
  servizio,
  categorie,
  onCambiato,
  onMessaggio,
}: {
  servizio: Servizio;
  categorie: CategoriaAdmin[];
  onCambiato: () => Promise<void>;
  onMessaggio: (m: Messaggio) => void;
}) {
  const [modifica, setModifica] = useState<string | null | undefined>(undefined);
  const [modulo, setModulo] = useState<ModuloCategoria>(moduloCategoriaVuoto());
  const [invio, setInvio] = useState(false);

  const apri = (c: CategoriaAdmin | null) => {
    setModifica(c ? c.id : null);
    setModulo(
      c
        ? {
            genitoreId: c.genitoreId ?? "",
            slug: c.slug,
            slugManuale: true,
            nome: c.nome,
            descrizione: c.descrizione,
            ordine: String(c.ordine),
            attiva: c.attiva,
          }
        : moduloCategoriaVuoto(),
    );
  };

  const salva = async (e: FormEvent) => {
    e.preventDefault();
    const esito = validaModuloCategoria(modulo);
    if (!esito.ok) return onMessaggio({ tono: "errore", testo: esito.errore });
    setInvio(true);
    const r = await servizio.salvaCategoria(modifica ?? null, esito.dati);
    setInvio(false);
    if (!r.ok) return onMessaggio({ tono: "errore", testo: r.error });
    onMessaggio({ tono: "ok", testo: "Categoria salvata." });
    setModifica(undefined);
    await onCambiato();
  };

  const principali = categorie.filter((c) => c.genitoreId === null);

  return (
    <section aria-labelledby="accessori-categorie" className="space-y-4">
      <div className="flex items-center justify-between gap-3">
        <h2 id="accessori-categorie" className="font-serif text-2xl font-semibold">
          Categorie
        </h2>
        <Button size="sm" variant="outline" onClick={() => apri(null)}>
          <Plus /> Nuova categoria
        </Button>
      </div>

      {modifica !== undefined ? (
        <form onSubmit={salva} className="grid gap-3 rounded-xl border border-border bg-card p-4 md:grid-cols-2">
          <div>
            <Label htmlFor="cat-nome">Nome</Label>
            <Input
              id="cat-nome"
              value={modulo.nome}
              maxLength={80}
              onChange={(e) =>
                setModulo((m) => ({
                  ...m,
                  nome: e.target.value,
                  slug: m.slugManuale ? m.slug : slugDaNome(e.target.value).slice(0, 60),
                }))
              }
            />
          </div>
          <div>
            <Label htmlFor="cat-slug">Indirizzo</Label>
            <Input
              id="cat-slug"
              value={modulo.slug}
              maxLength={60}
              onChange={(e) => setModulo((m) => ({ ...m, slug: e.target.value, slugManuale: true }))}
            />
          </div>
          <div>
            <Label htmlFor="cat-genitore">Categoria genitore</Label>
            <select
              id="cat-genitore"
              className={CAMPO}
              value={modulo.genitoreId}
              onChange={(e) => setModulo((m) => ({ ...m, genitoreId: e.target.value }))}
            >
              <option value="">Nessuna (primo livello)</option>
              {principali
                .filter((p) => p.id !== modifica)
                .map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.nome}
                  </option>
                ))}
            </select>
          </div>
          <div>
            <Label htmlFor="cat-ordine">Ordine</Label>
            <Input
              id="cat-ordine"
              inputMode="numeric"
              value={modulo.ordine}
              onChange={(e) => setModulo((m) => ({ ...m, ordine: e.target.value }))}
            />
          </div>
          <div className="md:col-span-2">
            <Label htmlFor="cat-descrizione">Descrizione</Label>
            <Textarea
              id="cat-descrizione"
              rows={2}
              maxLength={500}
              value={modulo.descrizione}
              onChange={(e) => setModulo((m) => ({ ...m, descrizione: e.target.value }))}
            />
          </div>
          <label className="flex items-center gap-2 text-sm md:col-span-2">
            <input
              type="checkbox"
              checked={modulo.attiva}
              onChange={(e) => setModulo((m) => ({ ...m, attiva: e.target.checked }))}
            />
            Categoria attiva (visibile nel catalogo)
          </label>
          <div className="flex gap-2 md:col-span-2">
            <Button type="submit" disabled={invio}>
              {invio ? <Loader2 className="animate-spin" /> : null} Salva categoria
            </Button>
            <Button type="button" variant="ghost" onClick={() => setModifica(undefined)}>
              Annulla
            </Button>
          </div>
        </form>
      ) : null}

      <ul className="divide-y divide-border rounded-xl border border-border bg-card" data-testid="accessori-admin-categorie">
        {categorie.map((c) => (
          <li key={c.id} className="flex flex-wrap items-center justify-between gap-2 px-4 py-2.5 text-sm">
            <span className={c.genitoreId ? "pl-4" : "font-medium"}>
              {c.nome} <span className="text-antracite/50">/{c.slug}</span>
              {!c.attiva ? <span className="ml-2 rounded-full bg-secondary px-2 py-0.5 text-xs">Disattivata</span> : null}
            </span>
            <span className="flex items-center gap-3">
              <span className="text-antracite/60">{c.accessori} schede</span>
              <Button size="sm" variant="ghost" onClick={() => apri(c)}>
                Modifica
              </Button>
            </span>
          </li>
        ))}
      </ul>
    </section>
  );
}

// ---------------------------------------------------------------------------
// Schede
// ---------------------------------------------------------------------------

function SezioneSchede({
  servizio,
  categorie,
  schede,
  onCambiato,
  onMessaggio,
}: {
  servizio: Servizio;
  categorie: CategoriaAdmin[];
  schede: SchedaAccessorioAdmin[];
  onCambiato: () => Promise<void>;
  onMessaggio: (m: Messaggio) => void;
}) {
  const [aperta, setAperta] = useState<string | null | undefined>(undefined);
  const scheda = schede.find((s) => s.id === aperta) ?? null;

  return (
    <section aria-labelledby="accessori-schede" className="space-y-4">
      <div className="flex items-center justify-between gap-3">
        <h2 id="accessori-schede" className="font-serif text-2xl font-semibold">
          Schede
        </h2>
        <Button size="sm" onClick={() => setAperta(null)} disabled={categorie.length === 0}>
          <Plus /> Nuova scheda
        </Button>
      </div>

      {aperta !== undefined ? (
        <EditorScheda
          // La chiave rimonta il modulo quando si cambia scheda.
          key={aperta ?? "nuova"}
          servizio={servizio}
          categorie={categorie}
          scheda={scheda}
          onChiudi={() => setAperta(undefined)}
          onCambiato={onCambiato}
          onMessaggio={onMessaggio}
          onCreata={(id) => setAperta(id)}
        />
      ) : null}

      {schede.length === 0 ? (
        <p className="rounded-xl border border-dashed border-border bg-secondary/40 px-4 py-8 text-center text-sm text-antracite/70" data-testid="accessori-admin-vuoto">
          Nessuna scheda ancora. Crea la prima bozza: resterà invisibile al pubblico finché non la pubblichi.
        </p>
      ) : (
        <ul className="divide-y divide-border rounded-xl border border-border bg-card" data-testid="accessori-admin-schede">
          {schede.map((s) => (
            <li key={s.id} className="flex flex-wrap items-center justify-between gap-2 px-4 py-3 text-sm">
              <span>
                <span className="font-medium">{s.nome}</span>{" "}
                <span className="text-antracite/50">/{s.slug}</span>
                <span className="ml-2 rounded-full bg-secondary px-2 py-0.5 text-xs">{ETICHETTE_STATO[s.stato]}</span>
                <span className="block text-xs text-antracite/60">{s.categoria.nome}</span>
              </span>
              <Button size="sm" variant="ghost" onClick={() => setAperta(s.id)}>
                Modifica
              </Button>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function EditorScheda({
  servizio,
  categorie,
  scheda,
  onChiudi,
  onCambiato,
  onMessaggio,
  onCreata,
}: {
  servizio: Servizio;
  categorie: CategoriaAdmin[];
  scheda: SchedaAccessorioAdmin | null;
  onChiudi: () => void;
  onCambiato: () => Promise<void>;
  onMessaggio: (m: Messaggio) => void;
  onCreata: (id: string) => void;
}) {
  const [modulo, setModulo] = useState<ModuloScheda>(() =>
    scheda ? moduloDaScheda(scheda) : moduloSchedaVuoto(),
  );
  const [invio, setInvio] = useState(false);
  const [carico, setCarico] = useState(false);
  const file = useRef<HTMLInputElement>(null);

  const slugBloccato = scheda?.pubblicatoIl != null;
  const immagini = scheda?.immagini ?? [];

  const salva = async (e: FormEvent) => {
    e.preventDefault();
    const esito = validaModuloScheda(modulo);
    if (!esito.ok) return onMessaggio({ tono: "errore", testo: esito.errore });
    setInvio(true);
    const r = await servizio.salva(scheda?.id ?? null, esito.dati);
    setInvio(false);
    if (!r.ok) return onMessaggio({ tono: "errore", testo: r.error });
    onMessaggio({
      tono: "ok",
      testo: scheda ? "Scheda salvata." : "Bozza creata: ora puoi aggiungere le immagini.",
    });
    await onCambiato();
    if (!scheda) onCreata(r.data.id);
  };

  const cambiaStato = async (verso: "bozza" | "pubblicato" | "archiviato") => {
    if (!scheda) return;
    setInvio(true);
    const r = await servizio.impostaStato(scheda.id, verso);
    setInvio(false);
    if (!r.ok) return onMessaggio({ tono: "errore", testo: r.error });
    onMessaggio({ tono: "ok", testo: `Scheda: ${ETICHETTE_STATO[r.data.stato].toLowerCase()}.` });
    await onCambiato();
  };

  const aggiungiImmagine = async (e: ChangeEvent<HTMLInputElement>) => {
    const scelto = e.target.files?.[0];
    e.target.value = "";
    if (!scelto || !scheda) return;
    if (immagini.length >= MAX_IMMAGINI_ACCESSORIO) {
      return onMessaggio({ tono: "errore", testo: `Al massimo ${MAX_IMMAGINI_ACCESSORIO} immagini.` });
    }
    setCarico(true);
    try {
      const webp = await preparaImmagineVetrina(scelto, "foto");
      const caricata = await servizio.caricaImmagine(scheda.id, webp);
      if (!caricata.ok) return onMessaggio({ tono: "errore", testo: caricata.error });
      const r = await servizio.impostaImmagini(scheda.id, [...immagini, caricata.data]);
      if (!r.ok) {
        // Il file non e collegato a niente: si toglie, senza lasciare orfani.
        await servizio.cancellaImmagini([caricata.data]);
        return onMessaggio({ tono: "errore", testo: r.error });
      }
      onMessaggio({ tono: "ok", testo: "Immagine aggiunta." });
      await onCambiato();
    } catch (err) {
      onMessaggio({ tono: "errore", testo: err instanceof Error ? err.message : "Immagine non valida." });
    } finally {
      setCarico(false);
    }
  };

  const rimuoviImmagine = async (percorso: string) => {
    if (!scheda) return;
    const r = await servizio.impostaImmagini(scheda.id, immagini.filter((p) => p !== percorso));
    if (!r.ok) return onMessaggio({ tono: "errore", testo: r.error });
    // Prima si scollega, poi si cancella: il bucket rifiuta i file in uso.
    await servizio.cancellaImmagini([percorso]);
    onMessaggio({ tono: "ok", testo: "Immagine rimossa." });
    await onCambiato();
  };

  const categorieAttive = categorie.filter((c) => c.attiva || c.id === modulo.categoriaId);

  return (
    <form onSubmit={salva} className="space-y-4 rounded-xl border border-border bg-card p-4" aria-label="Scheda accessorio">
      <div className="flex items-center justify-between gap-2">
        <h3 className="font-serif text-xl font-semibold">{scheda ? `Modifica «${scheda.nome}»` : "Nuova scheda"}</h3>
        <Button type="button" variant="ghost" size="sm" onClick={onChiudi}>
          Chiudi
        </Button>
      </div>

      <div className="grid gap-3 md:grid-cols-2">
        <div>
          <Label htmlFor="acc-nome">Nome</Label>
          <Input
            id="acc-nome"
            value={modulo.nome}
            maxLength={120}
            onChange={(e) =>
              setModulo((m) => ({
                ...m,
                nome: e.target.value,
                slug: m.slugManuale ? m.slug : slugDaNome(e.target.value),
              }))
            }
          />
        </div>
        <div>
          <Label htmlFor="acc-slug">Indirizzo {slugBloccato ? "(bloccato: già pubblicata)" : ""}</Label>
          <Input
            id="acc-slug"
            value={modulo.slug}
            maxLength={80}
            disabled={slugBloccato}
            onChange={(e) => setModulo((m) => ({ ...m, slug: e.target.value, slugManuale: true }))}
          />
        </div>
        <div>
          <Label htmlFor="acc-categoria">Categoria</Label>
          <select
            id="acc-categoria"
            className={CAMPO}
            value={modulo.categoriaId}
            onChange={(e) => setModulo((m) => ({ ...m, categoriaId: e.target.value }))}
          >
            <option value="">Scegli…</option>
            {categorieAttive.map((c) => (
              <option key={c.id} value={c.id}>
                {nomeCategoria(categorie, c)}
              </option>
            ))}
          </select>
        </div>
        <div>
          <Label htmlFor="acc-marchio">Marchio (facoltativo)</Label>
          <Input
            id="acc-marchio"
            value={modulo.marchio}
            maxLength={80}
            onChange={(e) => setModulo((m) => ({ ...m, marchio: e.target.value }))}
          />
        </div>
        <div>
          <Label htmlFor="acc-condizione">Condizione</Label>
          <select
            id="acc-condizione"
            className={CAMPO}
            value={modulo.condizione}
            onChange={(e) =>
              setModulo((m) => ({ ...m, condizione: e.target.value as ModuloScheda["condizione"] }))
            }
          >
            {CONDIZIONI_ACCESSORIO.map((c) => (
              <option key={c} value={c}>
                {ETICHETTE_CONDIZIONE[c]}
              </option>
            ))}
          </select>
        </div>
        <div>
          <Label htmlFor="acc-quantita">Quantità interna (non pubblica)</Label>
          <Input
            id="acc-quantita"
            inputMode="numeric"
            value={modulo.quantita}
            onChange={(e) => setModulo((m) => ({ ...m, quantita: e.target.value }))}
          />
        </div>
        <div className="md:col-span-2">
          <Label htmlFor="acc-descrizione">Descrizione (almeno 10 caratteri per pubblicare)</Label>
          <Textarea
            id="acc-descrizione"
            rows={4}
            maxLength={2000}
            value={modulo.descrizione}
            onChange={(e) => setModulo((m) => ({ ...m, descrizione: e.target.value }))}
          />
        </div>
      </div>

      <fieldset className="space-y-2">
        <legend className="text-sm font-medium">Attributi (facoltativi, massimo {MAX_ATTRIBUTI_ACCESSORIO})</legend>
        {modulo.attributi.map((riga, i) => (
          <div key={i} className="flex gap-2">
            <Input
              aria-label={`Nome attributo ${i + 1}`}
              placeholder="es. Materiale"
              value={riga.chiave}
              onChange={(e) =>
                setModulo((m) => ({
                  ...m,
                  attributi: m.attributi.map((r, j) => (j === i ? { ...r, chiave: e.target.value } : r)),
                }))
              }
            />
            <Input
              aria-label={`Valore attributo ${i + 1}`}
              placeholder="es. Cristallo"
              value={riga.valore}
              maxLength={120}
              onChange={(e) =>
                setModulo((m) => ({
                  ...m,
                  attributi: m.attributi.map((r, j) => (j === i ? { ...r, valore: e.target.value } : r)),
                }))
              }
            />
            <Button
              type="button"
              variant="ghost"
              size="icon"
              aria-label={`Rimuovi attributo ${i + 1}`}
              onClick={() => setModulo((m) => ({ ...m, attributi: m.attributi.filter((_, j) => j !== i) }))}
            >
              <Trash2 />
            </Button>
          </div>
        ))}
        {modulo.attributi.length < MAX_ATTRIBUTI_ACCESSORIO ? (
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={() => setModulo((m) => ({ ...m, attributi: [...m.attributi, { chiave: "", valore: "" }] }))}
          >
            <Plus /> Aggiungi attributo
          </Button>
        ) : null}
      </fieldset>

      <div className="flex flex-wrap gap-2">
        <Button type="submit" disabled={invio}>
          {invio ? <Loader2 className="animate-spin" /> : null} {scheda ? "Salva modifiche" : "Crea bozza"}
        </Button>
        {scheda
          ? TRANSIZIONI_STATO[scheda.stato].map((t) => (
              <Button
                key={t.verso}
                type="button"
                variant="outline"
                disabled={invio}
                onClick={() => void cambiaStato(t.verso)}
              >
                {t.etichetta}
              </Button>
            ))
          : null}
      </div>

      {scheda ? (
        <section aria-labelledby="acc-immagini" className="space-y-2 border-t border-border pt-4">
          <h4 id="acc-immagini" className="text-sm font-medium">
            Immagini ({immagini.length}/{MAX_IMMAGINI_ACCESSORIO}) — la prima è la copertina
          </h4>
          <ul className="grid grid-cols-3 gap-2 sm:grid-cols-6">
            {immagini.map((p) => {
              const url = urlImmagineAccessorio(p);
              return (
                <li key={p} className="relative aspect-square overflow-hidden rounded-lg border border-border">
                  {url ? (
                    /* eslint-disable-next-line @next/next/no-img-element -- anteprima di un file gia caricato. */
                    <img src={url} alt="Immagine della scheda" className="h-full w-full object-cover" />
                  ) : null}
                  <Button
                    type="button"
                    size="icon"
                    variant="secondary"
                    className="absolute right-1 top-1 h-7 w-7"
                    aria-label="Rimuovi immagine"
                    onClick={() => void rimuoviImmagine(p)}
                  >
                    <Trash2 />
                  </Button>
                </li>
              );
            })}
          </ul>
          <input
            ref={file}
            type="file"
            accept="image/jpeg,image/png,image/webp"
            className="sr-only"
            aria-label="Aggiungi immagine"
            onChange={(e) => void aggiungiImmagine(e)}
          />
          <Button
            type="button"
            variant="outline"
            size="sm"
            disabled={carico || immagini.length >= MAX_IMMAGINI_ACCESSORIO}
            onClick={() => file.current?.click()}
          >
            {carico ? <Loader2 className="animate-spin" /> : <ImagePlus />} Aggiungi immagine
          </Button>
        </section>
      ) : (
        <p className="border-t border-border pt-4 text-sm text-antracite/65">
          Dopo aver creato la bozza potrai aggiungere le immagini.
        </p>
      )}
    </form>
  );
}
