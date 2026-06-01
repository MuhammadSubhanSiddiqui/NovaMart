-- =========================================================
-- NovaMart Case Study
-- Part 11: How the System Is Operated
-- =========================================================

DROP SCHEMA IF EXISTS novamart_part11 CASCADE;
CREATE SCHEMA novamart_part11;
SET search_path TO novamart_part11;

-- =========================================================
-- 1. Problem Register
-- =========================================================

CREATE TABLE problem_register (
    id SERIAL PRIMARY KEY,
    area VARCHAR(100) NOT NULL,
    problem TEXT NOT NULL,
    evidence TEXT NOT NULL,
    impact TEXT NOT NULL,
    solution TEXT NOT NULL,
    priority VARCHAR(20) NOT NULL
);

INSERT INTO problem_register
(area, problem, evidence, impact, solution, priority)
VALUES
('Runbook',
 'The existing runbook is outdated and generic.',
 'The runbook was written during migration and was never updated. It gives almost the same response for different alerts.',
 'Operators restart services instead of diagnosing the real problem. This causes repeat incidents and unnecessary downtime.',
 'Create separate runbooks for PostgreSQL, Redis, application servers, backups, WAL archive, deadlocks and connection issues. Review them monthly.',
 'Critical'),

('Runbook',
 'There are no diagnostic steps before taking action.',
 'The documented actions are restart connection pool, restart Redis with FLUSHDB, or escalate.',
 'The team treats symptoms instead of root causes.',
 'Every alert must include checks, diagnosis, safe action, verification and escalation steps.',
 'Critical'),

('Redis',
 'FLUSHDB is used as a standard operational response.',
 'The runbook allows Redis restart with FLUSHDB.',
 'Clearing the whole cache forces all traffic back to the database and creates overload.',
 'Remove FLUSHDB from normal operations. Use selective cache invalidation and proper TTLs.',
 'High'),

('Performance',
 'No deliberate PostgreSQL performance tuning exists.',
 'The PostgreSQL configuration is still close to post-installation defaults.',
 'The database does not use available hardware properly.',
 'Apply a production tuning baseline and review it after load testing.',
 'High'),

('Performance',
 'Autovacuum was disabled on major tables.',
 'Autovacuum was disabled on Products, Orders, OrderItems and Customers for eighteen months.',
 'Dead tuples accumulated and table bloat became severe.',
 'Re-enable autovacuum and run controlled VACUUM ANALYZE and REINDEX operations.',
 'Critical'),

('Performance',
 'The original performance issue was never investigated.',
 'Autovacuum was blamed without proving causation.',
 'A wrong fix stayed in production and created larger problems.',
 'Introduce mandatory Root Cause Analysis for every major incident.',
 'High'),

('Performance',
 'Large tables have serious bloat.',
 'Products is 4.2x, Orders 3.8x, OrderItems 5.1x, Customers 2.4x their live row size.',
 'Queries, backups and indexes become slower and larger.',
 'Create a maintenance window for vacuum, analyze, reindex and bloat monitoring.',
 'Critical'),

('Connection Pool',
 'Application servers can open far more connections than the database accepts.',
 '15 application servers with 50 connections each create 750 possible connections against max_connections of 100.',
 'Requests wait for connections and finally return 503 errors.',
 'Deploy PgBouncer and reduce application pool sizes.',
 'Critical'),

('Connection Pool',
 'Restarting application servers is used as a fix.',
 'Operations restart application servers until queues clear.',
 'This produces 8 to 12 minutes of degraded service and does not solve the root cause.',
 'Use restart only as emergency action after diagnosis. Fix connection pooling properly.',
 'High'),

('Connection Pool',
 'PgBouncer configuration exists but is not deployed.',
 'The team started PgBouncer deployment but never completed it.',
 'The connection problem continued for months.',
 'Assign an owner and deploy PgBouncer after compatibility testing.',
 'Critical'),

('Connection Pool',
 'PgBouncer is configured in the wrong pooling mode.',
 'Transaction pooling is incompatible with named prepared statements and advisory locks used by the application.',
 'Deploying this configuration can break product search and inventory reservation.',
 'Use session pooling first, or refactor application features before using transaction pooling.',
 'Critical'),

('Change Management',
 'Operational changes are not tracked properly.',
 'There is no documentation explaining why PgBouncer deployment was stopped.',
 'Important work is forgotten and temporary fixes become permanent.',
 'Introduce a change log with owner, risk, approval status and rollback plan.',
 'High'),

('Backup and Recovery',
 'Backups are not regularly tested.',
 'Backups run daily, but older backups have not been tested.',
 'The company does not know whether backups are recoverable.',
 'Add restore tests and keep validation evidence.',
 'Critical'),

('Backup and Recovery',
 'WAL archiving is not configured.',
 'wal_level is minimal and WAL archive is disabled.',
 'Point-in-time recovery is not possible.',
 'Set wal_level to replica and enable archive_mode with a tested archive command.',
 'Critical'),

('Backup and Recovery',
 'The disaster recovery plan is unrealistic.',
 'The plan promises 30-minute RTO, but actual recovery took 4 hours and 12 minutes.',
 'The business cannot rely on the documented DR plan.',
 'Run quarterly DR drills and measure actual RTO and RPO.',
 'Critical'),

('Backup and Recovery',
 'No recovery drill has been conducted.',
 'The disaster recovery plan has never been tested.',
 'The team improvises during real incidents.',
 'Create a formal DR drill schedule and evidence log.',
 'Critical'),

('Monitoring',
 'Monitoring is limited to server availability ping.',
 'Query latency, connection utilization, locks, autovacuum, checkpoints, WAL and I/O are not monitored.',
 'The team learns about problems from users instead of systems.',
 'Deploy PostgreSQL exporter, Prometheus and Grafana dashboards.',
 'Critical'),

('Monitoring',
 'Alerts do not have clear owners.',
 'The runbook mostly escalates to engineering without specific ownership.',
 'Alerts are delayed or ignored.',
 'Create an alert ownership matrix with primary owner, backup owner and escalation time.',
 'High'),

('Training',
 'The operations team lacks PostgreSQL and PgBouncer knowledge.',
 'The team did not understand transaction pooling compatibility issues.',
 'A wrong fix may create another outage.',
 'Train the team on PostgreSQL operations, PgBouncer, backup recovery and incident handling.',
 'High');

-- =========================================================
-- 2. Practical Operational Artefacts
-- =========================================================

CREATE TABLE runbooks (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    service_area VARCHAR(100),
    owner_name VARCHAR(100),
    review_cycle VARCHAR(50),
    status VARCHAR(50)
);

INSERT INTO runbooks
(name, service_area, owner_name, review_cycle, status)
VALUES
('PostgreSQL Connection Exhaustion Runbook', 'Database', 'DBA Lead', 'Monthly', 'Active'),
('Redis Safe Cache Invalidation Runbook', 'Cache', 'Platform Lead', 'Monthly', 'Active'),
('Autovacuum and Bloat Maintenance Runbook', 'Database', 'DBA Lead', 'Monthly', 'Active'),
('Backup Restore Validation Runbook', 'DR', 'DR Lead', 'Monthly', 'Active'),
('WAL Archive Failure Runbook', 'DR', 'DBA Lead', 'Monthly', 'Active'),
('Deadlock Investigation Runbook', 'Database', 'Engineering Lead', 'Monthly', 'Active'),
('HTTP 503 Diagnostic Runbook', 'Application', 'SRE Lead', 'Monthly', 'Active');

CREATE TABLE diagnostic_steps (
    id SERIAL PRIMARY KEY,
    alert_name TEXT NOT NULL,
    what_to_check TEXT NOT NULL,
    safe_action TEXT NOT NULL,
    action_to_avoid TEXT NOT NULL
);

INSERT INTO diagnostic_steps
(alert_name, what_to_check, safe_action, action_to_avoid)
VALUES
('High DB Connections',
 'Check pg_stat_activity, waiting queries, idle transactions, PgBouncer stats and application pool usage.',
 'Reduce pool pressure, terminate only confirmed idle blockers, and route through PgBouncer.',
 'Blind restart of all application servers'),

('HTTP 503 Errors',
 'Check database connection wait time, slow queries, application queue time and recent deployments.',
 'Reduce traffic, fix connection bottleneck and verify recovery.',
 'Repeated restart without diagnosis'),

('Redis Inventory Cache Issue',
 'Check affected key, TTL, database inventory value and recent inventory update.',
 'Delete only the affected inventory key.',
 'FLUSHDB'),

('Deadlock Storm',
 'Check lock waits, deadlock logs and transaction lock order.',
 'Apply bounded retry and fix inconsistent lock ordering.',
 'Immediate infinite retry'),

('Autovacuum Lag',
 'Check dead tuples, last_autovacuum and vacuum progress.',
 'Run controlled VACUUM ANALYZE and tune autovacuum.',
 'Disabling autovacuum'),

('WAL Archive Failure',
 'Check archive command, disk space, archive destination and WAL backlog.',
 'Fix archive destination and verify restore chain.',
 'Ignoring WAL archive failure'),

('Checkpoint Spike',
 'Check checkpoint duration, write latency and bgwriter statistics.',
 'Tune checkpoint settings and storage I/O.',
 'Restart database without diagnosis');

-- =========================================================
-- 3. Redis Cache Policy
-- =========================================================

CREATE TABLE redis_policy (
    id SERIAL PRIMARY KEY,
    cache_type VARCHAR(100),
    key_pattern VARCHAR(150),
    ttl_minutes INT,
    invalidation_method TEXT,
    forbidden_action TEXT
);

INSERT INTO redis_policy
(cache_type, key_pattern, ttl_minutes, invalidation_method, forbidden_action)
VALUES
('Product Detail', 'product:{id}', 60, 'Delete product key after product update', 'FLUSHDB'),
('Search Result', 'search:{query_hash}', 60, 'Delete affected search keys after catalog update', 'FLUSHDB'),
('Promotion', 'promo:{store_id}', 120, 'Delete promotion keys for affected store', 'FLUSHDB'),
('Inventory', 'inv:{store_id}:{product_id}', 5, 'Delete only affected inventory key after stock change', 'FLUSHDB');

-- =========================================================
-- 4. PostgreSQL Tuning Baseline
-- =========================================================

CREATE TABLE postgres_tuning_plan (
    id SERIAL PRIMARY KEY,
    parameter_name VARCHAR(100),
    current_value VARCHAR(100),
    recommended_value VARCHAR(100),
    reason TEXT
);

INSERT INTO postgres_tuning_plan
(parameter_name, current_value, recommended_value, reason)
VALUES
('shared_buffers', '128MB', '32GB', 'Server has 128GB RAM; current value is too low.'),
('effective_cache_size', '4GB', '96GB', 'Planner needs realistic cache estimate.'),
('work_mem', '4MB', '64MB', 'Sort and hash operations need more memory.'),
('maintenance_work_mem', 'default', '2GB', 'Required for vacuum and index maintenance.'),
('max_connections', '100', '200 with PgBouncer', 'Direct app connections must be controlled.'),
('checkpoint_completion_target', '0.5', '0.9', 'Smooth checkpoint writes.'),
('wal_level', 'minimal', 'replica', 'Required for WAL archiving and replication.'),
('archive_mode', 'off', 'on', 'Required for point-in-time recovery.'),
('max_parallel_workers_per_gather', '2', '8', 'Use available CPU cores.');

CREATE TABLE bloat_fix_plan (
    id SERIAL PRIMARY KEY,
    table_name VARCHAR(100),
    current_bloat TEXT,
    fix_steps TEXT,
    priority VARCHAR(20)
);

INSERT INTO bloat_fix_plan
(table_name, current_bloat, fix_steps, priority)
VALUES
('Products', '4.2x live row size', 'Enable autovacuum, VACUUM ANALYZE, then REINDEX during maintenance window.', 'Critical'),
('Orders', '3.8x live row size', 'Enable autovacuum, VACUUM ANALYZE, then REINDEX during maintenance window.', 'Critical'),
('OrderItems', '5.1x live row size', 'Enable autovacuum, VACUUM ANALYZE, then REINDEX during maintenance window.', 'Critical'),
('Customers', '2.4x live row size', 'Enable autovacuum, VACUUM ANALYZE, then REINDEX during maintenance window.', 'High');

-- =========================================================
-- 5. Connection Pool and PgBouncer
-- =========================================================

CREATE TABLE connection_pool_fix (
    id SERIAL PRIMARY KEY,
    current_app_servers INT,
    current_pool_per_server INT,
    current_possible_connections INT,
    db_max_connections INT,
    recommended_pool_per_server INT,
    recommended_total_connections INT,
    solution TEXT
);

INSERT INTO connection_pool_fix
(current_app_servers, current_pool_per_server, current_possible_connections, db_max_connections,
 recommended_pool_per_server, recommended_total_connections, solution)
VALUES
(15, 50, 750, 100, 5, 75, 'Deploy PgBouncer and reduce app-side pool size.');

CREATE TABLE pgbouncer_plan (
    id SERIAL PRIMARY KEY,
    setting_name VARCHAR(100),
    recommended_value VARCHAR(100),
    reason TEXT
);

INSERT INTO pgbouncer_plan
(setting_name, recommended_value, reason)
VALUES
('pool_mode', 'session', 'Transaction pooling is unsafe because the app uses named prepared statements and advisory locks.'),
('max_client_conn', '1000', 'Allow application clients to connect to PgBouncer.'),
('default_pool_size', '50', 'Limit backend database connections.'),
('reserve_pool_size', '20', 'Handle short spikes safely.'),
('server_reset_query', 'DISCARD ALL', 'Clean session state before reuse.');

-- =========================================================
-- 6. Change Management and RCA
-- =========================================================

CREATE TABLE change_log (
    id BIGSERIAL PRIMARY KEY,
    change_title TEXT NOT NULL,
    owner_name TEXT,
    risk_level VARCHAR(20),
    approval_status VARCHAR(50),
    rollback_plan TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO change_log
(change_title, owner_name, risk_level, approval_status, rollback_plan)
VALUES
('Deploy PgBouncer in session mode', 'DBA Lead', 'High', 'Pending', 'Switch connection string back to direct DB access.'),
('Enable WAL archiving', 'DBA Lead', 'Critical', 'Pending', 'Disable archive_mode only after confirming safe rollback.'),
('Re-enable autovacuum on major tables', 'DBA Lead', 'High', 'Approved', 'Tune thresholds if load increases.'),
('Remove FLUSHDB from Redis runbook', 'Platform Lead', 'Medium', 'Approved', 'Use selective key deletion instead.');

CREATE TABLE rca_register (
    id BIGSERIAL PRIMARY KEY,
    incident_name TEXT NOT NULL,
    immediate_cause TEXT,
    root_cause TEXT,
    corrective_action TEXT,
    owner_name TEXT,
    due_date DATE,
    status VARCHAR(50)
);

INSERT INTO rca_register
(incident_name, immediate_cause, root_cause, corrective_action, owner_name, due_date, status)
VALUES
('Connection exhaustion causing 503 errors',
 'Application pools exceeded database connection capacity.',
 'No connection pool governance.',
 'Deploy PgBouncer and reduce app pool size.',
 'SRE Lead',
 CURRENT_DATE + INTERVAL '7 days',
 'Open'),

('Autovacuum disabled and table bloat',
 'Autovacuum was turned off after a performance incident.',
 'No evidence-based RCA before changing configuration.',
 'Re-enable autovacuum and monitor bloat.',
 'DBA Lead',
 CURRENT_DATE + INTERVAL '10 days',
 'Open'),

('Redis overload after cache flush',
 'Full Redis cache was cleared.',
 'Runbook allowed unsafe FLUSHDB command.',
 'Replace FLUSHDB with selective invalidation.',
 'Platform Lead',
 CURRENT_DATE + INTERVAL '5 days',
 'Open');

-- =========================================================
-- 7. Backup, WAL and DR Evidence
-- =========================================================

CREATE TABLE wal_recovery_plan (
    id SERIAL PRIMARY KEY,
    item VARCHAR(100),
    current_state VARCHAR(100),
    required_state VARCHAR(150),
    purpose TEXT
);

INSERT INTO wal_recovery_plan
(item, current_state, required_state, purpose)
VALUES
('wal_level', 'minimal', 'replica', 'Enable replication and PITR.'),
('archive_mode', 'off', 'on', 'Enable WAL archiving.'),
('archive_command', 'not configured', 'copy WAL to secure archive location', 'Maintain WAL chain.'),
('restore_command', 'not configured', 'restore WAL from archive', 'Support point-in-time recovery.');

CREATE TABLE backup_validation (
    id BIGSERIAL PRIMARY KEY,
    backup_date DATE,
    backup_location TEXT,
    restore_test_passed BOOLEAN,
    tested_by TEXT,
    tested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    notes TEXT
);

INSERT INTO backup_validation
(backup_date, backup_location, restore_test_passed, tested_by, notes)
VALUES
(CURRENT_DATE, 'Islamabad NAS and offsite archive', TRUE, 'DR Lead', 'Restore validation evidence recorded.');

CREATE TABLE dr_drill_log (
    id BIGSERIAL PRIMARY KEY,
    drill_name TEXT,
    target_rto_minutes INT,
    actual_rto_minutes INT,
    target_rpo_minutes INT,
    actual_rpo_minutes INT,
    result VARCHAR(50),
    tested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO dr_drill_log
(drill_name, target_rto_minutes, actual_rto_minutes, target_rpo_minutes, actual_rpo_minutes, result)
VALUES
('PostgreSQL PITR Drill', 30, 25, 5, 3, 'Passed'),
('Cross Data Centre Recovery Drill', 30, NULL, 5, NULL, 'Scheduled');

-- =========================================================
-- 8. Monitoring and Alert Ownership
-- =========================================================

CREATE TABLE monitoring_plan (
    id SERIAL PRIMARY KEY,
    metric_name VARCHAR(150),
    source_name VARCHAR(100),
    why_needed TEXT,
    alert_condition TEXT,
    owner_name VARCHAR(100)
);

INSERT INTO monitoring_plan
(metric_name, source_name, why_needed, alert_condition, owner_name)
VALUES
('Active DB Connections', 'pg_stat_activity', 'Detect connection exhaustion.', 'Above 80% of max_connections.', 'DBA Lead'),
('PgBouncer Waiting Clients', 'PgBouncer stats', 'Detect pool saturation.', 'Waiting clients for more than 5 minutes.', 'SRE Lead'),
('Query p95 Latency', 'pg_stat_statements', 'Detect slow queries.', 'p95 latency above SLA.', 'DBA Lead'),
('Deadlocks', 'pg_stat_database', 'Detect deadlock storms.', 'Deadlocks above threshold.', 'Engineering Lead'),
('Dead Tuples', 'pg_stat_user_tables', 'Detect bloat.', 'Dead tuple ratio too high.', 'DBA Lead'),
('Last Autovacuum', 'pg_stat_user_tables', 'Detect vacuum starvation.', 'No autovacuum in expected window.', 'DBA Lead'),
('Checkpoint Duration', 'pg_stat_bgwriter', 'Detect checkpoint spikes.', 'Checkpoint duration above threshold.', 'DBA Lead'),
('WAL Archive Lag', 'WAL archive monitor', 'Protect PITR.', 'Archive lag above 5 minutes.', 'DR Lead'),
('Backup Restore Status', 'Backup validation job', 'Verify recoverability.', 'Restore test failed.', 'DR Lead'),
('Disk I/O Latency', 'Node exporter', 'Detect storage bottleneck.', 'Latency above threshold.', 'Infrastructure Lead'),
('Redis Inventory Key TTL', 'Redis scanner', 'Detect permanent inventory cache.', 'Inventory key has no TTL.', 'Platform Lead');

CREATE TABLE alert_owners (
    id SERIAL PRIMARY KEY,
    alert_name TEXT,
    primary_owner TEXT,
    backup_owner TEXT,
    escalation_minutes INT
);

INSERT INTO alert_owners
(alert_name, primary_owner, backup_owner, escalation_minutes)
VALUES
('High DB Connections', 'DBA Lead', 'SRE Lead', 10),
('Redis Cache Error', 'Platform Lead', 'SRE Lead', 15),
('Backup Restore Failure', 'DR Lead', 'DBA Lead', 5),
('Deadlock Storm', 'Engineering Lead', 'DBA Lead', 10),
('WAL Archive Failure', 'DBA Lead', 'DR Lead', 5);

-- =========================================================
-- 9. Training and Review Schedule
-- =========================================================

CREATE TABLE training_plan (
    id SERIAL PRIMARY KEY,
    topic TEXT,
    team_name TEXT,
    required_by DATE,
    status VARCHAR(50)
);

INSERT INTO training_plan
(topic, team_name, required_by, status)
VALUES
('PostgreSQL Autovacuum and MVCC', 'DBA and Engineering', CURRENT_DATE + INTERVAL '30 days', 'Planned'),
('PgBouncer Session vs Transaction Pooling', 'DBA and SRE', CURRENT_DATE + INTERVAL '14 days', 'Planned'),
('Incident Response and RCA', 'Operations', CURRENT_DATE + INTERVAL '21 days', 'Planned'),
('Backup Restore and PITR', 'DBA and DR Team', CURRENT_DATE + INTERVAL '21 days', 'Planned'),
('Redis Safe Cache Invalidation', 'Platform and Operations', CURRENT_DATE + INTERVAL '14 days', 'Planned');

CREATE TABLE operations_review (
    id SERIAL PRIMARY KEY,
    review_name TEXT,
    frequency TEXT,
    owner_name TEXT,
    next_review_date DATE,
    agenda TEXT
);

INSERT INTO operations_review
(review_name, frequency, owner_name, next_review_date, agenda)
VALUES
('Database Operations Review', 'Monthly', 'DBA Lead', CURRENT_DATE + INTERVAL '30 days',
 'Review slow queries, bloat, vacuum, connections, WAL and incidents.'),
('Runbook Review', 'Monthly', 'SRE Lead', CURRENT_DATE + INTERVAL '30 days',
 'Update runbooks based on incidents and lessons learned.'),
('Disaster Recovery Review', 'Quarterly', 'DR Lead', CURRENT_DATE + INTERVAL '90 days',
 'Review restore drills, backup validation and RTO/RPO evidence.');

-- =========================================================
-- 10. Final Report Views
-- =========================================================

CREATE VIEW part11_problem_solution_report AS
SELECT
    id,
    area,
    problem,
    evidence,
    impact,
    solution,
    priority
FROM problem_register
ORDER BY
CASE priority
    WHEN 'Critical' THEN 1
    WHEN 'High' THEN 2
    WHEN 'Medium' THEN 3
    ELSE 4
END,
id;

CREATE VIEW part11_summary AS
SELECT 'Total Problems Identified' AS item, COUNT(*)::TEXT AS value
FROM problem_register
UNION ALL
SELECT 'Critical Problems', COUNT(*)::TEXT
FROM problem_register WHERE priority = 'Critical'
UNION ALL
SELECT 'High Problems', COUNT(*)::TEXT
FROM problem_register WHERE priority = 'High'
UNION ALL
SELECT 'Runbooks Created', COUNT(*)::TEXT
FROM runbooks
UNION ALL
SELECT 'Diagnostic Procedures Created', COUNT(*)::TEXT
FROM diagnostic_steps
UNION ALL
SELECT 'Monitoring Metrics Defined', COUNT(*)::TEXT
FROM monitoring_plan
UNION ALL
SELECT 'RCA Records Created', COUNT(*)::TEXT
FROM rca_register
UNION ALL
SELECT 'Backup Validation Records', COUNT(*)::TEXT
FROM backup_validation
UNION ALL
SELECT 'DR Drill Records', COUNT(*)::TEXT
FROM dr_drill_log;

CREATE VIEW part11_priority_actions AS
SELECT 1 AS priority_no, 'Deploy PgBouncer in session mode and reduce application pool size.' AS action
UNION ALL SELECT 2, 'Enable WAL archiving and point-in-time recovery.'
UNION ALL SELECT 3, 'Start backup validation and DR drills.'
UNION ALL SELECT 4, 'Re-enable autovacuum and clean table bloat.'
UNION ALL SELECT 5, 'Replace generic runbook with diagnostic runbooks.'
UNION ALL SELECT 6, 'Remove FLUSHDB from normal Redis operations.'
UNION ALL SELECT 7, 'Deploy monitoring for DB, Redis, WAL, backups, locks and I/O.'
UNION ALL SELECT 8, 'Introduce RCA and change management process.'
UNION ALL SELECT 9, 'Train operations team on PostgreSQL, PgBouncer and DR.';

-- =========================================================
-- Final Output
-- =========================================================

SELECT * FROM part11_summary;
SELECT * FROM part11_problem_solution_report;
SELECT * FROM part11_priority_actions;
SELECT * FROM postgres_tuning_plan;
SELECT * FROM connection_pool_fix;
SELECT * FROM pgbouncer_plan;
SELECT * FROM wal_recovery_plan;
SELECT * FROM backup_validation;
SELECT * FROM dr_drill_log;