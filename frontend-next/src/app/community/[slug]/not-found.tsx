import Link from "next/link";
import { Button } from "@/components/ui/button";

export default function NotFound() {
  return (
    <div className="rounded-2xl border border-border bg-card p-10 text-center">
      <p className="font-serif text-2xl">Club non trovato</p>
      <Button asChild className="mt-4 bg-bordeaux hover:bg-bordeaux/90">
        <Link href="/">Torna alla home</Link>
      </Button>
    </div>
  );
}
