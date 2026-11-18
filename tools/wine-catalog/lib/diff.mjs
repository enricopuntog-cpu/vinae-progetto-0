// Classificazione di un import rispetto a uno snapshot precedente (lwin -> row_hash).
// Pura e deterministica. NON produce mai un'azione di cancellazione: un record
// sparito dalla fonte è solo elencato (`removed_from_source`); decidere cosa
// farne in Vinea spetta a una revisione, non all'importatore.

export function classifyImport(records, previous) {
  const counts = {
    new: 0, updated: 0, unchanged: 0, duplicate: 0, conflict: 0, merged: 0,
    // Combined confrontati con lo snapshot precedente (WI-001B, chiude il limite G1 di WI-001A):
    // il riferimento di destinazione è nel row_hash, quindi una sua modifica è un «aggiornato».
    merged_new: 0, merged_updated: 0, merged_unchanged: 0,
    removed_from_source: 0,
  };
  const seen = new Map(); // lwin -> primo record
  const conflicting = new Set();
  for (const r of records) {
    const first = seen.get(r.lwin);
    if (!first) {
      seen.set(r.lwin, r);
    } else if (first.row_hash === r.row_hash) {
      counts.duplicate += 1;
    } else {
      conflicting.add(r.lwin);
    }
  }
  counts.conflict = conflicting.size;

  const mergedPairs = [];
  for (const [lwin, r] of seen) {
    if (conflicting.has(lwin)) continue;
    if (r.status === 'Combined') {
      counts.merged += 1;
      mergedPairs.push({ from: lwin, into: r.reference_lwin });
      if (!previous || !previous.has(lwin)) counts.merged_new += 1;
      else if (previous.get(lwin) === r.row_hash) counts.merged_unchanged += 1;
      else counts.merged_updated += 1;
      continue;
    }
    if (!previous || !previous.has(lwin)) counts.new += 1;
    else if (previous.get(lwin) === r.row_hash) counts.unchanged += 1;
    else counts.updated += 1;
  }

  const removedLwins = [];
  if (previous) {
    for (const lwin of previous.keys()) if (!seen.has(lwin)) removedLwins.push(lwin);
  }
  removedLwins.sort();
  counts.removed_from_source = removedLwins.length;

  return {
    counts,
    conflictLwins: [...conflicting].sort(),
    mergedPairs,
    removedLwins,
    deleteAction: 'none',
  };
}
