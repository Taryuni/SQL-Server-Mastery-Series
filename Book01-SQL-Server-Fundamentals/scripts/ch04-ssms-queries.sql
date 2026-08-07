-- =============================================================================
-- Chapter 4 — SSMS: The DBA's Workshop
-- SQL Server Fundamentals | SQL Server Mastery Series
-- Author: Taryuni
-- =============================================================================
-- Run these queries in SSMS while reading Chapter 4.
-- Connect to your SQLDEV instance before running anything.
-- =============================================================================

-- ─── Confirm your SQL Server version ────────────────────────────────────────
-- Tells you exactly which build is running on this instance.
SELECT @@VERSION;

-- ─── Confirm the instance name ───────────────────────────────────────────────
-- Should return TAR\SQLDEV (or your machine name\SQLDEV).
SELECT @@SERVERNAME;

-- ─── View all active sessions ────────────────────────────────────────────────
-- The classic DBA quick-check: who's connected, what they're doing,
-- and whether anything is blocked. A non-zero BlkBy value means trouble.
EXEC sp_who2;
