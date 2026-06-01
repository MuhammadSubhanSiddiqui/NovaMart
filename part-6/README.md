# Part 6 Remediation Pack

This folder contains the database and middleware changes for the concurrency, deadlock, and recovery issues described in Part Six of the case study.

## Files

- `00_run_all.sql`: convenience wrapper for the database migration
- `docs/part6_concurrency_remediation.md`: GitHub-ready narrative with the SQL and Node.js snippets
- `src/migrations/part6_concurrency.sql`: PostgreSQL migration for OCC and WAL configuration
- `src/middleware/checkout_remediation.js`: reference middleware patch for inventory, OCC, and lock ordering
- `05_validation.sql`: post-change validation queries
- `decision-log.md`: engineering rationale and trade-offs

## Run Order

Run the migration first, then deploy the middleware patch, and finally execute the validation queries.

## Notes

- `wal_level = 'replica'` and `archive_mode = 'on'` require a PostgreSQL restart before they take effect.
- The archive command in the migration uses a local Windows-friendly placeholder and should be adjusted to match the actual archive directory on your machine.
- The OCC patch assumes the application will retry when the `CONCURRENCY_CONFLICT_RETRY` error is returned.