import Link from "next/link";

const NotFound = () => (
  <div className="grid place-items-center py-24 text-center">
    <h1 className="font-serif text-3xl">Annuncio non trovato</h1>
    <Link href="/esplora" className="mt-4 text-bordeaux underline">Torna alla ricerca</Link>
  </div>
);

export default NotFound;
