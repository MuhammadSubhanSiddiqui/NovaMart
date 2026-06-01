# Part 4 Remediation Pack

This folder contains standalone PostgreSQL 16 scripts for the data-shape problems described in Part Four of the case study.

## Files

- `00_run_all.sql`: convenience wrapper for `psql`
- `01_products_remediation.sql`: product-table cleanup and search-index repair
- `02_customers_remediation.sql`: PAN containment, profile JSON cleanup, and dead-letter handling
- `03_employees_remediation.sql`: hierarchy index repair
- `04_novapay_plans_remediation.sql`: orphan-plan reparenting and foreign-key restoration
- `05_validation.sql`: post-remediation checks
- `decision-log.md`: engineering rationale and trade-offs

## Run Order

Run the scripts in numeric order. If you want a single entry point, use `psql -f 00_run_all.sql` from this directory.

## Notes

- The scripts assume the default `public` schema and the lowercase table names used by PostgreSQL.
- The customer PAN script uses a local development key if no `novamart.pci_key` setting is already present.
- The NovaPay script repairs the customer foreign key pattern shown in the case and provides the same mechanism for the remaining missing references.