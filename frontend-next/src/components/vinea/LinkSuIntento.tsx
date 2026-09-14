"use client";

import NextLink, { useLinkStatus } from "next/link";
import { forwardRef, useState, type ComponentPropsWithoutRef } from "react";

/** Prepara la destinazione al passaggio del mouse o al focus, non ogni link visibile. */
export const LinkSuIntento = forwardRef<
  HTMLAnchorElement,
  ComponentPropsWithoutRef<typeof NextLink>
>(function LinkSuIntento({ onMouseEnter, onFocus, onTouchStart, prefetch, children, ...props }, ref) {
  const [intento, setIntento] = useState(false);
  return (
    <NextLink
      {...props}
      ref={ref}
      prefetch={prefetch === undefined ? (intento ? null : false) : prefetch}
      onMouseEnter={(event) => {
        onMouseEnter?.(event);
        if (!event.defaultPrevented) setIntento(true);
      }}
      onFocus={(event) => {
        onFocus?.(event);
        if (!event.defaultPrevented) setIntento(true);
      }}
      onTouchStart={(event) => {
        onTouchStart?.(event);
        if (!event.defaultPrevented) setIntento(true);
      }}
    >
      {children}
      <AvanzamentoNavigazione />
    </NextLink>
  );
});

function AvanzamentoNavigazione() {
  const { pending } = useLinkStatus();
  return pending ? (
    <span role="status" className="fixed inset-x-0 top-0 z-50 h-1 bg-oro motion-safe:animate-pulse pointer-events-none">
      <span className="sr-only">Apertura pagina…</span>
    </span>
  ) : null;
}
