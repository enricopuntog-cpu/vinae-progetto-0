"use client";

import { Component, type ReactNode } from "react";

type Props = { children: ReactNode; fallback: ReactNode };

/**
 * Una sezione accessoria caricata su richiesta può non arrivare, per esempio su rete instabile.
 * Senza un confine l'errore risale fino a `app/error.tsx` e porta via tutta la pagina.
 */
export class ConfineOpzionale extends Component<Props, { guasto: boolean }> {
  state = { guasto: false };

  static getDerivedStateFromError() {
    return { guasto: true };
  }

  render() {
    return this.state.guasto ? this.props.fallback : this.props.children;
  }
}
