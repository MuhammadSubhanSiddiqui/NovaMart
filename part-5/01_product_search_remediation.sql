-- Part 5.1: Product search load remediation for PostgreSQL 16
-- Goal: lower planner cost, avoid disk-spilling hash joins, and stop recomputing ratings on every search.

SET search_path = public, pg_catalog;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'novamart_app') THEN
        EXECUTE format(
            'ALTER ROLE %I IN DATABASE %I SET work_mem = %L',
            'novamart_app',
            current_database(),
            '256MB'
        );
    END IF;
END $$;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_products_description_jsonb_gin
    ON public.products
    USING GIN (description_jsonb jsonb_path_ops);

DROP INDEX IF EXISTS public.idx_products_description;

DROP MATERIALIZED VIEW IF EXISTS public.mv_product_ratings;

CREATE MATERIALIZED VIEW public.mv_product_ratings AS
SELECT
    product_id,
    AVG(rating) AS avg_rating,
    COUNT(rating) AS review_count
FROM public.reviews
GROUP BY product_id
WITH DATA;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_product_ratings_product_id
    ON public.mv_product_ratings (product_id);

ANALYZE public.products;
ANALYZE public.reviews;
ANALYZE public.mv_product_ratings;