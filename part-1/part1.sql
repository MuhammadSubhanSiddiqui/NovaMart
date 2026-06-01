DROP SCHEMA IF EXISTS novamart_part1 CASCADE;
CREATE SCHEMA novamart_part1;
SET search_path TO novamart_part1;

CREATE TABLE business_verticals (
    vertical_id SERIAL PRIMARY KEY,
    vertical_name VARCHAR(100) NOT NULL UNIQUE,
    users_or_scale TEXT,
    main_risk TEXT
);

CREATE TABLE technology_stack (
    tech_id SERIAL PRIMARY KEY,
    component_name VARCHAR(120) NOT NULL,
    technology_name VARCHAR(120) NOT NULL,
    purpose TEXT,
    current_issue TEXT
);

CREATE TABLE problem_register (
    problem_id SERIAL PRIMARY KEY,
    problem_area VARCHAR(120) NOT NULL,
    problem_title VARCHAR(250) NOT NULL,
    evidence TEXT NOT NULL,
    root_cause TEXT NOT NULL,
    business_impact TEXT NOT NULL,
    priority VARCHAR(20) NOT NULL CHECK (priority IN ('Critical','High','Medium','Low')),
    proposed_solution TEXT NOT NULL,
    implementation_artifact TEXT,
    status VARCHAR(50) DEFAULT 'Identified'
);

CREATE TABLE remediation_controls (
    control_id SERIAL PRIMARY KEY,
    problem_id INT REFERENCES problem_register(problem_id),
    control_area VARCHAR(120),
    control_name VARCHAR(200),
    technical_action TEXT,
    expected_result TEXT
);

CREATE TABLE decision_log (
    decision_id SERIAL PRIMARY KEY,
    problem_id INT REFERENCES problem_register(problem_id),
    diagnosis TEXT,
    options_considered TEXT,
    chosen_option TEXT,
    justification TEXT,
    trade_off TEXT
);

CREATE TABLE recommended_db_roles (
    role_id SERIAL PRIMARY KEY,
    role_name VARCHAR(100),
    allowed_access TEXT,
    forbidden_access TEXT
);

CREATE TABLE monitoring_metrics (
    metric_id SERIAL PRIMARY KEY,
    metric_name VARCHAR(150),
    reason TEXT,
    alert_condition TEXT
);

CREATE TABLE disaster_recovery_plan (
    dr_id SERIAL PRIMARY KEY,
    current_failure TEXT,
    required_fix TEXT,
    target_rto TEXT,
    target_rpo TEXT
);

INSERT INTO business_verticals VALUES
(DEFAULT,'NovaMart Online','14 million users, 2.1 million SKUs, 80k–220k daily orders','Checkout failures, search mismatch, payment inconsistency'),
(DEFAULT,'NovaMart Retail','134 stores across 23 cities','POS inventory inconsistency and slow availability check'),
(DEFAULT,'NovaPay','2.3 million credit accounts, PKR 18 billion portfolio','Installment mismatch, orphan plans, wrong credit balance'),
(DEFAULT,'NovaLogistics','7 warehouses, 1200 vehicles','Partial order states and dispatch inconsistency');

INSERT INTO technology_stack VALUES
(DEFAULT,'Primary OLTP','PostgreSQL 16','Orders, customers, payments','Default tuning, no WAL archive, no replication'),
(DEFAULT,'BI Warehouse','MS SQL Server 2022 + SSAS','Reporting and analytics','Revenue, tax, city and default-rate reports incorrect'),
(DEFAULT,'Search','Elasticsearch 8.x','Product search','Consumer crashed, index stale for months'),
(DEFAULT,'Cache','Redis 7.x','Application cache','Permanent inventory cache, unsafe FLUSHDB runbook'),
(DEFAULT,'Middleware','Node.js','Unified access layer','Cross-node joins in JavaScript, partial writes'),
(DEFAULT,'Legacy System','Oracle 19c','Old monolith','Migration rushed, knowledge lost');

INSERT INTO problem_register
(problem_area, problem_title, evidence, root_cause, business_impact, priority, proposed_solution, implementation_artifact)
VALUES
('Migration Governance','Migration declared complete too early',
'18-month migration declared complete after 7 months due to investor pressure.',
'Business deadline overrode technical readiness.',
'Unstable production platform and hidden data defects.',
'Critical',
'Create migration readiness checklist, reconciliation tests, rollback plan, and formal sign-off.',
'Migration validation scripts, reconciliation reports, decision log'),

('Knowledge Management','No knowledge transfer from Oracle DBA team',
'Original Oracle engineers resigned within 30 days and documented nothing.',
'No mandatory KT process or operational documentation.',
'New junior team could not diagnose production behaviour.',
'High',
'Prepare architecture documents, runbooks, schema dictionary, and operational SOPs.',
'Runbook repository and schema documentation'),

('Architecture','Over-complicated heterogeneous architecture without governance',
'PostgreSQL, SQL Server, Elasticsearch, Redis and Node.js were introduced together.',
'Polyglot system was adopted without ownership, data contracts, or sync monitoring.',
'Data inconsistency and difficult troubleshooting.',
'Critical',
'Define source of truth, data ownership, service boundaries, and integration contracts.',
'Architecture decision record and data ownership matrix'),

('Data Consistency','Search price differs from product detail price',
'Customers saw different prices in search results and product detail page.',
'Elasticsearch/outbox synchronization was not monitored.',
'Revenue loss, customer disputes and legal risk.',
'Critical',
'Use PostgreSQL as source of truth, repair outbox consumer, add lag monitoring and reconciliation.',
'Outbox replay script, search-index reconciliation script'),

('Payment Integrity','Cancelled orders charged',
'Customers complained cancelled orders had already been charged.',
'Order and payment states were not managed transactionally.',
'Refund cost, customer trust loss, regulatory exposure.',
'Critical',
'Implement payment state machine and transactional order/payment workflow.',
'Payment state table, idempotency key, reconciliation job'),

('Loyalty','Loyalty rewards credited to wrong account',
'Complaints showed rewards going to incorrect customer accounts.',
'Weak validation and missing audit trail.',
'Customer dissatisfaction and financial accounting errors.',
'High',
'Use strict FK validation, immutable loyalty ledger, and audit log.',
'Loyalty ledger table and audit trigger'),

('NovaPay','Installment statements do not match payment history',
'Installment statements differed from actual payment history.',
'Multiple code paths update balances without ledger model.',
'Credit disputes and wrong financial statements.',
'Critical',
'Replace mutable balance logic with immutable ledger and reconciliation.',
'NovaPay ledger schema and balance verification query'),

('Operations','Customer complaints handled individually',
'Management did not detect pattern for months.',
'No incident classification or trend analysis.',
'Six months degraded state remained unnoticed.',
'High',
'Centralize tickets, classify incidents, and build RCA dashboard.',
'Incident category table and trend report view'),

('Security','Plaintext database credentials',
'Credentials stored in /etc/novamart/db.conf.',
'No secret management process.',
'Attacker quickly obtained DB credentials.',
'Critical',
'Move secrets to vault, rotate passwords, restrict file permissions.',
'Vault configuration, credential rotation log'),

('Security','Application account has SUPERUSER privilege',
'novamart_app connected as PostgreSQL superuser.',
'No least-privilege database access model.',
'Single compromised app server became full database compromise.',
'Critical',
'Create separate read/write/admin roles and revoke superuser from app role.',
'RBAC SQL script'),

('Security','No database audit logging',
'pg_audit installed but never configured; audit log empty.',
'Audit control was installed but not operationalized.',
'Forensic investigation lacked database evidence.',
'Critical',
'Enable pg_audit, log sensitive table access, retain immutable logs.',
'pg_audit config and sample audit logs'),

('Security','SQL injection surface',
'Post-incident penetration test found 23 SQL injection points.',
'Developers used string concatenation for SQL.',
'Customer and admin data could be extracted.',
'Critical',
'Use parameterized queries, prepared statements, SAST checks, and injection tests.',
'Patched query examples and SQLi test suite'),

('Security','Full card PAN retained in customers table',
'card_last_sixteen contained full 16-digit PAN for 2.3 million customers.',
'Unsafe legacy feature removed but data not classified or deleted.',
'PCI non-compliance and customer data breach.',
'Critical',
'Classify PAN data, tokenize/encrypt legally retained records, purge non-required records.',
'PAN classification report and tokenization script'),

('Security','Transport encryption not enforced',
'PostgreSQL ssl=prefer allowed plaintext fallback.',
'TLS incompatibility was tracked but not fixed.',
'Customer data readable on internal network.',
'Critical',
'Set ssl=require, fix client TLS, rotate certificates, verify encrypted connections.',
'TLS config and certificate generation procedure'),

('Security','Data at rest not encrypted',
'PostgreSQL data directory on unencrypted ext4 filesystem.',
'Filesystem access bypassed database permissions.',
'Base table files could be read directly.',
'Critical',
'Enable disk encryption and protect keys through KMS.',
'Encryption-at-rest deployment notes'),

('Disaster Recovery','No WAL archiving / no PITR',
'wal_level=minimal and archive_mode disabled.',
'Recovery could not meet 30-minute RTO.',
'Data loss and 4h+ recovery during ransomware.',
'Critical',
'Set wal_level=replica, enable WAL archiving and PITR restore drills.',
'postgresql.conf changes and restore test script'),

('Replication','No replication between PostgreSQL nodes',
'Five nodes existed but no replication of any kind.',
'Replication setup was deferred after TLS issue.',
'Single node failure makes data unavailable.',
'Critical',
'Implement streaming replication and cross-DC standby.',
'Replication setup script'),

('Performance','PostgreSQL default configuration on large hardware',
'shared_buffers=128MB, effective_cache_size=4GB on 128GB RAM server.',
'No deliberate tuning after installation.',
'Slow queries and poor resource usage.',
'High',
'Tune shared_buffers, effective_cache_size, work_mem, checkpoint and parallel settings.',
'postgresql.conf tuned template'),

('Performance','Autovacuum disabled on major tables',
'Products, Orders, OrderItems and Customers not vacuumed for 18 months.',
'Mistaken correlation between autovacuum and performance incident.',
'Severe bloat and slow queries.',
'High',
'Re-enable autovacuum, run VACUUM/REINDEX plan, monitor dead tuples.',
'vacuum maintenance script'),

('Connection Management','Connection pool overload',
'15 app servers x 50 connections = 750 demand against max_connections=100.',
'No deployed PgBouncer and wrong pool sizing.',
'503 errors and restarts during load.',
'Critical',
'Deploy PgBouncer carefully, reduce app pool size, avoid transaction pooling where incompatible.',
'PgBouncer config and connection test'),

('Monitoring','Only server ping monitoring exists',
'No query latency, locks, connections, buffer hit, vacuum or WAL metrics.',
'Monitoring designed for uptime only.',
'Failures detected by customer complaints.',
'Critical',
'Deploy Prometheus, PostgreSQL exporter, Grafana dashboards and alert rules.',
'docker-compose monitoring stack'),

('Data Modeling','Products table mixes unrelated entities',
'Physical, digital, financial and logistics products stored in one 47-column table.',
'Poor polymorphic design and many nullable columns.',
'Bad planner estimates and data quality issues.',
'High',
'Split product subtype tables and use validated JSONB only where appropriate.',
'Product normalization migration'),

('Data Quality','Customers.profile_data is malformed VARCHAR JSON',
'23 percent rows contain malformed JSON.',
'VARCHAR used instead of JSONB and import truncated data.',
'Wrong addresses used by mailer and invoice generator.',
'High',
'Validate JSON, convert valid rows to JSONB, quarantine malformed rows, normalize addresses.',
'JSON validation and cleanup script'),

('Data Integrity','NovaPay orphan plans',
'340,000 plan rows have no corresponding customer, order or product.',
'FK constraints disabled and never re-enabled.',
'Deduction batch wastes runtime and financial obligations are unclear.',
'Critical',
'Classify orphan plans, restore FKs after remediation, create exception workflow.',
'Orphan classification and FK validation script'),

('Concurrency','Phantom inventory / overselling',
'Read-decide-write inventory flow has no isolation control.',
'Concurrent checkouts oversell inventory.',
'Cancellations, express shipping cost and customer distrust.',
'Critical',
'Use SELECT FOR UPDATE or SERIALIZABLE transaction for inventory reservation.',
'Checkout transaction patch and concurrency test'),

('Concurrency','Lost updates in NovaPay available_credit',
'Multiple code paths read, modify and write available_credit without version check.',
'No optimistic/pessimistic concurrency control.',
'Balances drift from audit log.',
'Critical',
'Use ledger or optimistic concurrency version column.',
'available_credit reconciliation and OCC test'),

('Concurrency','Deadlock storm',
'Order placement locks Inventory then OrderItems; cancellation locks opposite order.',
'Inconsistent lock ordering.',
'Retries amplify lock pressure.',
'High',
'Standardize lock order and add bounded retry with backoff.',
'Deadlock reproduction and fix test'),

('Distributed Transactions','Partial order states across nodes',
'Order, inventory, NovaPay plan and logistics writes are independent.',
'No distributed transaction or saga pattern.',
'340 partial failures weekly.',
'Critical',
'Implement Saga with compensating actions and idempotency.',
'Saga state table and compensation scripts'),

('Warehouse','Revenue overstated',
'Warehouse revenue excludes refunds, cancellations and discounts.',
'ETL logic incomplete.',
'PKR 340M phantom revenue.',
'Critical',
'Correct revenue fact calculation and reconcile with bank/audit trail.',
'ETL correction script'),

('Warehouse','Customer city history overwritten',
'Customer_Dim uses Type 1 SCD for city.',
'Historical attributes not preserved.',
'Regional revenue attribution wrong.',
'High',
'Use Type 2 SCD for customer geography.',
'SCD Type 2 migration'),

('Warehouse','Wrong tax date dimension',
'Cube uses order_date for revenue quarter.',
'Tax requires payment_received_date.',
'Incorrect Q3 tax filing risk.',
'Critical',
'Expose separate date dimensions and use payment date for tax reporting.',
'SSAS/date-dimension correction'),

('Warehouse','Basket size understated',
'POS fragments one visit into multiple orders.',
'Warehouse lacks visit/session grain.',
'Store manager commissions underpaid.',
'High',
'Create visit/session fact and recompute basket size.',
'Basket-size correction script'),

('Warehouse','Default rate overstated',
'Restructured and reversed plans classified incorrectly.',
'Default definition not aligned with business reality.',
'Loan loss reserves overstated.',
'Critical',
'Create correct default classification rules.',
'NovaPay default-rate recomputation script');

INSERT INTO remediation_controls
(problem_id, control_area, control_name, technical_action, expected_result)
SELECT problem_id,'Governance','Decision Log',
'Maintain diagnosis, options, chosen solution and trade-off for each problem.',
'Board and evaluator can verify why each problem was selected.'
FROM problem_register;

INSERT INTO recommended_db_roles VALUES
(DEFAULT,'novamart_app_read','SELECT only on required application views','No direct access to PAN, audit logs, admin tables'),
(DEFAULT,'novamart_app_write','INSERT/UPDATE through controlled procedures only','No SUPERUSER, no DDL, no unrestricted SELECT *'),
(DEFAULT,'novapay_service','NovaPay ledger and plan procedures only','No direct customer table dump'),
(DEFAULT,'support_readonly','Single-customer lookup views only','No bulk customer export'),
(DEFAULT,'etl_loader','Warehouse staging tables and ETL procedures','No OLTP admin privileges'),
(DEFAULT,'db_admin','DDL and maintenance only through controlled admin login','No application usage');

INSERT INTO disaster_recovery_plan VALUES
(DEFAULT,'wal_level=minimal and no WAL archive','Set wal_level=replica, archive_mode=on, archive_command configured','30 minutes','5 minutes'),
(DEFAULT,'No tested restore process','Monthly restore drill and automated PITR verification','30 minutes','5 minutes'),
(DEFAULT,'Backups only in Islamabad NAS','Encrypted offsite backups and cross-DC standby','30 minutes','5 minutes'),
(DEFAULT,'No replication between nodes','Streaming replication with monitored lag','30 minutes','Near zero for replicated datasets');

INSERT INTO monitoring_metrics VALUES
(DEFAULT,'pg_stat_activity active connections','Detect connection saturation','Active connections > 80% max_connections'),
(DEFAULT,'query p95 latency','Detect slow query degradation','p95 latency exceeds SLA for 5 minutes'),
(DEFAULT,'deadlocks per minute','Detect deadlock storm','deadlocks > threshold in 10 minutes'),
(DEFAULT,'autovacuum activity and dead tuples','Detect bloat growth','dead tuples exceed configured ratio'),
(DEFAULT,'WAL archive lag','Ensure PITR readiness','archive lag > 5 minutes'),
(DEFAULT,'replication lag','Ensure standby usability','lag > 30 seconds'),
(DEFAULT,'Elasticsearch outbox lag','Detect stale search index','unprocessed events > threshold'),
(DEFAULT,'Redis inventory keys without TTL','Detect stale inventory cache','inventory key TTL = -1'),
(DEFAULT,'failed payment reconciliation count','Detect payment inconsistency','daily mismatch count > 0'),
(DEFAULT,'warehouse revenue variance','Detect reporting mismatch','warehouse differs from bank/audit > tolerance');

INSERT INTO decision_log
(problem_id, diagnosis, options_considered, chosen_option, justification, trade_off)
SELECT
problem_id,
'Evidence taken from case study symptoms, incident reports, technical landscape and forensic findings.',
'Option A: ignore; Option B: document only; Option C: implement technical remediation with tests.',
'Option C: implement technical remediation with test evidence.',
'Case study requires runnable artefacts, test scripts, benchmarks and technical proof, not only narrative.',
'Full remediation is larger than project window, so critical security, recovery, consistency and stability issues are prioritized.'
FROM problem_register;

CREATE VIEW critical_issue_report AS
SELECT
    problem_id,
    problem_area,
    problem_title,
    root_cause,
    business_impact,
    proposed_solution,
    implementation_artifact
FROM problem_register
WHERE priority = 'Critical'
ORDER BY problem_id;

CREATE VIEW priority_summary AS
SELECT priority, COUNT(*) AS total
FROM problem_register
GROUP BY priority
ORDER BY
CASE priority
    WHEN 'Critical' THEN 1
    WHEN 'High' THEN 2
    WHEN 'Medium' THEN 3
    ELSE 4
END;

CREATE VIEW area_summary AS
SELECT problem_area, COUNT(*) AS total_issues
FROM problem_register
GROUP BY problem_area
ORDER BY total_issues DESC;

CREATE VIEW board_summary AS
SELECT
    'Total Problems Identified' AS item,
    COUNT(*)::TEXT AS value
FROM problem_register
UNION ALL
SELECT
    'Critical Problems',
    COUNT(*)::TEXT
FROM problem_register
WHERE priority='Critical'
UNION ALL
SELECT
    'High Problems',
    COUNT(*)::TEXT
FROM problem_register
WHERE priority='High'
UNION ALL
SELECT
    'Main Recommendation',
    'Fix security, DR, replication, connection pooling, data consistency, concurrency, warehouse accuracy and monitoring first';

CREATE VIEW part1_final_submission AS
SELECT
    p.problem_id,
    p.problem_area,
    p.problem_title,
    p.evidence,
    p.root_cause,
    p.business_impact,
    p.priority,
    p.proposed_solution,
    p.implementation_artifact,
    d.chosen_option,
    d.justification,
    d.trade_off
FROM problem_register p
LEFT JOIN decision_log d ON d.problem_id = p.problem_id
ORDER BY
CASE p.priority
    WHEN 'Critical' THEN 1
    WHEN 'High' THEN 2
    WHEN 'Medium' THEN 3
    ELSE 4
END,
p.problem_id;

-- Security example artefact: least privilege roles
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'novamart_app_read') THEN
        CREATE ROLE novamart_app_read NOLOGIN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'novamart_app_write') THEN
        CREATE ROLE novamart_app_write NOLOGIN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'novapay_service') THEN
        CREATE ROLE novapay_service NOLOGIN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'support_readonly') THEN
        CREATE ROLE support_readonly NOLOGIN;
    END IF;
END $$;

-- Example safe business tables for Part 1 modelling
CREATE TABLE customers_clean_target (
    customer_id BIGSERIAL PRIMARY KEY,
    full_name VARCHAR(150) NOT NULL,
    email VARCHAR(150),
    phone VARCHAR(30),
    city VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE customer_profile_jsonb_target (
    profile_id BIGSERIAL PRIMARY KEY,
    customer_id BIGINT REFERENCES customers_clean_target(customer_id),
    profile_data JSONB NOT NULL,
    is_valid BOOLEAN DEFAULT TRUE
);

CREATE TABLE products_master_target (
    product_id BIGSERIAL PRIMARY KEY,
    sku VARCHAR(80) UNIQUE NOT NULL,
    product_name VARCHAR(250) NOT NULL,
    product_type VARCHAR(50) NOT NULL CHECK (product_type IN ('Physical','Digital','Financial','Logistics')),
    price NUMERIC(14,2) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE
);

CREATE TABLE product_enrichment_target (
    enrichment_id BIGSERIAL PRIMARY KEY,
    product_id BIGINT REFERENCES products_master_target(product_id),
    attributes JSONB NOT NULL
);

CREATE TABLE orders_target (
    order_id BIGSERIAL PRIMARY KEY,
    customer_id BIGINT REFERENCES customers_clean_target(customer_id),
    order_status VARCHAR(50) NOT NULL,
    total_amount NUMERIC(14,2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE payment_ledger_target (
    ledger_id BIGSERIAL PRIMARY KEY,
    order_id BIGINT REFERENCES orders_target(order_id),
    customer_id BIGINT REFERENCES customers_clean_target(customer_id),
    transaction_type VARCHAR(50) NOT NULL,
    debit NUMERIC(14,2) DEFAULT 0,
    credit NUMERIC(14,2) DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE audit_log_target (
    audit_id BIGSERIAL PRIMARY KEY,
    table_name VARCHAR(100),
    action_name VARCHAR(20),
    record_id TEXT,
    changed_by TEXT DEFAULT current_user,
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    old_data JSONB,
    new_data JSONB
);

CREATE TABLE outbox_events_target (
    event_id BIGSERIAL PRIMARY KEY,
    aggregate_name VARCHAR(100),
    aggregate_id BIGINT,
    event_type VARCHAR(100),
    payload JSONB,
    processed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMP
);

CREATE TABLE inventory_target (
    inventory_id BIGSERIAL PRIMARY KEY,
    product_id BIGINT REFERENCES products_master_target(product_id),
    store_id INT NOT NULL,
    available_qty INT NOT NULL CHECK (available_qty >= 0),
    UNIQUE(product_id, store_id)
);

CREATE TABLE novapay_ledger_target (
    ledger_id BIGSERIAL PRIMARY KEY,
    customer_id BIGINT REFERENCES customers_clean_target(customer_id),
    order_id BIGINT REFERENCES orders_target(order_id),
    plan_id BIGINT,
    transaction_type VARCHAR(50),
    debit NUMERIC(14,2) DEFAULT 0,
    credit NUMERIC(14,2) DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE saga_order_workflow_target (
    saga_id BIGSERIAL PRIMARY KEY,
    order_id BIGINT,
    current_step VARCHAR(100),
    status VARCHAR(50),
    compensation_required BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Sample data
INSERT INTO customers_clean_target(full_name,email,phone,city) VALUES
('Ali Khan','ali@example.com','03001234567','Lahore'),
('Sara Ahmed','sara@example.com','03111234567','Karachi'),
('Usman Malik','usman@example.com','03211234567','Islamabad');

INSERT INTO products_master_target(sku,product_name,product_type,price) VALUES
('SKU-1001','Laptop Pro 15','Physical',180000),
('SKU-1002','Streaming Subscription','Digital',1500),
('SKU-1003','NovaPay Installment Plan','Financial',0);

INSERT INTO product_enrichment_target(product_id,attributes) VALUES
(1,'{"weight_kg":2.1,"screen_size":"15 inch","brand":"NovaTech"}'),
(2,'{"duration_months":12,"license_type":"subscription"}'),
(3,'{"term_months":12,"interest_rate":18.5}');

INSERT INTO inventory_target(product_id,store_id,available_qty) VALUES
(1,1,25),
(1,2,10),
(2,1,999);

INSERT INTO orders_target(customer_id,order_status,total_amount) VALUES
(1,'Completed',180000),
(2,'Cancelled',1500);

INSERT INTO payment_ledger_target(order_id,customer_id,transaction_type,debit,credit) VALUES
(1,1,'PAYMENT_RECEIVED',0,180000),
(2,2,'REFUND_REQUIRED',1500,0);

INSERT INTO outbox_events_target(aggregate_name,aggregate_id,event_type,payload) VALUES
('Product',1,'PRODUCT_PRICE_UPDATED','{"sku":"SKU-1001","price":180000}'),
('Inventory',1,'INVENTORY_CHANGED','{"product_id":1,"store_id":1,"qty":25}');

-- Final report outputs
SELECT * FROM board_summary;
SELECT * FROM priority_summary;
SELECT * FROM area_summary;
SELECT * FROM critical_issue_report;
SELECT * FROM part1_final_submission;