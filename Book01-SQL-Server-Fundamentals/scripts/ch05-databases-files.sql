-- =============================================================================
-- Chapter 5 — Databases, Files, and Storage
-- SQL Server Fundamentals | SQL Server Mastery Series
-- Author: Taryuni
-- =============================================================================
-- Run these queries in SSMS while reading Chapter 5.
-- Some queries require an existing database to be in context.
-- =============================================================================

-- ─── Create a practice database with explicit file placement ─────────────────
-- Adapt the paths to match your SQL Server data and log directories.
-- The DEV subfolder naming convention mirrors the SQLDEV instance name.
CREATE DATABASE PracticeDB
ON PRIMARY (
    NAME = 'PracticeDB',
    FILENAME = 'E:\DEV\DATA\PracticeDB.mdf',
    SIZE = 8MB,
    FILEGROWTH = 64MB
)
LOG ON (
    NAME = 'PracticeDB_log',
    FILENAME = 'L:\DEV\LOG\PracticeDB_log.ldf',
    SIZE = 8MB,
    FILEGROWTH = 64MB
);
GO

-- ─── View database configuration and file details ────────────────────────────
-- Returns size, status, and file paths for every database on the instance
-- when called with no argument. Pass a database name to scope to one database.
EXEC sp_helpdb;
EXEC sp_helpdb 'TarLogistics';

-- ─── Check space usage ───────────────────────────────────────────────────────
-- Run from within the database context you want to measure.
USE TarLogistics;
GO
EXEC sp_spaceused;

-- ─── Query file sizes directly from the system catalog ───────────────────────
-- size is stored in 8KB pages; dividing by 128 converts to MB.
-- growth > 0 means autogrowth is configured; 0 means fixed size.
USE TarLogistics;
GO
SELECT
    name,
    size / 128.0 AS SizeInMB,
    growth
FROM sys.database_files;
