

CREATE SCHEMA IF NOT EXISTS novamart_part3;
SET search_path TO novamart_part3;

-- =====================================================
-- 1. Configuration Baseline
-- =====================================================

CREATE TABLE configuration_recommendations
(
    id SERIAL PRIMARY KEY,
    parameter_name VARCHAR(100),
    current_value VARCHAR(100),
    recommended_value VARCHAR(100),
    reason TEXT
);

INSERT INTO configuration_recommendations
(parameter_name,current_value,recommended_value,reason)
VALUES
('shared_buffers','128MB','32GB',
 '128GB RAM server requires larger cache'),

('effective_cache_size','4GB','96GB',
 'Allow planner to estimate available cache'),

('work_mem','4MB','64MB',
 'Prevent hash joins spilling to disk'),

('max_parallel_workers_per_gather','2','8',
 'Enable parallel query execution'),

('max_connections','100','200',
 'Support controlled application load'),

('checkpoint_completion_target','0.5','0.9',
 'Reduce checkpoint spikes'),

('wal_level','minimal','replica',
 'Required for replication and PITR'),

('archive_mode','off','on',
 'Enable WAL archiving'),

('checkpoint_timeout','30min','15min',
 'Improve recovery objectives');

-- =====================================================
-- 2. Replication Design
-- =====================================================

CREATE TABLE replication_strategy
(
    node_name VARCHAR(50),
    role_type VARCHAR(50),
    location_name VARCHAR(100),
    purpose TEXT
);

INSERT INTO replication_strategy VALUES
('Node1','Primary','Islamabad',
 'OLTP primary'),

('Node2','Standby','Islamabad',
 'Hot standby'),

('Node3','Standby','Islamabad',
 'Inventory replica'),

('Node4','Standby','Lahore',
 'Disaster recovery replica'),

('Node5','Analytics Replica','Lahore',
 'Reporting workload');

-- =====================================================
-- 3. Connection Pool Fix
-- =====================================================

CREATE TABLE connection_pool_plan
(
    application_servers INT,
    connections_per_server INT,
    total_connections INT,
    recommended_solution TEXT
);

INSERT INTO connection_pool_plan
VALUES
(
15,
50,
750,
'Deploy PgBouncer and reduce backend connections'
);

-- =====================================================
-- 4. Autovacuum Recovery
-- =====================================================

CREATE TABLE autovacuum_fix
(
    table_name VARCHAR(100),
    issue_found TEXT,
    remediation TEXT
);

INSERT INTO autovacuum_fix VALUES
('Products',
 'Autovacuum disabled 18 months',
 'Enable autovacuum and VACUUM FULL'),

('Orders',
 'Autovacuum disabled 18 months',
 'Enable autovacuum and VACUUM FULL'),

('OrderItems',
 'Autovacuum disabled 18 months',
 'Enable autovacuum and VACUUM FULL'),

('Customers',
 'Autovacuum disabled 18 months',
 'Enable autovacuum and VACUUM FULL');

-- =====================================================
-- 5. Monitoring Design
-- =====================================================

CREATE TABLE monitoring_metrics
(
    metric_name VARCHAR(150),
    reason TEXT
);

INSERT INTO monitoring_metrics VALUES
('Connection Utilization',
 'Detect connection exhaustion'),

('Query Latency',
 'Detect slow queries'),

('Deadlocks',
 'Detect transaction conflicts'),

('Checkpoint Duration',
 'Detect I/O bottlenecks'),

('Autovacuum Activity',
 'Detect table bloat'),

('Buffer Hit Ratio',
 'Detect cache inefficiency'),

('Replication Lag',
 'Detect DR issues'),

('Disk I/O',
 'Detect storage saturation'),

('WAL Generation',
 'Detect recovery readiness');

-- =====================================================
-- 6. PgBouncer Recommendation
-- =====================================================

CREATE TABLE pgbouncer_configuration
(
    setting_name VARCHAR(100),
    setting_value VARCHAR(100)
);

INSERT INTO pgbouncer_configuration VALUES
('pool_mode','session'),
('max_client_conn','1000'),
('default_pool_size','50'),
('reserve_pool_size','20');

-- =====================================================
-- 7. Disaster Recovery
-- =====================================================

CREATE TABLE disaster_recovery_plan
(
    control_name VARCHAR(150),
    implementation TEXT
);

INSERT INTO disaster_recovery_plan VALUES
(
'WAL Archiving',
'archive_mode=on'
),

(
'Point In Time Recovery',
'Use WAL archive retention'
),

(
'Streaming Replication',
'Primary + standby architecture'
),

(
'Monthly Restore Test',
'Verify backup integrity'
),

(
'Cross Site Backup',
'Islamabad + Lahore'
);

-- =====================================================
-- 8. Board Summary View
-- =====================================================

CREATE VIEW technical_landscape_summary AS
SELECT
'No Replication' AS issue,
'Implement Streaming Replication' AS solution

UNION ALL

SELECT
'Connection Storm',
'Deploy PgBouncer'

UNION ALL

SELECT
'Autovacuum Disabled',
'Re-enable Autovacuum'

UNION ALL

SELECT
'Default PostgreSQL Tuning',
'Apply Production Configuration'

UNION ALL

SELECT
'No Monitoring',
'Prometheus + Grafana'

UNION ALL

SELECT
'No WAL Archive',
'Enable PITR';

-- =====================================================
-- REPORT OUTPUT
-- =====================================================

SELECT * FROM technical_landscape_summary;