import Image from "next/image";

/** Il file scelto resta integro: la finestra circolare mostra soltanto il sigillo. */
export function VineaLogo() {
  return (
    <span className="relative block h-10 w-10 shrink-0 overflow-hidden rounded-full bg-bordeaux" aria-hidden="true">
      <Image
        src="/images/vinea-logo-scelto.png"
        alt=""
        width={1024}
        height={662}
        sizes="86px"
        loading="eager"
        className="absolute max-w-none"
        style={{ width: "213.333333%", height: "auto", left: "-57.5%", top: "-19.166667%" }}
        data-testid="vinea-brand-mark"
      />
    </span>
  );
}
