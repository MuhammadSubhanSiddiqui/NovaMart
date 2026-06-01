-- Validation queries for the Part 5 remediation pack.

SET search_path = public, pg_catalog;

SELECT
    current_setting('work_mem', true) AS session_work_mem;

SELECT
    indexname
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'products'
  AND indexname = 'idx_products_description_jsonb_gin';

SELECT
    to_regclass('public.mv_product_ratings') AS mv_product_ratings_exists;

SELECT
    indexname
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'mv_product_ratings'
  AND indexname = 'idx_mv_product_ratings_product_id';

SELECT
    relkind,
    relname
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname = 'inventory';

SELECT
    COUNT(*) AS inventory_partitions
FROM pg_inherits i
JOIN pg_class c ON c.oid = i.inhrelid
JOIN pg_class p ON p.oid = i.inhparent
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE p.relname = 'inventory'
  AND n.nspname = 'public';

SELECT
    indexname
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'orders'
  AND indexname = 'idx_orders_customer_id';

SELECT
    indexname
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'orderitems'
  AND indexname = 'idx_orderitems_order_id';

SELECT
    EXISTS (
        SELECT 1
        FROM pg_extension
        WHERE extname = 'pg_stat_statements'
    ) AS pg_stat_statements_enabled;