import Link from "next/link";

export default function NotFound() {
  return (
    <div className="grid place-items-center py-24 text-center">
      <p className="font-serif text-3xl">Annuncio non trovato</p>
      <Link href="/esplora" className="mt-4 text-bordeaux underline">
        Torna alla ricerca
      </Link>
    </div>
  );
}
