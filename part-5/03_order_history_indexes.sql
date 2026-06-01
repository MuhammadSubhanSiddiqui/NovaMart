-- Part 5.3: Order history remediation for PostgreSQL 16
-- Goal: turn correlated subquery lookups into index probes instead of repeated full-table scans.

SET search_path = public, pg_catalog;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_customer_id
    ON public.orders (customer_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orderitems_order_id
    ON public.orderitems (order_id);

ANALYZE public.orders;
ANALYZE public.orderitems;