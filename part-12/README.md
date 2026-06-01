# Part 12 Remediation Pack

This folder contains the standalone load-test harness for the Friday-evening peak scenario described in Part 12 of the case study.

## Files

- `src/tests/integration/locustfile.py`: Locust workload generator that drives PostgreSQL directly
- `src/tests/integration/run_benchmark.sh`: one-command benchmark runner that exports raw CSV output
- `src/tests/integration/analyze_results.py`: separate statistical analysis step for the exported CSV files

## Run Order

1. Install the Python dependencies required by Locust and psycopg2.
2. Run the benchmark script to produce raw CSV files.
3. Run the analysis script against the generated CSV output.

## Notes

- The harness bypasses the Node.js middleware so the database engine can be tested directly.
- The benchmark is intentionally CSV-first: the raw metrics are produced by Locust, and the analysis step is a separate script.