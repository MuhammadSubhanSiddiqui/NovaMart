-- Employees remediation for PostgreSQL 16
-- Goal: speed up recursive reporting-chain lookups without changing application code.

SET search_path = public, pg_catalog;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_employees_manager_id
    ON public.employees (manager_id);

ANALYZE public.employees;
