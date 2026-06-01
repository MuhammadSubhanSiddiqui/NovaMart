-- Combined SQL bundle for part-6
-- Generated: 2026-06-01 13:39:54

-- ============================================================
-- FILE: 00_run_all.sql
-- ============================================================
\set ON_ERROR_STOP on

\i src/migrations/part6_concurrency.sql

-- ============================================================
-- FILE: 05_validation.sql
-- ============================================================
-- Validation queries for the Part 6 remediation pack.

SET search_path = public, pg_catalog;

SELECT
    column_name,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'customers'
  AND column_name = 'version';

SELECT
    name,
    setting
FROM pg_settings
WHERE name IN ('wal_level', 'archive_mode', 'archive_command');

SELECT
    indexname
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'orderitems'
  AND indexname = 'idx_orderitems_order_inventory';

-- ============================================================
-- FILE: modular_remediation.sql
-- ============================================================
\echo 'Part 6 modular remediation started'
\set ON_ERROR_STOP on

-- Module 1: Database migration for concurrency and recovery
\i src/migrations/part6_concurrency.sql

-- Module 2: Validation checks
\i 05_validation.sql

\echo 'Part 6 modular remediation completed'


-- ============================================================
-- FILE: src/migrations/part6_concurrency.sql
-- ============================================================
-- Part 6 migration: concurrency control, deadlock mitigation support, and WAL configuration.

SET search_path = public, pg_catalog;

ALTER TABLE public.customers
    ADD COLUMN IF NOT EXISTS version integer NOT NULL DEFAULT 1;

ALTER SYSTEM SET wal_level = 'replica';
ALTER SYSTEM SET archive_mode = 'on';

ALTER SYSTEM SET archive_command = 'cmd /c copy "%p" "C:\\pg_archive\\%f"';

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orderitems_order_inventory
    ON public.orderitems (order_id, product_id);

