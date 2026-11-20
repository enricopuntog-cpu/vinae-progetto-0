"use client";

// WI-002 — stato del percorso «Fotografa l'etichetta» nel passo Identificazione.
//
// Fasi e responsabilità, una per volta e mai fuse:
//   scelta del file      → anteprima locale (URL `blob:`, mai caricata)
//   lettura (su richiesta) → OCR locale → campi modificabili
//   ricerca              → candidati dai dati Vinea (sorgente sostituibile)
//   conferma             → solo qui `applica` tocca il wizard
//
// La fotografia non lascia il dispositivo: l'unica uscita è `conservaFoto`, che
// l'utente deve chiedere con un gesto a parte.

import { useCallback, useEffect, useRef, useState } from "react";
import type { CandidatoValutato, SorgenteCandidati } from "@/lib/vendi/foto-etichetta/candidati";
import { type FaseRicerca, useRicercaCandidati } from "./useRicercaCandidati";
import type { CampiEstratti, QualitaLettura } from "@/lib/vendi/foto-etichetta/estrazione";
import { validaFileImmagine } from "@/lib/vendi/foto-etichetta/immagine";
import { type MotoreOcr, creaMotoreTesseract } from "@/lib/vendi/foto-etichetta/ocr";
import { leggiEtichetta } from "@/lib/vendi/foto-etichetta/pipeline";

export type CampiConfermati = {
  produttore: string;
  nome: string;
  annata: string;
  denominazione: string;
  formato: string;
};

export type FaseLettura = "vuota" | "anteprima" | "in_corso" | "letta" | "errore";
export type { FaseRicerca };

export type OpzioniFotoEtichetta = {
  sorgente: SorgenteCandidati;
  /** Chiamata solo alla lettura: il motore non esiste prima che l'utente la chieda. */
  creaMotore?: () => MotoreOcr;
  /** Preparazione dell'immagine (canvas nel browser); sostituibile nei test. */
  prepara?: (file: Blob) => Promise<Blob>;
  /** Il wizard riceve i campi solo da qui, dopo la conferma esplicita. */
  applica: (campi: CampiConfermati, candidato: CandidatoValutato | null) => void;
};

const CAMPI_VUOTI: CampiConfermati = {
  produttore: "",
  nome: "",
  annata: "",
  denominazione: "",
  formato: "",
};

export function useFotoEtichetta({
  sorgente,
  creaMotore = creaMotoreTesseract,
  prepara,
  applica,
}: OpzioniFotoEtichetta) {
  const [file, setFile] = useState<File | null>(null);
  const [anteprima, setAnteprima] = useState<string | null>(null);
  const [fase, setFase] = useState<FaseLettura>("vuota");
  const [progresso, setProgresso] = useState(0);
  const [messaggio, setMessaggio] = useState<string | null>(null);
  const [testo, setTesto] = useState("");
  const [qualita, setQualita] = useState<Exclude<QualitaLettura, "nessuna"> | null>(null);
  const [campi, setCampi] = useState<CampiConfermati>(CAMPI_VUOTI);
  const [annateAlternative, setAnnateAlternative] = useState<number[]>([]);
  const ricerca = useRicercaCandidati(sorgente);
  const {
    fase: faseRicerca,
    candidati,
    sintesi,
    messaggio: messaggioRicerca,
    selezionato,
    azzera: azzeraRicerca,
    seleziona: selezionaCandidato,
  } = ricerca;
  const [applicato, setApplicato] = useState(false);

  const abort = useRef<AbortController | null>(null);
  // Genera un numero per ogni richiesta: una risposta arrivata dopo un
  // annullamento o una nuova foto non deve sovrascrivere lo stato corrente.
  const generazione = useRef(0);
  const urlCorrente = useRef<string | null>(null);

  const rilascia = useCallback(() => {
    abort.current?.abort();
    abort.current = null;
    generazione.current++;
    azzeraRicerca();
    if (urlCorrente.current) {
      URL.revokeObjectURL(urlCorrente.current);
      urlCorrente.current = null;
    }
  }, [azzeraRicerca]);

  // Alla chiusura del passo l'anteprima e l'eventuale lettura in corso si liberano.
  useEffect(() => rilascia, [rilascia]);

  const azzeraRisultati = useCallback(() => {
    setTesto("");
    setQualita(null);
    setCampi(CAMPI_VUOTI);
    setAnnateAlternative([]);
    azzeraRicerca();
    setApplicato(false);
    setProgresso(0);
  }, [azzeraRicerca]);

  const scegliFile = useCallback(
    (nuovo: File | null) => {
      rilascia();
      azzeraRisultati();
      setMessaggio(null);
      if (!nuovo) {
        setFile(null);
        setAnteprima(null);
        setFase("vuota");
        return;
      }
      const validazione = validaFileImmagine(nuovo);
      if (!validazione.ok) {
        setFile(null);
        setAnteprima(null);
        setFase("errore");
        setMessaggio(validazione.messaggio);
        return;
      }
      const url = URL.createObjectURL(nuovo);
      urlCorrente.current = url;
      setFile(nuovo);
      setAnteprima(url);
      setFase("anteprima");
    },
    [azzeraRisultati, rilascia],
  );

  const cerca = useCallback(
    async (daCampi: CampiConfermati) => {
      const annata = Number.parseInt(daCampi.annata, 10);
      await ricerca.cerca({
        produttore: daCampi.produttore,
        nome: daCampi.nome,
        annata: Number.isInteger(annata) ? annata : null,
        formato: daCampi.formato || null,
      });
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps -- `ricerca.cerca` cambia solo con la sorgente
    [ricerca.cerca],
  );

  const leggi = useCallback(async () => {
    if (!file || fase === "in_corso") return;
    abort.current?.abort();
    const controllo = new AbortController();
    abort.current = controllo;
    const mia = ++generazione.current;
    azzeraRisultati();
    setMessaggio(null);
    setFase("in_corso");

    const esito = await leggiEtichetta(file, {
      motore: creaMotore(),
      prepara,
      segnale: controllo.signal,
      suProgresso: (p) => {
        if (mia === generazione.current) setProgresso(p);
      },
    });
    if (mia !== generazione.current) return;
    abort.current = null;

    if (!esito.ok) {
      setFase(esito.codice === "annullata" ? "anteprima" : "errore");
      setMessaggio(esito.codice === "annullata" ? null : esito.messaggio);
      return;
    }
    const iniziali: CampiConfermati = {
      produttore: esito.campi.produttore ?? "",
      nome: esito.campi.nome ?? "",
      annata: esito.campi.annata ? String(esito.campi.annata) : "",
      denominazione: esito.campi.denominazione ?? "",
      formato: esito.campi.formato ?? "",
    };
    setTesto(esito.testo);
    setQualita(esito.qualita);
    setCampi(iniziali);
    setAnnateAlternative(esito.campi.annateAlternative);
    setFase("letta");
    void cerca(iniziali);
  }, [azzeraRisultati, cerca, creaMotore, fase, file, prepara]);

  const annullaLettura = useCallback(() => {
    abort.current?.abort();
  }, []);

  const modificaCampo = useCallback((chiave: keyof CampiConfermati, valore: string) => {
    setCampi((c) => ({ ...c, [chiave]: valore }));
    // Correggere produttore o nome rende superata la scelta di un vino trovato:
    // al wizard devono arrivare i campi che l'utente vede, non quelli del candidato.
    if (chiave === "produttore" || chiave === "nome") selezionaCandidato(null);
    setApplicato(false);
  }, [selezionaCandidato]);

  const seleziona = useCallback(
    (id: string | null) => {
      selezionaCandidato(id);
      setApplicato(false);
    },
    [selezionaCandidato],
  );

  /** L'unico punto in cui il percorso scrive nel wizard, e solo su richiesta. */
  const conferma = useCallback(() => {
    const scelto = candidati.find((c) => c.id === selezionato) ?? null;
    applica(campi, scelto);
    setApplicato(true);
  }, [applica, campi, candidati, selezionato]);

  const ricomincia = useCallback(() => scegliFile(null), [scegliFile]);

  return {
    file,
    anteprima,
    fase,
    progresso,
    messaggio,
    testo,
    qualita,
    campi,
    annateAlternative,
    faseRicerca,
    candidati,
    sintesi,
    messaggioRicerca,
    selezionato,
    applicato,
    scegliFile,
    leggi,
    annullaLettura,
    modificaCampo,
    cercaDiNuovo: () => void cerca(campi),
    seleziona,
    conferma,
    ricomincia,
  };
}

export type StatoFotoEtichetta = ReturnType<typeof useFotoEtichetta>;
export type { CampiEstratti };
