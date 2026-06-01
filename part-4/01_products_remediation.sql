-- Products remediation for PostgreSQL 16
-- Goal: remove obviously invalid physical data, preserve semi-structured descriptions, and fix search planning.

SET search_path = public, pg_catalog;

VACUUM (ANALYZE) public.products;

UPDATE public.products
SET weight_kg = NULL
WHERE product_type IN ('financial', 'digital', 'logistics')
  AND weight_kg IS NOT NULL;

ALTER TABLE public.products
ADD COLUMN IF NOT EXISTS description_jsonb jsonb;

DO $$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT ctid, description
        FROM public.products
        WHERE description IS NOT NULL
          AND description_jsonb IS NULL
    LOOP
        BEGIN
            IF btrim(r.description) ~ '^[\{\[]' THEN
                UPDATE public.products
                SET description_jsonb = r.description::jsonb
                WHERE ctid = r.ctid;
            ELSE
                UPDATE public.products
                SET description_jsonb = jsonb_build_object('raw_text', r.description)
                WHERE ctid = r.ctid;
            END IF;
        EXCEPTION WHEN others THEN
            UPDATE public.products
            SET description_jsonb = jsonb_build_object(
                'raw_text', r.description,
                'parse_error', SQLERRM
            )
            WHERE ctid = r.ctid;
        END;
    END LOOP;
END $$;

DROP INDEX IF EXISTS public.idx_products_description_jsonb_gin;
CREATE INDEX idx_products_description_jsonb_gin
    ON public.products
    USING GIN (description_jsonb jsonb_path_ops);

CREATE INDEX IF NOT EXISTS idx_products_product_type
    ON public.products (product_type);

ANALYZE public.products;
