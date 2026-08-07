-- =============================================================================
-- Chapter 10 — Routine Maintenance: The DBA's Weekly Work
-- SQL Server Fundamentals | SQL Server Mastery Series
-- Author: Taryuni
-- =============================================================================
-- Run these queries in SSMS while reading Chapter 10.
-- Index maintenance and DBCC CHECKDB are resource-intensive — run them during
-- a low-traffic maintenance window, not during peak business hours.
-- The RESTORE VERIFYONLY example assumes you have a .bak file to test against.
-- =============================================================================

-- ─── Check index fragmentation ───────────────────────────────────────────────
-- sys.dm_db_index_physical_stats returns fragmentation data per index.
-- avg_fragmentation_in_percent is the key metric:
--   < 5%   — no action needed
--   5–30%  — REORGANIZE (online, low locking, incremental progress)
--   > 30%  — REBUILD (heavier, resets statistics, can be done online in Enterprise)
-- page_count < ~1000: skip reorganize/rebuild — the overhead isn't worth it.
SELECT
    OBJECT_NAME(i.object_id)  AS table_name,
    i.name                    AS index_name,
    ips.index_type_desc,
    ips.avg_fragmentation_in_percent,
    ips.page_count
FROM sys.dm_db_index_physical_stats(
    DB_ID(),    -- current database
    NULL,       -- all tables
    NULL,       -- all indexes
    NULL,       -- all partitions
    'LIMITED'   -- LIMITED mode is fast; SAMPLED or DETAILED for more accuracy
) ips
JOIN sys.indexes i
    ON i.object_id = ips.object_id
    AND i.index_id = ips.index_id
WHERE ips.page_count > 100
ORDER BY ips.avg_fragmentation_in_percent DESC;

-- ─── Reorganize a fragmented index (5–30%) ───────────────────────────────────
-- REORGANIZE defragments the leaf level of the index without a full lock.
-- It can be interrupted and restarted. Best for low-to-moderate fragmentation.
ALTER INDEX IX_Shipments_TrackingNumber ON dbo.Shipments REORGANIZE;

-- ─── Rebuild a heavily fragmented index (> 30%) ──────────────────────────────
-- REBUILD drops and recreates the index. In Standard Edition it takes the table
-- offline briefly. In Enterprise Edition, ONLINE = ON keeps the table accessible.
-- REBUILD also updates statistics automatically.
ALTER INDEX IX_Shipments_TrackingNumber ON dbo.Shipments
    REBUILD WITH (ONLINE = OFF);  -- change to ONLINE = ON if Enterprise Edition

-- ─── Check statistics freshness ──────────────────────────────────────────────
-- The query optimizer uses statistics to estimate row counts and choose plans.
-- Stale statistics lead to bad plans — wrong index choice, wrong join order,
-- over- or under-allocation of memory grants.
-- stats_date() returns when statistics were last updated.
SELECT
    OBJECT_NAME(s.object_id) AS table_name,
    s.name                   AS stats_name,
    STATS_DATE(s.object_id, s.stats_id) AS last_updated,
    s.auto_created,
    s.user_created
FROM sys.stats s
WHERE OBJECT_NAME(s.object_id) = 'Shipments'
ORDER BY last_updated ASC;

-- ─── Update all statistics in a database ─────────────────────────────────────
-- sp_updatestats only updates statistics that have changed since they were
-- last updated — it's fast and safe to run regularly.
-- For a full update (all stats, regardless of change), use
-- UPDATE STATISTICS <table> WITH FULLSCAN on specific tables instead.
USE TarLogistics;
GO
EXEC sp_updatestats;

-- ─── Run DBCC CHECKDB ────────────────────────────────────────────────────────
-- CHECKDB verifies the structural integrity of every page in the database.
-- It is the most comprehensive consistency check available.
-- On a large database this can take hours — schedule it weekly during a
-- maintenance window. A clean run returns no errors and ends with
-- "DBCC execution completed. If DBCC printed error messages,
--  contact your system administrator."
DBCC CHECKDB ('TarLogistics');

-- Physical-only mode — faster, checks page headers and record structures
-- but does not verify logical consistency (e.g., index key order).
-- Useful for very large databases where a full CHECKDB takes too long.
DBCC CHECKDB ('TarLogistics') WITH PHYSICAL_ONLY;

-- ─── Verify a backup file ─────────────────────────────────────────────────────
-- RESTORE VERIFYONLY reads the backup file and confirms that SQL Server can
-- read all backup sets. It does NOT restore data — it only validates the file.
-- Run this after every backup to confirm the file is readable.
-- Adapt the path to match where your backup file is stored.
RESTORE VERIFYONLY
FROM DISK = 'E:\DEV\BACKUP\TarLogistics_Full.bak';
