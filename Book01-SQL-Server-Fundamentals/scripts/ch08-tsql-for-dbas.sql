-- =============================================================================
-- Chapter 8 — T-SQL for DBAs: Not a Developer's Chapter
-- SQL Server Fundamentals | SQL Server Mastery Series
-- Author: Taryuni
-- =============================================================================
-- Run these queries in SSMS while reading Chapter 8.
-- Some queries require the TarLogistics database. Others run against system
-- DMVs and work on any database in context.
-- =============================================================================

-- ─── Opening scenario: a blocking investigation ───────────────────────────────
-- This is the kind of query a DBA reaches for when someone reports the
-- application is hanging. It shows active requests, their wait types, and
-- which session is blocked by which other session.
SELECT
    r.session_id,
    r.status,
    r.wait_type,
    r.wait_time / 1000.0          AS wait_seconds,
    r.blocking_session_id,
    r.cpu_time,
    r.total_elapsed_time / 1000.0 AS elapsed_seconds,
    t.text                        AS sql_text
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.session_id > 50;  -- filter out system sessions

-- ─── Read and change instance-level configuration ────────────────────────────
-- sp_configure shows the current and running values for every configuration
-- option. 'show advanced options' must be 1 to see all of them.
EXEC sp_configure;
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'max server memory (MB)', 8192;
RECONFIGURE;

-- ─── Join sessions to active requests ────────────────────────────────────────
-- sys.dm_exec_sessions has one row per connected session.
-- sys.dm_exec_requests has one row per currently running request (not idle sessions).
-- Joining them gives a complete picture: who is connected, what they're running,
-- how long they've been waiting, and who is blocking them.
SELECT
    s.session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    r.status,
    r.wait_type,
    r.blocking_session_id,
    r.cpu_time,
    r.total_elapsed_time / 1000.0 AS elapsed_seconds
FROM sys.dm_exec_sessions s
LEFT JOIN sys.dm_exec_requests r
    ON s.session_id = r.session_id
WHERE s.is_user_process = 1;

-- ─── Check all database statuses ─────────────────────────────────────────────
-- A database that is not ONLINE cannot be accessed by users.
-- Common non-ONLINE states: RESTORING (during restore), RECOVERY_PENDING
-- (engine crashed mid-recovery), SUSPECT (corruption detected).
SELECT
    name,
    state_desc,
    recovery_model_desc,
    log_reuse_wait_desc
FROM sys.databases;

-- ─── Wait statistics — understanding where the instance is spending time ──────
-- sys.dm_os_wait_stats accumulates since the last restart (or last DBCC SQLPERF).
-- PAGEIOLATCH_* = waiting to read/write pages from disk — I/O pressure.
-- LCK_M_*       = lock waits — contention between sessions.
-- CXPACKET      = parallel query waits — may indicate too much parallelism.
-- SOS_SCHEDULER_YIELD = CPU pressure.
SELECT TOP 20
    wait_type,
    waiting_tasks_count,
    wait_time_ms / 1000.0           AS total_wait_seconds,
    max_wait_time_ms / 1000.0       AS max_wait_seconds,
    (wait_time_ms - signal_wait_time_ms) / 1000.0 AS resource_wait_seconds
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN (
    -- filter out benign idle waits that inflate the numbers
    'SLEEP_TASK','BROKER_TO_FLUSH','BROKER_TASK_STOP','CLR_AUTO_EVENT',
    'DISPATCHER_QUEUE_SEMAPHORE','FT_IFTS_SCHEDULER_IDLE_WAIT',
    'HADR_WORK_QUEUE','LAZYWRITER_SLEEP','LOGMGR_QUEUE',
    'REQUEST_FOR_DEADLOCK_SEARCH','RESOURCE_QUEUE','SERVER_IDLE_CHECK',
    'SLEEP_DBSTARTUP','SLEEP_DBRECOVER','SLEEP_MASTERDBREADY',
    'SLEEP_MASTERMDREADY','SLEEP_MASTERUPGRADED','SLEEP_MSDBSTARTUP',
    'SLEEP_SYSTEMTASK','SLEEP_TEMPDBSTARTUP','SNI_HTTP_ACCEPT',
    'SP_SERVER_DIAGNOSTICS_SLEEP','SQLTRACE_BUFFER_FLUSH','WAITFOR',
    'XE_DISPATCHER_WAIT','XE_TIMER_EVENT','SQLTRACE_INCREMENTAL_FLUSH_SLEEP'
)
ORDER BY wait_time_ms DESC;

-- ─── Find blocking sessions ───────────────────────────────────────────────────
-- A blocking chain: session A holds a lock, session B waits for it.
-- The head blocker (blocking_session_id = 0 or NULL) is the root cause.
-- CROSS APPLY unpacks the SQL text for both the blocked and blocking session.
SELECT
    blocked.session_id                AS blocked_session,
    blocking.session_id               AS blocking_session,
    blocked_text.text                 AS blocked_sql,
    blocking_text.text                AS blocking_sql,
    blocked_req.wait_type,
    blocked_req.wait_time / 1000.0    AS wait_seconds
FROM sys.dm_exec_requests blocked_req
JOIN sys.dm_exec_sessions blocked
    ON blocked_req.session_id = blocked.session_id
JOIN sys.dm_exec_sessions blocking
    ON blocked_req.blocking_session_id = blocking.session_id
CROSS APPLY sys.dm_exec_sql_text(blocked_req.sql_handle) blocked_text
CROSS APPLY sys.dm_exec_sql_text(blocking.most_recent_sql_handle) blocking_text
WHERE blocked_req.blocking_session_id > 0;

-- ─── SQL Server Agent job history ────────────────────────────────────────────
-- msdb is the system database that stores Agent metadata.
-- This query surfaces the last run result for every job: 1 = succeeded, 0 = failed.
-- Sort by last_run_date DESC to surface recently failed jobs quickly.
SELECT
    j.name                    AS job_name,
    jh.run_date,
    jh.run_time,
    jh.run_duration,
    CASE jh.run_status
        WHEN 1 THEN 'Succeeded'
        WHEN 0 THEN 'Failed'
        WHEN 3 THEN 'Cancelled'
        ELSE 'Other'
    END                       AS run_status,
    jh.message
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobhistory jh
    ON j.job_id = jh.job_id
WHERE jh.step_id = 0  -- step_id 0 = the overall job outcome, not individual steps
ORDER BY jh.run_date DESC, jh.run_time DESC;
