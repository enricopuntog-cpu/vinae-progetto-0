// WI-016 — la sola chiamata che consegna un segnale, usata dal mittente, dal raccoglitore e dall'osservatore.
export async function inviaSegnale(sql, s) {
  const [riga] = await sql`select brain.ingest_signal(${s.fonte}::text, ${s.evento}::text, ${s.stato}::text,
    ${s.osservato}::timestamptz, ${s.riferimento}::text, ${JSON.stringify(s.conteggi ?? {})}::text::jsonb) as esito`;
  return riga.esito;
}
