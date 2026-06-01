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
