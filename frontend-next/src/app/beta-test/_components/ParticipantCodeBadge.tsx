// Codice reale restituito dal server dopo «INIZIA IL TEST»: resta visibile in
// alto su ogni schermata del percorso, mai come campo modificabile.
export function ParticipantCodeBadge({ code }: { code: string }) {
  return (
    <div className="mb-4 flex justify-end">
      <span
        className="rounded-full border border-bordeaux/20 bg-bordeaux/5 px-3 py-1 font-mono text-sm font-semibold text-bordeaux"
        data-participant-code={code}
      >
        Test {code}
      </span>
    </div>
  );
}
