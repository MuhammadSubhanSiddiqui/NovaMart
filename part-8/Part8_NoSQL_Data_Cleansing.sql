-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║                                                                            ║
-- ║   NOVAMART — PART 8: NoSQL LAYERS & DATA CLEANSING                         ║
-- ║                                                                            ║
-- ║   Database Engine  : PostgreSQL 16+ (JSONB / Logical Replication)          ║
-- ║   Target Node      : Node 1 (Primary OLTP)                                ║
-- ║   Execution Order  : Run sections sequentially (8.1 through 8.6)           ║
-- ║                                                                            ║
-- ║   NOTE: The Elasticsearch lag monitoring script (Section 8.6) is           ║
-- ║         embedded in a block comment. Extract and run via cron.             ║
-- ║                                                                            ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝


-- ┌──────────────────────────────────────────────────────────────────────────────┐
-- │  8.1  JSONB SCHEMA DISCOVERY (09_jsonb_discovery.sql)                      │
-- │  Purpose: Discover all distinct representations of the screen_size         │
-- │           attribute and its alias display_size in the NoSQL JSONB column.  │
-- └──────────────────────────────────────────────────────────────────────────────┘

-- Discover heterogeneous types stored under 'screen_size'
SELECT
    jsonb_typeof(attributes->'screen_size')     AS type_of_screen_size,
    LEFT(attributes->>'screen_size', 50)        AS sample_value,
    COUNT(*)                                     AS occurrences
FROM product_enrichment
WHERE attributes ? 'screen_size'
  AND attributes->>'category' = 'television'
GROUP BY 1, 2
ORDER BY 3 DESC;

-- Discover usage of the alias 'display_size'
SELECT
    jsonb_typeof(attributes->'display_size')    AS type_of_display_size,
    LEFT(attributes->>'display_size', 50)       AS sample_value,
    COUNT(*)                                     AS occurrences
FROM product_enrichment
WHERE attributes ? 'display_size'
  AND attributes->>'category' = 'television'
GROUP BY 1, 2
ORDER BY 3 DESC;


-- ┌──────────────────────────────────────────────────────────────────────────────┐
-- │  8.2  JSONB NORMALIZATION (10_jsonb_normalize.sql)                         │
-- │  Purpose: Normalize all screen_size variants (string "55 inches",          │
-- │           object {"size": 55}, array [55]) to a canonical numeric value.   │
-- └──────────────────────────────────────────────────────────────────────────────┘

-- Normalize screen_size to numeric for all televisions
UPDATE product_enrichment
SET attributes = jsonb_set(
    attributes,
    '{screen_size}',
    to_jsonb(
        CASE
            WHEN jsonb_typeof(attributes->'screen_size') = 'number'
                THEN (attributes->>'screen_size')::numeric
            WHEN jsonb_typeof(attributes->'screen_size') = 'string'
                THEN regexp_replace(attributes->>'screen_size', '[^0-9.]', '', 'g')::numeric
            WHEN jsonb_typeof(attributes->'screen_size') = 'object'
                THEN (attributes->'screen_size'->>'size')::numeric
            WHEN jsonb_typeof(attributes->'screen_size') = 'array'
                THEN (attributes->'screen_size'->>0)::numeric
            ELSE NULL
        END
    )
)
WHERE attributes->>'category' = 'television'
  AND attributes ? 'screen_size'
  AND jsonb_typeof(attributes->'screen_size') != 'number';

-- Merge the alias 'display_size' into 'screen_size' where screen_size is missing
UPDATE product_enrichment
SET attributes = (attributes - 'display_size')
WHERE attributes->>'category' = 'television'
  AND attributes ? 'display_size'
  AND NOT (attributes ? 'screen_size');


-- ┌──────────────────────────────────────────────────────────────────────────────┐
-- │  8.3  JSONB VALIDATION CONSTRAINT (11_jsonb_validation.sql)                │
-- │  Purpose: Add database-level checks to prevent future bad JSON writes.     │
-- └──────────────────────────────────────────────────────────────────────────────┘

-- Validation function: enforces type rules per product category
CREATE OR REPLACE FUNCTION validate_product_attributes(attrs JSONB)
RETURNS BOOLEAN AS $$
BEGIN
    -- Television: screen_size must be numeric
    IF attrs->>'category' = 'television' THEN
        IF attrs ? 'screen_size' AND jsonb_typeof(attrs->'screen_size') != 'number' THEN
            RETURN FALSE;
        END IF;
    END IF;

    -- Refrigerator: capacity_liters must be numeric
    IF attrs->>'category' = 'refrigerator' THEN
        IF attrs ? 'capacity_liters' AND jsonb_typeof(attrs->'capacity_liters') != 'number' THEN
            RETURN FALSE;
        END IF;
    END IF;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Enforce the constraint
ALTER TABLE product_enrichment
    ADD CONSTRAINT chk_attributes_schema
    CHECK (validate_product_attributes(attributes));


-- ┌──────────────────────────────────────────────────────────────────────────────┐
-- │  8.4  CATEGORY REFERENCE SCHEMAS (12_category_schemas.sql)                 │
-- │  Purpose: Store canonical schemas per category for dynamic validation       │
-- │           and drop the default GIN index to prepare for jsonb_path_ops.    │
-- └──────────────────────────────────────────────────────────────────────────────┘

CREATE TABLE category_schemas (
    category         VARCHAR(100)   PRIMARY KEY,
    required_fields  JSONB          NOT NULL,
    optional_fields  JSONB          NOT NULL,
    updated_at       TIMESTAMPTZ    DEFAULT NOW()
);

INSERT INTO category_schemas (category, required_fields, optional_fields) VALUES
    ('television',
     '{"screen_size": "number", "resolution": "string", "smart_tv": "boolean"}',
     '{}'),
    ('refrigerator',
     '{"capacity_liters": "number", "energy_rating": "string"}',
     '{"frost_free": "boolean"}');

-- Drop the inefficient default GIN index to prepare for jsonb_path_ops
DROP INDEX IF EXISTS idx_product_enrichment_attributes;


-- ┌──────────────────────────────────────────────────────────────────────────────┐
-- │  8.5  DEBEZIUM CDC PUBLICATION (13_create_publication.sql)                  │
-- │  Purpose: Create a PostgreSQL logical publication for Kafka CDC via         │
-- │           Debezium, streaming product changes to Elasticsearch.            │
-- └──────────────────────────────────────────────────────────────────────────────┘

CREATE PUBLICATION products_publication
    FOR TABLE products, product_enrichment;


-- ┌──────────────────────────────────────────────────────────────────────────────┐
-- │  8.6  ELASTICSEARCH LAG MONITOR (14_check_es_lag.sh)                       │
-- │  Action: Extract the script below and schedule via cron (e.g. every 5m).   │
-- └──────────────────────────────────────────────────────────────────────────────┘

/*
 *  ── Shell Script: check_es_lag.sh ──
 *
 *  #!/bin/bash
 *  # Monitors the Elasticsearch outbox consumer backlog.
 *  # Alert if more than 1000 unprocessed events older than 5 minutes.
 *
 *  LAG=$(psql -h node1 -U monitor_user -d novamart_oltp -t -c \
 *      "SELECT COUNT(*) FROM es_outbox
 *       WHERE processed = FALSE
 *         AND created_at < NOW() - interval '5 minutes'")
 *
 *  if [ "$LAG" -gt 1000 ]; then
 *      curl -X POST "https://alerts.novamart.pk/webhook" \
 *          -d "{\"alert\": \"ES outbox lag critical\", \"lag\": $LAG}"
 *  fi
 *
 *  # Cron entry (every 5 minutes):
 *  # */5 * * * *  /opt/novamart/scripts/check_es_lag.sh >> /var/log/es_lag.log 2>&1
 */


-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  END OF PART 8 — NoSQL Layers & Data Cleansing                             ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝
