"use client";

import { useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Pencil, PackageX, Info } from "lucide-react";
import { firmaUploadFoto } from "@/app/vendi/actions";
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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { FotoGriglia } from "@/components/vinea/FotoGriglia";
import {
  MAX_FOTO,
  aggiungiFoto,
  creaBozzaFoto,
  percorsiFoto,
  percorsiSessioneNonUsati,
  revocaAnteprimeBlob,
  rimuoviFoto,
  sostituisciFoto,
  spostaFoto,
  type FotoModifica,
} from "@/lib/annunci/foto-modifica";
import { getSupabaseClient } from "@/lib/supabase/client";
import {
  BUCKET_ANNUNCI,
  createListingService,
  ETICHETTA_STATO,
  urlImmagine,
  type AnnuncioProprietario,
} from "@/services/listing-service";
import { AVVISO_RIMOZIONE_IRREVERSIBILE, EFFETTO_RIMOZIONE } from "@/lib/annunci/rimozione";
import type { Wine } from "@/data/wines";

const CONDIZIONI: Wine["condizione"][] = ["Perfetto", "Ottimo", "Buono"];

/**
 * Il pannello che il venditore vede sul proprio annuncio, e nessun altro.
 *
 * Esiste perché fino a oggi non c'era **nessun** comando per togliere un
 * annuncio dalla vendita: la RPC `listing_sospendi` è in produzione dalla Fase
 * 6b e non aveva un chiamante. La pagina dell'annuncio è il posto giusto — è
 * dove il venditore arriva per guardare cosa vede chi compra.
 *
 * Non decide da sé chi è il proprietario: riceve `annuncio` solo quando la
 * lettura lato server, filtrata dalla RLS, ha restituito una riga. Chi non è il
 * venditore non ottiene quella riga e questo componente non viene montato. La
 * garanzia sta nella policy, non in questo componente.
 */
export function ListingOwnerActions({ annuncio }: { annuncio: AnnuncioProprietario }) {
  const router = useRouter();
  const client = useMemo(() => getSupabaseClient(), []);
  const service = useMemo(() => createListingService(client), [client]);
  const listingId = annuncio.wine.listingId ?? annuncio.wine.id;

  const [sospensioneAperta, setSospensioneAperta] = useState(false);
  const [modificaAperta, setModificaAperta] = useState(false);
  const [sospensioneInCorso, setSospensioneInCorso] = useState(false);
  const [uploadInCorso, setUploadInCorso] = useState(false);
  const [salvataggioInCorso, setSalvataggioInCorso] = useState(false);
  const [puliziaInCorso, setPuliziaInCorso] = useState(false);

  const [prezzo, setPrezzo] = useState(String(annuncio.wine.prezzo));
  const [condizione, setCondizione] = useState<Wine["condizione"]>(annuncio.wine.condizione);
  const [conservazione, setConservazione] = useState(annuncio.wine.conservazione);
  const [storia, setStoria] = useState(annuncio.wine.storia);
  const [foto, setFoto] = useState<FotoModifica[]>([]);
  const [erroreUpload, setErroreUpload] = useState<string | null>(null);
  const [erroreSalvataggio, setErroreSalvataggio] = useState<string | null>(null);
  const [errorePulizia, setErrorePulizia] = useState<string | null>(null);

  const fotoRef = useRef<FotoModifica[]>([]);
  const percorsiSessioneRef = useRef(new Set<string>());
  const uploadAttivoRef = useRef<Promise<void> | null>(null);
  const salvataggioAttivoRef = useRef(false);
  const puliziaAttivaRef = useRef(false);
  const chiusuraRichiestaRef = useRef(false);

  const aggiornaFoto = (aggiornamento: (attuali: FotoModifica[]) => FotoModifica[]) => {
    const prossime = aggiornamento(fotoRef.current);
    fotoRef.current = prossime;
    setFoto(prossime);
  };

  const inizializzaBozza = () => {
    revocaAnteprimeBlob(fotoRef.current);
    const iniziali = creaBozzaFoto(annuncio.immaginiPercorsi, urlImmagine);
    fotoRef.current = iniziali;
    setFoto(iniziali);
    percorsiSessioneRef.current.clear();
    chiusuraRichiestaRef.current = false;
    setPrezzo(String(annuncio.wine.prezzo));
    setCondizione(annuncio.wine.condizione);
    setConservazione(annuncio.wine.conservazione);
    setStoria(annuncio.wine.storia);
    setErroreUpload(null);
    setErroreSalvataggio(null);
    setErrorePulizia(null);
  };

  const apriModifica = () => {
    inizializzaBozza();
    setModificaAperta(true);
  };

  const eliminaUploadSessione = async (percorsi: string[]): Promise<string | null> => {
    if (percorsi.length === 0) return null;
    if (!client) return "Connessione a Supabase non configurata.";

    const messaggio = "Non è stato possibile eliminare tutti gli upload temporanei.";
    try {
      const { error } = await client.storage.from(BUCKET_ANNUNCI).remove(percorsi);
      if (!error) return null;

      console.error("[annuncio] pulizia fotografie di sessione fallita:", error);
      return messaggio;
    } catch (error) {
      console.error("[annuncio] eccezione durante la pulizia fotografie di sessione:", error);
      return messaggio;
    }
  };

  const chiudiBozza = () => {
    revocaAnteprimeBlob(fotoRef.current);
    fotoRef.current = [];
    setFoto([]);
    setModificaAperta(false);
  };

  const annullaModifica = async () => {
    if (salvataggioAttivoRef.current) {
      toast.info("Attendi il termine del salvataggio.");
      return;
    }
    if (puliziaAttivaRef.current) return;

    // X, Escape, click esterno e pulsante Annulla arrivano tutti qui. Se un
    // upload termina mentre si sta chiudendo, il percorso firmato è già nel Set:
    // non entra più nella bozza e viene incluso nella stessa pulizia.
    chiusuraRichiestaRef.current = true;
    puliziaAttivaRef.current = true;
    setPuliziaInCorso(true);
    setErrorePulizia(null);

    try {
      await uploadAttivoRef.current;

      const errore = await eliminaUploadSessione([...percorsiSessioneRef.current]);
      if (errore) {
        setErrorePulizia(errore);
        toast.warning(`${errore} L'annuncio non è stato modificato.`);
      }
    } catch (error) {
      const messaggio = "Non è stato possibile completare la pulizia degli upload temporanei.";
      console.error("[annuncio] eccezione durante l'annullamento della modifica:", error);
      setErrorePulizia(messaggio);
      toast.warning(`${messaggio} L'annuncio non è stato modificato.`);
    } finally {
      percorsiSessioneRef.current.clear();
      chiudiBozza();
      puliziaAttivaRef.current = false;
      setPuliziaInCorso(false);
    }
  };

  const gestisciModificaAperta = (aperta: boolean) => {
    if (aperta) apriModifica();
    else void annullaModifica();
  };

  const avviaUpload = (
    file: File,
    applica: (nuova: FotoModifica) => void,
  ): Promise<void> => {
    if (uploadAttivoRef.current) return uploadAttivoRef.current;
    if (
      salvataggioAttivoRef.current ||
      puliziaAttivaRef.current ||
      chiusuraRichiestaRef.current
    ) {
      return Promise.resolve();
    }

    const operazione = (async () => {
      setUploadInCorso(true);
      setErroreUpload(null);

      if (!client) {
        const errore = "Connessione a Supabase non configurata.";
        setErroreUpload(errore);
        toast.error(errore);
        return;
      }

      const firma = await firmaUploadFoto(file.type, file.size, "annuncio");
      if (!firma.ok) {
        setErroreUpload(firma.error);
        toast.error(firma.error);
        return;
      }
      if (firma.data.bucket !== BUCKET_ANNUNCI) {
        const errore = "Il caricamento non ha restituito la destinazione prevista.";
        setErroreUpload(errore);
        toast.error(errore);
        return;
      }

      // Il percorso arriva dal signer autenticato, mai dal file o dalla UI. Si
      // registra prima dell'upload: anche un errore di rete dall'esito incerto
      // verrà compensato quando la bozza si chiude o viene salvata.
      percorsiSessioneRef.current.add(firma.data.percorso);
      const { error } = await client.storage
        .from(BUCKET_ANNUNCI)
        .uploadToSignedUrl(firma.data.percorso, firma.data.token, file);

      if (error) {
        console.error("[annuncio] upload fotografia fallito:", error);
        const messaggio = "Caricamento non riuscito. Riprova.";
        setErroreUpload(messaggio);
        toast.error(messaggio);
        return;
      }

      if (chiusuraRichiestaRef.current) return;

      applica({
        chiave: `sessione:${firma.data.percorso}`,
        percorso: firma.data.percorso,
        anteprima: URL.createObjectURL(file),
        origine: "sessione",
      });
      toast.success("Fotografia caricata");
    })().catch((error) => {
      const messaggio = "Caricamento non riuscito. Riprova.";
      console.error("[annuncio] eccezione durante l'upload fotografia:", error);
      setErroreUpload(messaggio);
      toast.error(messaggio);
    });

    uploadAttivoRef.current = operazione;
    return operazione.finally(() => {
      if (uploadAttivoRef.current === operazione) uploadAttivoRef.current = null;
      setUploadInCorso(false);
    });
  };

  const caricaFoto = (file: File) => {
    if (fotoRef.current.length >= MAX_FOTO) {
      toast.error(`Puoi caricare al massimo ${MAX_FOTO} fotografie.`);
      return Promise.resolve();
    }
    return avviaUpload(file, (nuova) => aggiornaFoto((attuali) => aggiungiFoto(attuali, nuova)));
  };

  const sostituisciFotografia = (indice: number, file: File) =>
    avviaUpload(file, (nuova) => {
      const precedente = fotoRef.current[indice];
      if (!precedente) return;
      if (precedente.anteprima.startsWith("blob:")) {
        URL.revokeObjectURL(precedente.anteprima);
      }
      aggiornaFoto((attuali) => sostituisciFoto(attuali, indice, nuova));
    });

  const rimuoviFotografia = (indice: number) => {
    const precedente = fotoRef.current[indice];
    if (precedente?.anteprima.startsWith("blob:")) {
      URL.revokeObjectURL(precedente.anteprima);
    }
    aggiornaFoto((attuali) => rimuoviFoto(attuali, indice));
  };

  const spostaFotografia = (indice: number, direzione: -1 | 1) => {
    aggiornaFoto((attuali) => spostaFoto(attuali, indice, direzione));
  };

  const rimuoviDallaVendita = async () => {
    setSospensioneInCorso(true);
    try {
      const esito = await service.sospendi(listingId);
      if (!esito.ok) {
        toast.error(esito.error);
        return;
      }
      toast.success("Annuncio rimosso dalla vendita");
      setSospensioneAperta(false);
      // I dati restano: la pagina si ricarica sulla lettura del proprietario,
      // che non filtra sullo stato.
      router.refresh();
    } finally {
      setSospensioneInCorso(false);
    }
  };

  const salvaModifiche = async () => {
    if (
      uploadAttivoRef.current ||
      salvataggioAttivoRef.current ||
      puliziaAttivaRef.current
    ) {
      return;
    }

    const centesimi = Math.round(Number(prezzo) * 100);
    if (!Number.isSafeInteger(centesimi) || centesimi <= 0) {
      toast.error("Inserisci un prezzo valido.");
      return;
    }

    const snapshotFoto = fotoRef.current;
    salvataggioAttivoRef.current = true;
    setSalvataggioInCorso(true);
    setErroreSalvataggio(null);

    try {
      const esito = await service.aggiorna(listingId, {
        prezzoCents: centesimi,
        condizione,
        conservazione: conservazione.trim(),
        storia: storia.trim(),
        immagini: percorsiFoto(snapshotFoto),
      });

      if (!esito.ok) {
        setErroreSalvataggio(esito.error);
        toast.error(esito.error);
        return;
      }
    } catch (error) {
      const messaggio = "Non è stato possibile salvare le modifiche. Riprova.";
      console.error("[annuncio] eccezione durante il salvataggio:", error);
      setErroreSalvataggio(messaggio);
      toast.error(messaggio);
      return;
    } finally {
      salvataggioAttivoRef.current = false;
      setSalvataggioInCorso(false);
    }

    toast.success("Annuncio aggiornato");
    chiusuraRichiestaRef.current = true;

    // Dopo il commit, gli upload ancora presenti nello snapshot sono fotografie
    // persistite. La pulizia riguarda soltanto gli altri percorsi firmati in
    // questa sessione (rimossi, sostituiti o falliti), mai fotografie preesistenti.
    const inutilizzati = percorsiSessioneNonUsati(percorsiSessioneRef.current, snapshotFoto);
    percorsiSessioneRef.current = new Set(inutilizzati);
    puliziaAttivaRef.current = true;
    setPuliziaInCorso(true);
    setErrorePulizia(null);

    try {
      const errore = await eliminaUploadSessione(inutilizzati);
      if (errore) {
        setErrorePulizia(errore);
        toast.warning(`${errore} Le modifiche all'annuncio sono state salvate.`);
      }
    } finally {
      percorsiSessioneRef.current.clear();
      chiudiBozza();
      puliziaAttivaRef.current = false;
      setPuliziaInCorso(false);
      router.refresh();
    }
  };

  const modificaInCorso = uploadInCorso || salvataggioInCorso || puliziaInCorso;

  return (
    <section className="rounded-2xl border border-oro/40 bg-oro/5 p-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <p className="text-sm font-medium">Il tuo annuncio</p>
          <p className="text-sm text-muted-foreground">
            Stato: <span className="font-medium">{ETICHETTA_STATO[annuncio.stato]}</span>
          </p>
        </div>

        <div className="flex flex-wrap gap-2">
          {annuncio.modificabile ? (
            <Button variant="outline" size="sm" onClick={apriModifica}>
              <Pencil className="mr-1 h-4 w-4" /> Modifica
            </Button>
          ) : null}

          {annuncio.sospendibile ? (
            <Button variant="outline" size="sm" onClick={() => setSospensioneAperta(true)}>
              <PackageX className="mr-1 h-4 w-4" /> Rimuovi dalla vendita
            </Button>
          ) : null}
        </div>
      </div>

      {annuncio.stato === "sospeso" ? (
        <p className="mt-3 flex gap-2 text-sm text-muted-foreground">
          <Info className="mt-0.5 h-4 w-4 shrink-0" />
          <span>
            Questo annuncio non è più visibile a chi compra. Prezzo, fotografie e descrizione
            restano qui, e la bottiglia è di nuovo libera in Cantina: per rimetterla in vendita si
            crea un annuncio nuovo, perché un annuncio rimosso non torna in vendita.
          </span>
        </p>
      ) : null}

      {/* --- Rimozione dalla vendita -------------------------------------- */}
      <Dialog open={sospensioneAperta} onOpenChange={setSospensioneAperta}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Rimuovere questo annuncio dalla vendita?</DialogTitle>
            {/*
              La domanda che si fa chi preme è «tornerà visibile?». La risposta
              onesta oggi è no: `sospeso` sta fuori dall'indice degli stati non
              terminali, `listing_pubblica` riparte solo da bozza o modifiche
              richieste, e nessuna funzione riporta un annuncio ad attivo. Dirlo
              qui costa una riga; scoprirlo dopo costa la fiducia.
            */}
            <DialogDescription>
              {EFFETTO_RIMOZIONE}
              <strong className="mt-2 block font-medium text-foreground">
                {AVVISO_RIMOZIONE_IRREVERSIBILE}
              </strong>
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button
              variant="ghost"
              onClick={() => setSospensioneAperta(false)}
              disabled={sospensioneInCorso}
            >
              Annulla
            </Button>
            <Button onClick={rimuoviDallaVendita} disabled={sospensioneInCorso}>
              {sospensioneInCorso ? "Rimozione…" : "Rimuovi dalla vendita"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* --- Modifica ------------------------------------------------------ */}
      <Dialog open={modificaAperta} onOpenChange={gestisciModificaAperta}>
        <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-2xl">
          <DialogHeader>
            <DialogTitle>Modifica annuncio</DialogTitle>
            <DialogDescription>
              Produttore, nome, annata e regione appartengono alla bottiglia e non si cambiano da
              qui.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-5">
            <div className="space-y-2">
              <div>
                <Label>Fotografie</Label>
                <p className="text-xs text-muted-foreground">
                  L'ordine mostrato sarà quello salvato. La prima fotografia è la principale.
                </p>
              </div>
              <FotoGriglia
                foto={foto}
                inCorso={modificaInCorso}
                onCarica={caricaFoto}
                onRimuovi={rimuoviFotografia}
                onSostituisci={sostituisciFotografia}
                onSposta={spostaFotografia}
                mostraPrincipale
              />
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="prezzo-modifica">Prezzo (€)</Label>
              <Input
                id="prezzo-modifica"
                inputMode="decimal"
                value={prezzo}
                onChange={(e) => setPrezzo(e.target.value)}
                disabled={modificaInCorso}
              />
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="condizione-modifica">Condizione</Label>
              <Select
                value={condizione}
                onValueChange={(v) => setCondizione(v as Wine["condizione"])}
                disabled={modificaInCorso}
              >
                <SelectTrigger id="condizione-modifica">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {CONDIZIONI.map((c) => (
                    <SelectItem key={c} value={c}>
                      {c}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="conservazione-modifica">Conservazione</Label>
              <Input
                id="conservazione-modifica"
                value={conservazione}
                onChange={(e) => setConservazione(e.target.value)}
                disabled={modificaInCorso}
              />
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="storia-modifica">Storia</Label>
              <Textarea
                id="storia-modifica"
                rows={4}
                value={storia}
                onChange={(e) => setStoria(e.target.value)}
                disabled={modificaInCorso}
              />
            </div>

            <div className="min-h-5 text-sm" aria-live="polite">
              {uploadInCorso ? (
                <p className="text-muted-foreground">Caricamento fotografia…</p>
              ) : null}
              {salvataggioInCorso ? (
                <p className="text-muted-foreground">Salvataggio annuncio…</p>
              ) : null}
              {puliziaInCorso ? (
                <p className="text-muted-foreground">Pulizia degli upload temporanei…</p>
              ) : null}
              {erroreUpload ? <p className="text-destructive">Upload: {erroreUpload}</p> : null}
              {erroreSalvataggio ? (
                <p className="text-destructive">Salvataggio: {erroreSalvataggio}</p>
              ) : null}
              {errorePulizia ? <p className="text-destructive">Pulizia: {errorePulizia}</p> : null}
            </div>
          </div>

          <DialogFooter>
            <Button
              variant="ghost"
              onClick={() => void annullaModifica()}
              disabled={salvataggioInCorso || puliziaInCorso}
            >
              {puliziaInCorso ? "Pulizia…" : "Annulla"}
            </Button>
            <Button onClick={salvaModifiche} disabled={modificaInCorso}>
              {salvataggioInCorso ? "Salvataggio…" : "Salva modifiche"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </section>
  );
}
