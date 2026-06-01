# Part 12 Decision Log

## What the sample shows

- The Friday-evening peak is a connection-management problem as much as a raw throughput problem.
- The system needs a reproducible workload mix that can hit search, checkout, tracking, NovaPay, and fraud paths in controlled proportions.
- Benchmark results must stay in raw CSV form so the analysis step remains separate and auditable.

## Engineering decisions

1. Use Locust so the workload mix can be expressed with weighted user tasks.
2. Use a `ThreadedConnectionPool` so the harness can simulate connection pressure without relying on the broken middleware.
3. Emit Locust request metrics directly from the PostgreSQL client wrapper so the exported CSVs represent database timing, not generic script timing.
4. Keep statistical analysis in a separate script so the raw benchmark output is preserved for review and re-analysis.

## Trade-offs

- The harness bypasses the Node.js middleware, which means it measures database behavior directly rather than end-to-end application behavior.
- The CSV-first workflow is slightly less convenient than printing summary numbers during the run, but it is more defensible for a board or regulator review.

## Expected outcome

- Repeatable Friday-peak load generation.
- Raw benchmark CSV files for auditability.
- A separate analysis pass that can be re-run without re-executing the stress test.