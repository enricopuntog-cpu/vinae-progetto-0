// Fase 12 - le due selezioni di club che la Home mostra.
//
// Stanno qui e non dentro la pagina per la stessa ragione di club-view.ts: sono
// derivazioni pure dell'elenco gia letto, provabili senza montare React, e la
// regola che conta - un club seguito non ricompare fra quelli da scoprire - e
// una regola, non un dettaglio di rendering.
//
// Nessun "use client" e nessun import di React: il modulo e condiviso fra il
// componente server che legge i club e quello client che li disegna.
//
// Non c'e nessun motore di raccomandazione qui dentro, e non deve entrarci.
// `scopriClub` ordina per una colonna che il server calcola gia - `membri` - e
// non compone punteggi: la Home mostra i club piu frequentati fra quelli che
// chi guarda non segue, che e una selezione, non un consiglio.

import type { Club } from "@/services/types";

/**
 * Quanti club mostra ciascuna delle due sezioni della Home.
 *
 * Tre e la larghezza della griglia desktop: una riga piena e nessuna riga
 * spaiata. La Home e un'anticipazione, non l'elenco - quello e /community, e
 * ogni sezione ci rimanda.
 */
export const LIMITE_CLUB_HOME = 3;

// Ordine deterministico a parita di membri: senza secondo criterio due club con
// lo stesso conteggio si scambierebbero di posto fra una lettura e l'altra, e
// la Home cambierebbe da sola sotto gli occhi di chi la ricarica.
const perMembriPoiNome = (a: Club, b: Club): number =>
  b.membri - a.membri || a.nome.localeCompare(b.nome, "it");

/**
 * I club che l'utente segue gia.
 *
 * `seguito` e lo stato del solo chiamante, calcolato da `public_clubs` con
 * auth.uid(): per un anonimo e sempre falso, quindi questa lista e vuota senza
 * bisogno di un ramo dedicato.
 */
export const clubSeguiti = (clubs: Club[], limite = LIMITE_CLUB_HOME): Club[] =>
  clubs
    .filter((c) => c.seguito)
    .sort(perMembriPoiNome)
    .slice(0, limite);

/**
 * I club da scoprire: quelli reali che chi guarda NON segue ancora.
 *
 * L'esclusione dei seguiti e il punto della funzione. Riproporre nella scoperta
 * un club di cui si e gia membri sprecherebbe le tre caselle disponibili
 * proprio per chi ha gia usato la sezione.
 */
export const clubDaScoprire = (clubs: Club[], limite = LIMITE_CLUB_HOME): Club[] =>
  clubs
    .filter((c) => !c.seguito)
    .sort(perMembriPoiNome)
    .slice(0, limite);
