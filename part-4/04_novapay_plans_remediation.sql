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
