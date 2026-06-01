# Part 5 Remediation Pack

This folder contains standalone PostgreSQL 16 scripts for the load and observability problems described in Part Five of the case study.

## Files

- `00_run_all.sql`: convenience wrapper for `psql`
- `01_product_search_remediation.sql`: planner relief, role-level `work_mem`, and ratings pre-aggregation
- `02_inventory_partitioning.sql`: migration from store views to native list partitioning
- `03_order_history_indexes.sql`: foreign-key indexes for the correlated subquery path
- `04_observability.sql`: `pg_stat_statements` setup and reporting query
- `05_validation.sql`: post-remediation checks
- `decision-log.md`: engineering rationale and trade-offs

## Run Order

Run the scripts in numeric order. If you want a single entry point, use `psql -f 00_run_all.sql` from this directory.

## Notes

- The product search script assumes the Part 4 `products.description_jsonb` remediation has already been applied.
- `pg_stat_statements` requires the extension to be loadable by the server. If it is not already preloaded, enable `shared_preload_libraries = 'pg_stat_statements'` and restart PostgreSQL once before running the observability script.
- The inventory script preserves the existing data by renaming the legacy heap table, creating a partitioned replacement, and then copying the data across.