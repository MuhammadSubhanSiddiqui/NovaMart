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