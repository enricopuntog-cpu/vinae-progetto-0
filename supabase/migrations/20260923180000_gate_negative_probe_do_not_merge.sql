-- PROBE NEGATIVO DEL GATE 12g: NON INTEGRARE.
-- Reintroduce di proposito il difetto 3 dell'audit #141 (prove depositate
-- cancellabili dalle parti) per dimostrare che il gate CI diventa rosso.
drop policy if exists dispute_evidence_owner_delete on storage.objects;
create policy dispute_evidence_owner_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'dispute-evidence'
  and split_part(name, '/', 2) = (select auth.uid())::text
);
