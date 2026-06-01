-- Part 5.4: Slow query observability for PostgreSQL 16
-- Goal: normalize query fingerprints so the hottest shapes can be measured and reported consistently.

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

SELECT
    queryid,
    LEFT(query, 100) AS normalized_query_stub,
    calls,
    total_exec_time / 1000 / 60 AS total_minutes_spent,
    mean_exec_time AS avg_ms_per_call
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 20;