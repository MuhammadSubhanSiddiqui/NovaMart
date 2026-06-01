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
