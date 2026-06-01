-- Part 6 migration: concurrency control, deadlock mitigation support, and WAL configuration.

SET search_path = public, pg_catalog;

ALTER TABLE public.customers
    ADD COLUMN IF NOT EXISTS version integer NOT NULL DEFAULT 1;

ALTER SYSTEM SET wal_level = 'replica';
ALTER SYSTEM SET archive_mode = 'on';

ALTER SYSTEM SET archive_command = 'cmd /c copy "%p" "C:\\pg_archive\\%f"';

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orderitems_order_inventory
    ON public.orderitems (order_id, product_id);