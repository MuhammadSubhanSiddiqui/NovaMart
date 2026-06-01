# Part 6 Concurrency Remediation

This pack addresses the Part 6 incidents with one database migration and one middleware patch.

## 1) Phantom Inventory

The fix is to stop doing a read-decide-write loop and let PostgreSQL enforce the stock constraint atomically.

```sql
UPDATE inventory
SET stock = stock - $1
WHERE store_id = $2
  AND product_id = $3
  AND stock >= $1
RETURNING stock;
```

If the statement affects zero rows, the application should treat the item as unavailable and abort the transaction.

## 2) NovaPay Lost Updates

Optimistic Concurrency Control is implemented by adding a `version` column to `customers` and updating only when the version still matches the value that was originally read.

```sql
UPDATE customers
SET available_credit = available_credit + $1,
    version = version + 1
WHERE customer_id = $2
  AND version = $3
RETURNING available_credit, version;
```

If the update returns no rows, another transaction won the race and the caller must re-read and retry.

## 3) Deadlock Storm

Because the vendor flow cannot be changed, the internal checkout path must follow the same lock order. The patched middleware inserts order items before it updates inventory so the application no longer acquires locks in the opposite order.

## 4) Recovery Window

`wal_level` must be raised from `minimal` to `replica` and archiving must be enabled so point-in-time recovery is available.

## Files

- [Database migration](../src/migrations/part6_concurrency.sql)
- [Middleware patch](../src/middleware/checkout_remediation.js)
- [Validation queries](../05_validation.sql)

## Outcome

This combination removes the inventory race, prevents silent credit drift, reduces deadlock pressure, and restores a recoverable WAL configuration.