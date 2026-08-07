-- =============================================================================
-- Chapter 9 — Monitoring: Knowing What's Normal
-- SQL Server Fundamentals | SQL Server Mastery Series
-- Author: Taryuni
-- =============================================================================
-- Run these queries in SSMS while reading Chapter 9.
-- The Alert and Operator setup requires SQL Server Agent to be running.
-- The system_health query reads from the default extended events session
-- that SQL Server starts automatically — no setup required.
-- =============================================================================

-- ─── Read the SQL Server error log ───────────────────────────────────────────
-- xp_readerrorlog is the fastest way to scan error logs from T-SQL.
-- Parameters: log number (0 = current), log type (1 = SQL, 2 = Agent),
-- search string 1, search string 2, start date, end date, sort order.
-- This example pulls everything from the current log:
EXEC xp_readerrorlog 0, 1;

-- Filter to login failures only (useful for security audits):
EXEC xp_readerrorlog 0, 1, 'Login failed';

-- ─── Create a SQL Server Agent alert ─────────────────────────────────────────
-- Severity 19 and above cover fatal errors that affect all processes.
-- Severity 25 is the most severe — the SQL Server process itself has a problem.
-- The alert fires and notifies an operator whenever that severity appears in the log.
EXEC msdb.dbo.sp_add_alert
    @name         = N'Sev 19+ Fatal Error',
    @severity     = 19,
    @enabled      = 1,
    @delay_between_responses = 300,  -- seconds; prevents alert storms
    @include_event_description_in = 1;

-- ─── Create an operator to receive notifications ──────────────────────────────
EXEC msdb.dbo.sp_add_operator
    @name           = N'DBA On-Call',
    @enabled        = 1,
    @email_address  = N'dba-oncall@tarlogistics.com';

-- ─── Wire the alert to the operator ──────────────────────────────────────────
-- @notification_method: 1 = email, 2 = pager, 4 = net send (bitmask, additive)
EXEC msdb.dbo.sp_add_notification
    @alert_name     = N'Sev 19+ Fatal Error',
    @operator_name  = N'DBA On-Call',
    @notification_method = 1;

-- ─── Page Life Expectancy (PLE) ──────────────────────────────────────────────
-- PLE measures how long (in seconds) a data page stays in the buffer pool
-- before being evicted. A healthy PLE on a well-tuned server is typically
-- 300 seconds or higher. A sudden drop in PLE signals memory pressure.
SELECT
    object_name,
    counter_name,
    instance_name,
    cntr_value  AS ple_seconds
FROM sys.dm_os_performance_counters
WHERE counter_name = 'Page life expectancy'
  AND object_name  LIKE '%Buffer Manager%';

-- ─── Scheduler utilization — CPU pressure indicator ─────────────────────────
-- Each CPU core gets one scheduler. If runnable_tasks_count is consistently
-- above 1-2 per scheduler, you have a CPU bottleneck — processes are queued
-- waiting for CPU time. pending_disk_io_count > 0 means I/O backpressure
-- is affecting scheduling.
SELECT
    scheduler_id,
    cpu_id,
    is_online,
    current_tasks_count,
    runnable_tasks_count,
    current_workers_count,
    active_workers_count,
    pending_disk_io_count
FROM sys.dm_os_schedulers
WHERE scheduler_id < 255;  -- filter out hidden system schedulers

-- ─── Extract deadlock graphs from the system_health session ─────────────────
-- SQL Server records the last ~100 deadlock graphs automatically in the
-- ring_buffer target of the system_health extended events session.
-- This query extracts the raw XML so you can open it in SSMS Deadlock Graph view.
SELECT
    xdr.value('@timestamp', 'datetime2') AS deadlock_time,
    xdr.query('.')                        AS deadlock_graph
FROM (
    SELECT CAST(target_data AS XML) AS target_data
    FROM sys.dm_xe_session_targets t
    JOIN sys.dm_xe_sessions s ON s.address = t.event_session_address
    WHERE s.name = 'system_health'
      AND t.target_name = 'ring_buffer'
) AS data
CROSS APPLY target_data.nodes('//RingBufferTarget/event[@name="xml_deadlock_report"]') AS XEventData(xdr);

-- ─── Long-running queries ────────────────────────────────────────────────────
-- Queries running longer than 30 seconds. In a well-tuned OLTP environment,
-- most queries complete in milliseconds. Anything over a few seconds warrants
-- investigation — check the execution plan and look for missing indexes,
-- parameter sniffing, or blocking.
SELECT
    r.session_id,
    r.status,
    r.total_elapsed_time / 1000.0 AS elapsed_seconds,
    r.cpu_time / 1000.0           AS cpu_seconds,
    r.logical_reads,
    r.wait_type,
    t.text                        AS sql_text
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.total_elapsed_time > 30000  -- 30,000 ms = 30 seconds
ORDER BY r.total_elapsed_time DESC;
