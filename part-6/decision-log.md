# Part 6 Decision Log

## What the sample shows

- Inventory failures come from a read-decide-write race, not from a missing report or a bad index.
- NovaPay balance drift comes from concurrent lost updates on `available_credit`.
- Deadlocks come from opposite lock ordering between internal and third-party flows.
- Recovery time is dominated by the fact that `wal_level` was set to `minimal`, which prevents point-in-time recovery.

## Engineering decisions

1. Use an atomic `UPDATE ... WHERE stock >= qty` pattern so PostgreSQL enforces the inventory constraint under row-level locking.
2. Add a `version` column to `customers` and require the application to perform compare-and-swap updates for `available_credit`.
3. Rewrite the internal checkout flow to follow the same lock order as the vendor cancellation flow so the lock hierarchy is globally consistent.
4. Raise `wal_level` to `replica` and enable archiving so the instance can support point-in-time recovery.
5. Add an index on the order-items path because it reduces the time locks are held and supports the patched transaction flow.

## Trade-offs

- OCC requires a retry path in the application, but it prevents silent balance drift.
- Changing WAL settings improves disaster recovery, but it also increases write-ahead-log volume and operational overhead.
- The deadlock fix is an application patch because the vendor module is not under our control.

## Expected outcome

- No negative inventory from concurrent checkout sessions.
- No silent lost updates on customer credit values.
- Fewer deadlocks in the order flow.
- A recoverable WAL configuration that supports the stated RTO.