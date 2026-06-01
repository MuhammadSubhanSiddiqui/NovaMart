# Part 4 Decision Log

## What the sample shows

- `products` is a mixed entity table with physical, digital, financial, and logistics rows in one heap.
- `customers.profile_data` is valid JSON in most rows but malformed in a significant minority.
- `customers.card_last_sixteen` is actually a stored PAN and is a PCI risk.
- `employees.manager_id` is a self-referential hierarchy column without an index.
- `novapay_plans` contains orphaned rows and was left with foreign-key enforcement partially disabled.

## Engineering decisions

1. Keep the remediation scripts executable on a local PostgreSQL 16 sample without app-layer changes.
2. Prefer data-safe cleanup over destructive deletion when the case describes retention or legal obligations.
3. Use JSONB for semi-structured customer profile data because the valid rows are still useful once parsed.
4. Move sensitive PAN data out of the base customer row and into a dedicated encrypted vault table.
5. Add the minimum index needed to remove the recursive hierarchy bottleneck.
6. Re-parent orphaned NovaPay plans to a legal holding record, then restore constraint enforcement with `NOT VALID` and validation.

## Trade-offs

- The product script improves the immediate query path and preserves the legacy column for compatibility. A full vertical split is the academically strongest answer, but it requires application rewrites that are outside a local SQL-only remediation pack.
- The customer script keeps malformed payloads instead of guessing at repairs. The dead-letter table preserves the evidence needed for manual review.
- The NovaPay remediation restores integrity without deleting collectible debt.

## Expected outcome

- Better planner estimates and lower search latency on `products`.
- Removal of plaintext PAN exposure from `customers`.
- Faster reporting-chain lookups for `employees`.
- Reinstated foreign-key enforcement for `novapay_plans` after orphan repair.