import Link from "next/link";

export default function NotFound() {
  return (
    <div className="grid place-items-center py-24 text-center">
      <p className="font-serif text-3xl">Profilo non disponibile</p>
      <p className="mt-2 max-w-md text-sm text-muted-foreground">
        Il profilo richiesto non è disponibile.
      </p>
      <Link href="/esplora" className="mt-4 text-bordeaux underline">
        Esplora gli annunci
      </Link>
    </div>
  );
}
