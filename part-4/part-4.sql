-- Combined SQL bundle for part-4

-- ============================================================
-- FILE: 00_run_all.sql
-- ============================================================
\set ON_ERROR_STOP on

\i 01_products_remediation.sql
\i 02_customers_remediation.sql
\i 03_employees_remediation.sql
\i 04_novapay_plans_remediation.sql


-- ============================================================
-- FILE: 01_products_remediation.sql
-- ============================================================
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


-- ============================================================
-- FILE: 02_customers_remediation.sql
-- ============================================================
-- Customers remediation for PostgreSQL 16
-- Goal: remove plaintext PAN exposure, preserve legally required records, and clean JSON profile payloads.

SET search_path = public, pg_catalog;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
BEGIN
    PERFORM set_config(
        'novamart.pci_key',
        COALESCE(current_setting('novamart.pci_key', true), 'nova_local_dev_key'),
        true
    );
END $$;

CREATE TABLE IF NOT EXISTS public.customer_pan_vault (
    customer_id bigint PRIMARY KEY,
    pan_ciphertext bytea NOT NULL,
    retention_state text NOT NULL CHECK (retention_state IN ('active', 'expired')),
    captured_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.profile_data_deadletter (
    customer_id bigint PRIMARY KEY,
    malformed_payload text NOT NULL,
    failure_reason text NOT NULL,
    captured_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.customers
ADD COLUMN IF NOT EXISTS profile_data_jsonb jsonb;

INSERT INTO public.customer_pan_vault (customer_id, pan_ciphertext, retention_state)
SELECT c.customer_id,
       pgp_sym_encrypt(c.card_last_sixteen, current_setting('novamart.pci_key')),
       CASE
           WHEN EXISTS (
               SELECT 1
               FROM public.orders o
               WHERE o.customer_id = c.customer_id
                 AND o.order_date >= now() - INTERVAL '18 months'
           ) THEN 'active'
           ELSE 'expired'
       END
FROM public.customers c
WHERE c.card_last_sixteen IS NOT NULL
ON CONFLICT (customer_id) DO UPDATE
SET pan_ciphertext = EXCLUDED.pan_ciphertext,
    retention_state = EXCLUDED.retention_state,
    captured_at = now();

UPDATE public.customers
SET card_last_sixteen = NULL
WHERE card_last_sixteen IS NOT NULL;

DO $$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT ctid, customer_id, profile_data
        FROM public.customers
        WHERE profile_data IS NOT NULL
          AND profile_data_jsonb IS NULL
    LOOP
        BEGIN
            UPDATE public.customers
            SET profile_data_jsonb = r.profile_data::jsonb
            WHERE ctid = r.ctid;
        EXCEPTION WHEN others THEN
            INSERT INTO public.profile_data_deadletter (customer_id, malformed_payload, failure_reason)
            VALUES (r.customer_id, r.profile_data, SQLERRM)
            ON CONFLICT (customer_id) DO UPDATE
            SET malformed_payload = EXCLUDED.malformed_payload,
                failure_reason = EXCLUDED.failure_reason,
                captured_at = now();

            UPDATE public.customers
            SET profile_data = NULL
            WHERE ctid = r.ctid;
        END;
    END LOOP;
END $$;

CREATE INDEX IF NOT EXISTS idx_customers_profile_data_jsonb_gin
    ON public.customers
    USING GIN (profile_data_jsonb jsonb_path_ops);

ANALYZE public.customers;


-- ============================================================
-- FILE: 03_employees_remediation.sql
-- ============================================================
-- Employees remediation for PostgreSQL 16
-- Goal: speed up recursive reporting-chain lookups without changing application code.

SET search_path = public, pg_catalog;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_employees_manager_id
    ON public.employees (manager_id);

ANALYZE public.employees;


-- ============================================================
-- FILE: 04_novapay_plans_remediation.sql
-- ============================================================
-- NovaPay plans remediation for PostgreSQL 16
-- Goal: re-parent orphans to a legal holding account and restore foreign-key enforcement.

SET search_path = public, pg_catalog;

DO $$
BEGIN
    BEGIN
        INSERT INTO public.customers (customer_id, name, contact_email)
        VALUES (-1, 'NovaMart Legal Holding (Orphans)', 'legal@novamart.pk')
        ON CONFLICT (customer_id) DO NOTHING;
    EXCEPTION
        WHEN undefined_column OR not_null_violation OR foreign_key_violation THEN
            NULL;
    END;
END $$;

DO $$
DECLARE
    insert_sql text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.customers WHERE customer_id = -1) THEN
        SELECT 'INSERT INTO public.customers (' || string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position) || ') VALUES (' ||
               string_agg(
                   CASE
                       WHEN column_name = 'customer_id' THEN '-1'
                       WHEN column_name ~* '(name|full_name|customer_name)' THEN quote_literal('NovaMart Legal Holding (Orphans)')
                       WHEN column_name ~* '(email|e_mail)' THEN quote_literal('legal@novamart.pk')
                       WHEN data_type IN ('character varying', 'character', 'text') THEN quote_literal('holding')
                       WHEN data_type IN ('smallint', 'integer', 'bigint', 'numeric', 'decimal', 'real', 'double precision') THEN '0'
                       WHEN data_type = 'boolean' THEN 'false'
                       WHEN data_type = 'date' THEN 'CURRENT_DATE'
                       WHEN data_type LIKE 'timestamp%' THEN 'CURRENT_TIMESTAMP'
                       WHEN data_type IN ('json', 'jsonb') THEN '''{}''::jsonb'
                       ELSE 'NULL'
                   END,
                   ', ' ORDER BY ordinal_position
               ) || ') ON CONFLICT (customer_id) DO NOTHING'
        INTO insert_sql
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'customers';

        IF insert_sql IS NOT NULL THEN
            EXECUTE insert_sql;
        END IF;
    END IF;
END $$;

UPDATE public.novapay_plans np
SET customer_id = -1
WHERE customer_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM public.customers c
      WHERE c.customer_id = np.customer_id
  );

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_novapay_plans_customer'
    ) THEN
        ALTER TABLE public.novapay_plans
            ADD CONSTRAINT fk_novapay_plans_customer
            FOREIGN KEY (customer_id)
            REFERENCES public.customers (customer_id)
            NOT VALID;
    END IF;
END $$;

ALTER TABLE public.novapay_plans
    VALIDATE CONSTRAINT fk_novapay_plans_customer;

ANALYZE public.novapay_plans;


-- ============================================================
-- FILE: 05_validation.sql
-- ============================================================
-- Validation queries for the Part 4 remediation pack.

SET search_path = public, pg_catalog;

SELECT
    COUNT(*) AS invalid_product_weights
FROM public.products
WHERE product_type IN ('financial', 'digital', 'logistics')
  AND weight_kg IS NOT NULL;

SELECT
    COUNT(*) AS populated_product_descriptions
FROM public.products
WHERE description_jsonb IS NOT NULL;

SELECT
    COUNT(*) AS pan_rows_remaining_in_customers
FROM public.customers
WHERE card_last_sixteen IS NOT NULL;

SELECT
    COUNT(*) AS pan_rows_in_vault
FROM public.customer_pan_vault;

SELECT
    COUNT(*) AS malformed_profiles_deadlettered
FROM public.profile_data_deadletter;

SELECT
    COUNT(*) AS customers_with_jsonb_profiles
FROM public.customers
WHERE profile_data_jsonb IS NOT NULL;

SELECT
    indexname
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'employees'
  AND indexname = 'idx_employees_manager_id';

SELECT
    conname,
    convalidated
FROM pg_constraint
WHERE conname = 'fk_novapay_plans_customer';


