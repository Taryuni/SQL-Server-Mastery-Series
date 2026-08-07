-- =============================================================================
-- Chapter 7 — Logins, Users, and Permissions
-- SQL Server Fundamentals | SQL Server Mastery Series
-- Author: Taryuni
-- =============================================================================
-- Run these queries in SSMS while reading Chapter 7.
-- Connect to your SQLDEV instance as a sysadmin before running.
-- Some statements modify server and database security — read the chapter
-- notes before executing anything in a shared environment.
-- =============================================================================

-- ─── Create a SQL Server login ───────────────────────────────────────────────
-- A login lives at the server level. It cannot access any database yet.
-- Always use a strong, unique passphrase in a real environment.
CREATE LOGIN MBenali
    WITH PASSWORD = 'Str0ng&UniqueP@ssphrase!';

-- ─── Create a database user mapped to that login ─────────────────────────────
-- The user lives inside a specific database. Without this, the login exists
-- but cannot touch TarLogistics.
USE TarLogistics;
GO
CREATE USER MBenali FOR LOGIN MBenali;

-- ─── Grant read access via a built-in role ───────────────────────────────────
-- db_datareader allows SELECT on all current and future tables in the database.
-- It does not allow INSERT, UPDATE, DELETE, or schema changes.
ALTER ROLE db_datareader ADD MEMBER MBenali;

-- ─── Audit: server-level role memberships ────────────────────────────────────
-- Use this to see which logins belong to sysadmin, securityadmin, etc.
-- A non-zero result for a login under sysadmin is worth investigating.
SELECT
    sp.name       AS LoginName,
    r.name        AS ServerRole
FROM sys.server_principals sp
JOIN sys.server_role_members rm
    ON sp.principal_id = rm.member_principal_id
JOIN sys.server_principals r
    ON rm.role_principal_id = r.principal_id
WHERE sp.type IN ('S', 'U');  -- S = SQL login, U = Windows login

-- ─── Audit: database-level role memberships ──────────────────────────────────
-- Run this from within the database you want to inspect (USE TarLogistics first).
-- Shows which database users belong to db_owner, db_datareader, etc.
USE TarLogistics;
GO
SELECT
    dp.name   AS UserName,
    r.name    AS DatabaseRole
FROM sys.database_principals dp
JOIN sys.database_role_members rm
    ON dp.principal_id = rm.member_principal_id
JOIN sys.database_principals r
    ON rm.role_principal_id = r.principal_id
WHERE dp.type IN ('S', 'U');  -- S = SQL user, U = Windows user
