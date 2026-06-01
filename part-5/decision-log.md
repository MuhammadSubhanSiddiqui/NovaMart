# Part 5 Decision Log

## What the sample shows

- The product search path is paying for stale planning assumptions, a tiny `work_mem`, a mismatched GIN operator class, and repeated aggregation of review ratings.
- The inventory availability path is forced through 134 store views instead of a partitioned table that PostgreSQL can prune.
- The order-history path is doing repeated lookups through correlated subqueries without supporting indexes on the foreign-key columns.
- The slow-query evidence is spread across many fingerprints, so a normalized fingerprint source is needed for reporting and prioritization.

## Engineering decisions

1. Use a role-scoped `work_mem` increase so the hot application user can avoid hash spills without inflating memory usage for every backend.
2. Build the product description GIN index on `description_jsonb` with `jsonb_path_ops` because the search pattern is containment-oriented.
3. Materialize average ratings per product because the 180-million-row review scan is pure repeated work during search.
4. Migrate inventory to native list partitioning by `store_id` so the planner can prune 133 partitions instead of scanning the whole table.
5. Index `orders.customer_id` and `orderitems.order_id` because they are the access paths that turn the correlated subqueries into index probes.
6. Enable `pg_stat_statements` so the team can quantify the real query fingerprints instead of arguing over raw log strings.

## Trade-offs

- The materialized ratings view introduces controlled staleness, but that is preferable to recomputing the same aggregate on every search request.
- Partitioning inventory is the strongest structural fix, but it is a heavier migration than a single index; the payoff is that the checkout path finally becomes pruneable.
- `pg_stat_statements` is diagnostic rather than corrective, and it needs a preload change if the server has not already been configured for it.

## Expected outcome

- Lower product-search latency and fewer retry cascades.
- Instant pruning for store-scoped inventory lookups.
- Fast order-history lookups for support workflows.
- A normalized query-fingerprint source for the board-level performance report.