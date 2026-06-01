-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║                                                                            ║
-- ║   NOVAMART — PART 7: DISTRIBUTED ARCHITECTURE INTEGRATION                  ║
-- ║                                                                            ║
-- ║   Database Engine  : PostgreSQL 16+                                        ║
-- ║   Target Nodes     : Node 1 (Primary), Node 2 (A-M), Node 3 (N-Z/Inv)     ║
-- ║   Execution Order  : Run sections sequentially (7.1 through 7.8)           ║
-- ║                                                                            ║
-- ║   NOTE: Shell scripts and configuration snippets are embedded in           ║
-- ║         block comments. Extract and run them on the appropriate servers.   ║
-- ║                                                                            ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝


-- ┌──────────────────────────────────────────────────────────────────────────────┐
-- │  7.1  REPLICATION SETUP (01_replication_setup.sql)                          │
-- │  Run on: EVERY PostgreSQL node (requires restart after ALTER SYSTEM)        │
-- └──────────────────────────────────────────────────────────────────────────────┘

-- Enable logical replication, streaming, and point-in-time recovery
ALTER SYSTEM SET wal_level             = 'logical';
ALTER SYSTEM SET archive_mode          = 'on';
ALTER SYSTEM SET archive_command       = 'cp %p /var/lib/postgresql/wal_archive/%f';
ALTER SYSTEM SET max_wal_senders       = 10;
ALTER SYSTEM SET max_replication_slots  = 10;
ALTER SYSTEM SET hot_standby           = 'on';

-- Create a dedicated replication user
CREATE ROLE replication_user WITH REPLICATION LOGIN PASSWORD 'strong_random_password';

-- On Node 1 primary: async replication to Lahore standby
ALTER SYSTEM SET synchronous_standby_names = '';


-- ┌──────────────────────────────────────────────────────────────────────────────┐
-- │  7.2  pg_hba.conf CONFIGURATION (02_pg_hba.conf)                           │
-- │  Action: Append to pg_hba.conf on each primary node, then reload.          │
-- └──────────────────────────────────────────────────────────────────────────────┘

/*
 *  ── pg_hba.conf snippet (add to each primary) ──
 *
 *  hostssl  replication  replication_user  0.0.0.0/0  scram-sha-256
 *
 *  After editing, reload the configuration:
 *    SELECT pg_reload_conf();
 */


-- ┌──────────────────────────────────────────────────────────────────────────────┐
-- │  7.3  STANDBY BOOTSTRAP (03_setup_standby.sh)                              │
-- │  Action: Run on each STANDBY server via bash.                              │
-- └──────────────────────────────────────────────────────────────────────────────┘

/*
 *  ── Shell Script: setup_standby.sh ──
 *
 *  #!/bin/bash
 *  # Run this on the standby server to seed from the primary.
 *  # The -R flag auto-creates standby.signal and sets primary_conninfo.
 *
 *  pg_basebackup \
 *      -h node1-primary \
 *      -U replication_user \
 *      -D /var/lib/postgresql/16/main \
 *      -Fp -R
 */


-- ┌──────────────────────────────────────────────────────────────────────────────┐
-- │  7.4  CONSOLIDATE CUSTOMERS (04_consolidate_customers.sql)                 │
-- │  Run on: NODE 1 — Creates a hash-partitioned customers table               │
-- └──────────────────────────────────────────────────────────────────────────────┘

CREATE TABLE customers (
    customer_id   BIGINT         NOT NULL,
    first_name    VARCHAR(100),
    last_name     VARCHAR(100),
    email         VARCHAR(255),
    phone         VARCHAR(20),
    city          VARCHAR(100),
    profile_data  JSONB,                        -- Migrated from VARCHAR to JSONB
    created_at    TIMESTAMPTZ    DEFAULT NOW(),
    updated_at    TIMESTAMPTZ    DEFAULT NOW()
) PARTITION BY HASH (customer_id);

-- 8 hash partitions — good balance for ~14M rows
CREATE TABLE customers_p0 PARTITION OF customers FOR VALUES WITH (MODULUS 8, REMAINDER 0);
CREATE TABLE customers_p1 PARTITION OF customers FOR VALUES WITH (MODULUS 8, REMAINDER 1);
CREATE TABLE customers_p2 PARTITION OF customers FOR VALUES WITH (MODULUS 8, REMAINDER 2);
CREATE TABLE customers_p3 PARTITION OF customers FOR VALUES WITH (MODULUS 8, REMAINDER 3);
CREATE TABLE customers_p4 PARTITION OF customers FOR VALUES WITH (MODULUS 8, REMAINDER 4);
CREATE TABLE customers_p5 PARTITION OF customers FOR VALUES WITH (MODULUS 8, REMAINDER 5);
CREATE TABLE customers_p6 PARTITION OF customers FOR VALUES WITH (MODULUS 8, REMAINDER 6);
CREATE TABLE customers_p7 PARTITION OF customers FOR VALUES WITH (MODULUS 8, REMAINDER 7);

-- Indexes aligned to actual query patterns
CREATE INDEX idx_customers_id    ON customers (customer_id);
CREATE INDEX idx_customers_city  ON customers (city);
CREATE INDEX idx_customers_email ON customers (email);


-- ┌──────────────────────────────────────────────────────────────────────────────┐
-- │  7.5  CONSOLIDATE ORDERS (05_consolidate_orders.sql)                       │
-- │  Run on: NODE 1 — Time-based range partitioning for orders                 │
-- └──────────────────────────────────────────────────────────────────────────────┘

CREATE TABLE orders (
    order_id      BIGINT         NOT NULL,
    customer_id   BIGINT         NOT NULL,
    channel       VARCHAR(10)    NOT NULL CHECK (channel IN ('online', 'retail')),
    order_date    TIMESTAMPTZ    NOT NULL,
    status        VARCHAR(20),
    total_amount  NUMERIC(12,2),
    store_id      INT,
    created_at    TIMESTAMPTZ    DEFAULT NOW()
) PARTITION BY RANGE (order_date);

-- Monthly partitions: July 2025 → June 2026
CREATE TABLE orders_2025_07 PARTITION OF orders FOR VALUES FROM ('2025-07-01') TO ('2025-08-01');
CREATE TABLE orders_2025_08 PARTITION OF orders FOR VALUES FROM ('2025-08-01') TO ('2025-09-01');
CREATE TABLE orders_2025_09 PARTITION OF orders FOR VALUES FROM ('2025-09-01') TO ('2025-10-01');
CREATE TABLE orders_2025_10 PARTITION OF orders FOR VALUES FROM ('2025-10-01') TO ('2025-11-01');
CREATE TABLE orders_2025_11 PARTITION OF orders FOR VALUES FROM ('2025-11-01') TO ('2025-12-01');
CREATE TABLE orders_2025_12 PARTITION OF orders FOR VALUES FROM ('2025-12-01') TO ('2026-01-01');
CREATE TABLE orders_2026_01 PARTITION OF orders FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE orders_2026_02 PARTITION OF orders FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
CREATE TABLE orders_2026_03 PARTITION OF orders FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');
CREATE TABLE orders_2026_04 PARTITION OF orders FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
CREATE TABLE orders_2026_05 PARTITION OF orders FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE orders_2026_06 PARTITION OF orders FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');

-- Archive partition for all historical data
CREATE TABLE orders_archive PARTITION OF orders FOR VALUES FROM (MINVALUE) TO ('2025-07-01');

-- Indexes
CREATE INDEX idx_orders_customer ON orders (customer_id);
CREATE INDEX idx_orders_date     ON orders (order_date);
CREATE INDEX idx_orders_channel  ON orders (channel);


-- ┌──────────────────────────────────────────────────────────────────────────────┐
-- │  7.6  DATA MIGRATION SCRIPT (06_migration_script.sh)                       │
-- │  Action: Run from a jump host that can reach all three nodes.              │
-- └──────────────────────────────────────────────────────────────────────────────┘

/*
 *  ── Shell Script: migration_script.sh ──
 *
 *  #!/bin/bash
 *  set -euo pipefail
 *
 *  echo "[1/2] Migrating A-M customers from Node 2..."
 *  pg_dump -h node2 -U replication_user -t customers --data-only novamart_customers \
 *      | psql -h node1 -U novamart_admin novamart_oltp
 *
 *  echo "[2/2] Migrating N-Z customers from Node 3..."
 *  pg_dump -h node3 -U replication_user -t customers --data-only novamart_inventory \
 *      | psql -h node1 -U novamart_admin novamart_oltp
 *
 *  echo "Migration complete."
 */


-- ┌──────────────────────────────────────────────────────────────────────────────┐
-- │  7.7  FOREIGN DATA WRAPPER (07_postgres_fdw.sql)                           │
-- │  Run on: NODE 1 — Replaces broken JavaScript memory joins with proper      │
-- │          database-level federation to Node 3's inventory.                  │
-- └──────────────────────────────────────────────────────────────────────────────┘

CREATE EXTENSION IF NOT EXISTS postgres_fdw;

CREATE SERVER node3_inventory
    FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host 'node3', port '5432', dbname 'novamart_inventory');

CREATE USER MAPPING FOR novamart_app
    SERVER node3_inventory
    OPTIONS (user 'readonly_user', password 'strong_password');

-- Import the remote tables as local foreign tables
CREATE SCHEMA IF NOT EXISTS foreign_tables;

IMPORT FOREIGN SCHEMA public
    LIMIT TO (inventory, warehouses, delivery_routes)
    FROM SERVER node3_inventory
    INTO foreign_tables;

-- Verification: the database now handles cross-node joins natively
-- SELECT o.order_id, o.customer_id, i.quantity_available
-- FROM orders o
-- JOIN foreign_tables.inventory i
--     ON o.product_id = i.product_id AND i.store_id = o.store_id
-- WHERE o.order_id = $1;


-- ┌──────────────────────────────────────────────────────────────────────────────┐
-- │  7.8  SAGA & OUTBOX TABLES (08_saga_outbox_tables.sql)                     │
-- │  Run on: NODE 1 — Fixes distributed transaction failures (partial orders)  │
-- │          using the Saga Pattern + Transactional Outbox Pattern.            │
-- └──────────────────────────────────────────────────────────────────────────────┘

-- Saga orchestration table
CREATE TABLE order_sagas (
    saga_id          UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id         BIGINT,
    status           VARCHAR(20)    NOT NULL DEFAULT 'started',
    steps_completed  JSONB          DEFAULT '[]'::jsonb,
    created_at       TIMESTAMPTZ    DEFAULT NOW(),
    updated_at       TIMESTAMPTZ    DEFAULT NOW()
);

-- Transactional outbox for reliable cross-node event delivery
CREATE TABLE saga_outbox (
    event_id      UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    saga_id       UUID           REFERENCES order_sagas(saga_id),
    event_type    VARCHAR(50)    NOT NULL,
    payload       JSONB          NOT NULL,
    destination   VARCHAR(50)    NOT NULL,     -- e.g. 'node3_inventory'
    status        VARCHAR(20)    DEFAULT 'pending',
    created_at    TIMESTAMPTZ    DEFAULT NOW(),
    processed_at  TIMESTAMPTZ
);

CREATE INDEX idx_outbox_pending ON saga_outbox (status) WHERE status = 'pending';


-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  END OF PART 7 — Distributed Architecture Integration                      ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝
