"use client";

import NextLink from "next/link";
import { forwardRef, useState, type ComponentPropsWithoutRef } from "react";

/** Prepara la destinazione al passaggio del mouse o al focus, non ogni link visibile. */
export const LinkSuIntento = forwardRef<
  HTMLAnchorElement,
  ComponentPropsWithoutRef<typeof NextLink>
>(function LinkSuIntento({ onMouseEnter, onFocus, prefetch, ...props }, ref) {
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
    />
  );
});
