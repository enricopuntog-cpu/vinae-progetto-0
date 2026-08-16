// Fase 12a - derivazioni pure dell'elenco club.
//
// Stanno qui e non dentro la pagina per due motivi. Sono provabili senza
// montare React, ed e cosi che i filtri restano una derivazione: la lezione di
// 10c e che ripulire un risultato derivato appartiene a una derivazione e mai
// a un effetto, perche la regola `set-state-in-effect` di Next 16 rifiuta un
// setState sincrono dentro un effetto - e ha ragione.
//
// Nessun "use client" e nessun import di React: questo file e condiviso fra il
// componente server che legge i club e quello client che li filtra.

import type { Club } from "@/services/types";

export type FiltriClub = {
  testo: string;
  territorio: string;
  denominazione: string;
  produttore: string;
  tipologia: string;
};

export type CampoFiltro = Exclude<keyof FiltriClub, "testo">;

export const FILTRI_VUOTI: FiltriClub = {
  testo: "",
  territorio: "",
  denominazione: "",
  produttore: "",
  tipologia: "",
};

export const ETICHETTE_FILTRO: Record<CampoFiltro, string> = {
  territorio: "Territorio",
  denominazione: "Denominazione",
  produttore: "Produttore",
  tipologia: "Tipologia",
};

export const filtraClub = (clubs: Club[], filtri: FiltriClub): Club[] => {
  const testo = filtri.testo.trim().toLowerCase();
  return clubs.filter((c) => {
    if (
      testo &&
      !c.nome.toLowerCase().includes(testo) &&
      !c.descrizione.toLowerCase().includes(testo)
    ) {
      return false;
    }
    if (filtri.territorio && c.territorio !== filtri.territorio) return false;
    if (filtri.denominazione && c.denominazione !== filtri.denominazione) return false;
    if (filtri.produttore && c.produttore !== filtri.produttore) return false;
    if (filtri.tipologia && c.tipologia !== filtri.tipologia) return false;
    return true;
  });
};

// Le opzioni dei quattro filtri si ricavano dai club che esistono davvero, non
// da un elenco scritto a mano. In `frontend/` erano quattro costanti
// (src/routes/community.index.tsx e il page-client rimosso dalla #44): con dati
// reali quella lista si sarebbe scollata dal contenuto al primo club aggiunto,
// offrendo un filtro che non seleziona nulla e nascondendone uno che servirebbe.
export const opzioniFiltro = (clubs: Club[], campo: CampoFiltro): string[] => {
  const valori = new Set<string>();
  for (const c of clubs) {
    const v = c[campo];
    if (v) valori.add(v);
  }
  return [...valori].sort((a, b) => a.localeCompare(b, "it"));
};

// Gli assi valorizzati di un club, nell'ordine in cui la scheda li mostra.
// Un club per tipologia non ha territorio e uno per territorio non ha
// produttore: le colonne sono opzionali, e questa funzione e il punto unico in
// cui l'assenza diventa "non mostrare" invece di "mostra vuoto".
export const assiClub = (club: Club): string[] =>
  [club.territorio, club.denominazione, club.produttore, club.tipologia].filter(
    (v): v is string => Boolean(v),
  );
