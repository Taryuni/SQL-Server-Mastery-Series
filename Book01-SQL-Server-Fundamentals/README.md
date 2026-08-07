# Book 1: SQL Server Fundamentals

**SQL Server Mastery Series** | by Taryuni | Published by Bitotol

<table>
<tr>
<td width="300" valign="top">
  <img src="front-cover.png" alt="SQL Server Fundamentals — Book 1 of the SQL Server Mastery Series by Taryuni" width="280">
</td>
<td valign="top">

## What This Book Is

*SQL Server Fundamentals* is a career transition guide for IT professionals — systems administrators, infrastructure engineers, and anyone who already works with servers and Windows environments — who have decided to move into SQL Server database administration.

Most SQL Server books are written for one of two audiences: developers who already know the database side, or complete beginners who've never touched a server. Neither was written for the IT professional who already manages Windows Server, Active Directory, and real infrastructure, and who is making a deliberate, strategic move into the DBA role.

This book was.

It builds directly on what you already know. It does not re-teach what you've spent years learning. It takes you, without detour or padding, into how SQL Server actually works, what a DBA actually does, and how to do the job with real competence.

</td>
</tr>
</table>

---

## What You'll Be Able to Do When You Finish

- Install and configure SQL Server 2022 with every decision understood — not inherited from a wizard's defaults
- Explain how SQL Server works beneath the surface: the engine, the transaction log, the buffer pool, and how a query moves through the system
- Create and manage databases with every storage decision made on purpose
- Control who has access to what, and audit it — understanding why the wrong answer is dangerous
- Write the T-SQL a DBA actually reaches for: DMVs, system stored procedures, blocking investigations, wait stats
- Read the error log and run a real health check before users report problems
- Execute a complete weekly maintenance routine: fragmentation, statistics, integrity checks

---

## Who This Book Is For

You are a systems administrator or IT professional with a few years in the field. You manage servers, troubleshoot problems, and are trusted with real infrastructure. You have seen a SELECT query. You are not a developer. You are not a beginner.

You have watched the DBA at your company become the person everyone calls when something breaks — the person whose vacation makes the whole office nervous. You have decided that's where you're going.

You have tried Microsoft documentation (it tells you what, never why), YouTube tutorials (they show you which buttons to click without explaining what you're doing), and possibly one SQL Server book that read like a university textbook. None of it was written for you.

This one is.

---

## What This Book Does Not Cover

These topics have their own books in the series — they are not gaps, they are deliberate boundaries:

- T-SQL programming in depth → Book 6
- Query optimization and execution plans → Book 2
- Backup and recovery strategy → Book 3
- High availability and disaster recovery → Book 4
- Database security in depth → Book 5
- Automation and scripting → Book 8
- Azure SQL and cloud migration → Book 9

---

## Chapters

| # | Title | What Happens |
|---|-------|-------------|
| Intro | This Book Is Not What You Think | Who this is for, what it covers, how to use it, and why you need a practice environment before Chapter 3 |
| 1 | What a DBA Actually Does | The real day-to-day — not a job description, but what the role actually involves in a real organization |
| 2 | How SQL Server Works: The Mental Model | The engine, the buffer pool, the transaction log, and how a query moves through the system — the model that makes everything else make sense |
| 3 | Installing SQL Server 2022 | Every installation decision explained: instance name, collation, authentication mode, data directories, service accounts |
| 4 | SSMS: The DBA's Workshop | Object Explorer, the query editor, Activity Monitor, essential shortcuts, and the queries you'll run every time you open SSMS |
| 5 | Databases, Files, and Storage | What a database actually is on disk, why data and log files are separated, TempDB, filegroups, and the storage mistakes that slow servers down |
| 6 | SQL Server Services: What's Running Under the Hood | The Database Engine, SQL Server Agent, Browser, and what happens when one of them stops — including how a stopped Agent takes down an entire application without an obvious error |
| 7 | Logins, Users, and Permissions | The two-layer security model, the sa account, fixed server and database roles, the principle of least privilege, and how to audit who has access to what |
| 8 | T-SQL for DBAs (Not Developers) | DMVs, sp_who2, sp_configure, blocking session queries, wait stats — not a SQL course, but the specific queries a DBA reaches for every day |
| 9 | Monitoring: Knowing What's Normal | The SQL Server error log, Page Life Expectancy, the system_health session, SQL Server Agent alerts, and the seven-step morning health check |
| 10 | Routine Maintenance: The DBA's Weekly Work | Index fragmentation, REBUILD vs. REORGANIZE, statistics, DBCC CHECKDB, and the Ola Hallengren Maintenance Solution — the industry standard, set up and scheduled |
| Conclusion | Where You Go From Here | What you can do now, what's still ahead, next steps before applying for a junior DBA role, and where Book 2 picks up |

---

## Practice Database

This book uses **TarLogistics** — a realistic North American logistics company database with 21 tables, 10,000 shipments, ~22,000 packages, and ~80,000 tracking events across 14 facilities in the US and Canada.

Set it up before starting Chapter 4. It is the environment every hands-on exercise from Chapter 4 onward runs against.

Full setup instructions: [TarLogistics README](../TarLogistics/README.md)

---

## Chapter Scripts

Each chapter from 4 onward has a companion SQL script in the `scripts/` folder. Open these in SSMS alongside the chapter — they are meant to be read and understood as you go, not executed in bulk.

| Script | Chapter | What's in It |
|--------|---------|--------------|
| `ch04-ssms-queries.sql` | Chapter 4 | Object Explorer navigation queries, sp_who2, @@VERSION, @@SERVERNAME, Activity Monitor equivalents |
| `ch05-databases-files.sql` | Chapter 5 | CREATE DATABASE with deliberate storage options, sp_helpdb, file size and growth queries |
| `ch06-services.sql` | Chapter 6 | Service status queries, SQL Server Configuration Manager reference, Agent job history checks |
| `ch07-logins-users-permissions.sql` | Chapter 7 | Creating logins and users, role assignments, auditing access — including who has sysadmin and who has access to what database |
| `ch08-tsql-for-dbas.sql` | Chapter 8 | sys.dm_exec_sessions, sys.dm_exec_requests, blocking session investigation, wait stats, sp_configure |
| `ch09-monitoring.sql` | Chapter 9 | Error log queries, Page Life Expectancy, long-running query detection, deadlock history from system_health, the morning health check |
| `ch10-routine-maintenance.sql` | Chapter 10 | Index fragmentation queries, REBUILD/REORGANIZE decisions, statistics update checks, DBCC CHECKDB, Ola Hallengren job setup |

---

## Practice Environment

The book uses a specific environment. If yours differs, the concepts transfer — adapt the paths and instance names accordingly.

| Setting | Value Used in the Book |
|---------|------------------------|
| Instance name | `TAR\SQLDEV` (machine: TAR, named instance: SQLDEV) |
| Data files | `E:\DEV\DATA\` |
| Log files | `L:\DEV\LOG\` |
| Backup files | `B:\DEV\BACKUP\` |
| SQL Server version | SQL Server 2022 Developer Edition |
| SSMS version | 19 or later |
| Minimum RAM | 4 GB (8 GB recommended) |

SQL Server Developer Edition is free, fully featured, and the right choice for a practice environment. Chapter 3 walks through downloading and installing it.

---

## Requirements

- Windows machine or VM (physical or virtual — both work)
- SQL Server 2022 Developer Edition (free from Microsoft)
- SQL Server Management Studio (SSMS) 19 or later (free from Microsoft)
- SQLCMD (included with SQL Server tools — required for TarLogistics seed data only)
- At least 4 GB RAM available to the instance (8 GB recommended)

---

## Frequently Asked Questions

**Do I need to know SQL before reading this?**
You should have seen a SELECT statement before — basic enough to read one, even if you've never written one yourself. This book is not a SQL tutorial, but it is not a reference for people who already know SQL Server either.

**Do I need to buy a SQL Server license?**
No. SQL Server Developer Edition is free and fully functional for learning and development. Chapter 3 covers the download and installation at no cost.

**Will this help me pass the DP-300?**
It is a strong foundation. The DP-300 tests many of the same fundamentals — installation, storage, security, monitoring, maintenance. It does not replace certification-specific study materials, and some DP-300 topics (particularly Azure SQL) are outside this book's scope.

**How long does it take to read?**
Around 28,000–32,000 words. At 45 minutes to an hour per evening, most readers finish in two to three weeks. It is designed to be read linearly, with the practice environment running alongside.

---

## Series Navigation

← [Series Overview](../README.md) | Next: [Book 2 — Performance Tuning](../book02-performance-tuning/README.md) →
