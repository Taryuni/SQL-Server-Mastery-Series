# TarLogistics Practice Database

TarLogistics is a fictional North American parcel and freight company used as the practice database throughout the entire SQL Server Mastery Series. It is not a toy schema built for a single exercise — it is a 21-table operational database designed to support realistic DBA work across all ten books, from basic installation through performance tuning, backup and recovery, security, automation, and cloud migration.

You set it up once. You keep working with it through every book.

---

## The Company

**TarLogistics** is a parcel and LTL freight courier operating across the United States and Canada.

| Detail | Value |
|--------|-------|
| Headquarters | Columbus, OH (geographically central — deliberate) |
| Canadian Gateway Hub | Toronto, ON |
| Regional Hub | Montréal, QC |
| Service tiers | Ground, Express, Freight/LTL |
| Customer types | Retail (individual shippers) and Business accounts (corporate, negotiated rates) |
| Cross-border scope | US–Canada shipments include customs and duties fields |

The business context is intentional. A logistics company generates the exact mix of data patterns a DBA needs to practice against: high-volume append-only tables (TrackingEvents), normalized address lookups, date-range pricing tables, recursive hierarchies, and soft-delete patterns — all in one place.

---

## Schema Overview

The schema is organized into five clusters.

### Cluster 1 — Parties

| Table | Purpose |
|-------|---------|
| Customers | Individual retail shippers |
| BusinessAccounts | Corporate accounts with negotiated contracts and credit terms |
| BusinessContacts | Named contacts within a BusinessAccount (multiple per account) |
| Addresses | Normalized, reusable address records (origin, destination, billing) |
| BusinessAccountAddresses | Links a BusinessAccount to one or more Addresses |

### Cluster 2 — Network

| Table | Purpose |
|-------|---------|
| Facilities | Physical locations: hubs, depots, retail counters |
| ServiceZones | Geographic pricing zones (US + Canada) |
| ZonePostalCodes | Postal code ranges mapped to a ServiceZone |
| Routes | Directional connections between two Facilities |

### Cluster 3 — Shipments

| Table | Purpose |
|-------|---------|
| Shipments | Parent record: one sender, one recipient, one service tier |
| Packages | Individual parcels within a Ground or Express shipment |
| FreightBills | LTL freight record attached to a Freight shipment |
| Pallets | Individual pallet units within a FreightBill |
| TrackingEvents | Every scan event for a Package or Pallet — the high-volume table |

### Cluster 4 — Operations

| Table | Purpose |
|-------|---------|
| Employees | All staff across all facilities |
| Drivers | Subset of Employees who operate vehicles (subtype relationship) |
| Vehicles | Truck fleet, typed by capacity class |
| Assignments | Links a Driver + Vehicle + Route for a given date and shift |

### Cluster 5 — Commercial

| Table | Purpose |
|-------|---------|
| RateCards | Pricing rules per service tier, zone pair, and weight band |
| Invoices | Monthly invoices for Business accounts |
| InvoiceLineItems | Individual shipments billed on an invoice |
| Payments | Payments applied against an Invoice (partial payments supported) |

---

## Seed Data Volumes

When set up with the full DDL + seed data, TarLogistics contains approximately:

| Table | Approximate Rows |
|-------|-----------------|
| Addresses | 4,500 |
| Customers | 1,500 |
| BusinessAccounts | 250 |
| BusinessContacts | ~500 |
| Facilities | 14 (3 hubs, 7 depots, 4 retail counters) |
| ServiceZones | ~30 |
| ZonePostalCodes | ~300 |
| Routes | ~40 |
| Employees | ~200 |
| Drivers | ~80 |
| Vehicles | ~60 |
| Assignments | ~500 |
| RateCards | ~200 |
| Shipments | 10,000 |
| Packages | ~22,000 |
| FreightBills | ~1,200 |
| Pallets | ~1,800 |
| TrackingEvents | ~80,000 |
| Invoices | ~600 |
| InvoiceLineItems | ~3,000 |
| Payments | ~800 |

TrackingEvents is the largest table by design — it is append-only in real operations and is the primary table for indexing, partitioning, and performance exercises in later books.

---

## Notable Design Features

These design choices are not accidental. Each one is a teaching opportunity that appears explicitly in one or more books.

**XOR CHECK constraints** — A `Shipment` has either a retail sender (`SenderCustomerID`) or a business account sender (`SenderBusinessAccountID`), never both. A `TrackingEvent` links to either a `PackageID` or a `PalletID`, never both. Both are enforced with CHECK constraints.

**Persisted computed column** — `Packages.DimWeightKg` is computed from `(LengthCm * WidthCm * HeightCm / 5000.0)` and persisted. Billing uses the greater of actual weight and dimensional weight — a natural CASE expression and computed column teaching moment.

**Self-referencing foreign keys** — `Facilities.ParentFacilityID` models the hub-and-spoke hierarchy (depot → hub). `Employees.ManagerEmployeeID` models the org chart. Both enable recursive CTE exercises in later books.

**Supertype/subtype relationship** — `Drivers` uses `EmployeeID` as both its primary key and foreign key to `Employees`. Not every employee drives. Drivers carry additional attributes (license class, expiry, endorsements) that don't belong on the main table.

**Soft deletes** — All main entities carry `DeletedAt DATETIME2 NULL`. A NULL value means the record is active. A timestamp means it has been soft-deleted. Paired with a filtered nonclustered index on `WHERE DeletedAt IS NULL` — a deliberate index teaching moment.

**Audit columns** — Every table carries `CreatedAt`, `CreatedBy`, `ModifiedAt`, and `ModifiedBy`. These are set at seed time with a fixed user (`taryuni`) and timestamp so the seed is reproducible regardless of when it runs.

**Slow-changing rate cards** — `RateCards` includes `EffectiveFrom` and `EffectiveTo` columns. A rate can be superseded without being deleted. This is an SCD Type 2 pattern introduced in Book 1 and explored in depth in later books.

**Tracking number format** — `TL` + `ServiceCode(1)` + `YYYYMMDD(8)` + `HH(2)` + `GlobalSequence(5)` = 18 characters. Examples: `TLG2025012414000001` (Ground), `TLE2025012409000047` (Express), `TLF2025012407000003` (Freight). Single global SEQUENCE object that never resets. Hour embedding enables time-of-day analytics demonstrations.

**Multi-currency** — Every monetary column is paired with a `CurrencyCode CHAR(3)` column (`USD` or `CAD`). An `ExchangeRateToUSD` snapshot is stored at transaction time on `Invoices` and `Payments`.

**BIGINT primary key on TrackingEvents** — INT would eventually overflow on a high-volume append-only table. BIGINT is the correct choice and the reason why is explained in Book 1.

---

## How TarLogistics Is Used Across the Series

| Book | How TarLogistics Is Used |
|------|--------------------------|
| 1 — SQL Server Fundamentals | Schema introduced; DDL and seed data set up; used for all Chapter 4–10 exercises |
| 2 — Performance Tuning | TrackingEvents partitioned by EventTimestamp; covering indexes added to Shipments; execution plan exercises use real data volume |
| 3 — Backup and Recovery | TarLogistics is the database you back up, corrupt, and restore — multiple times, in multiple scenarios |
| 4 — High Availability | AG setup and failover demonstrated on the live TarLogistics instance; readable secondary used for reporting queries |
| 5 — Database Security | Row-level security on BusinessAccount data; column encryption on payment references |
| 6 — T-SQL for Database Professionals | Advanced query patterns: window functions over TrackingEvents, recursive CTEs on the Facilities hierarchy, dynamic SQL for rate card lookups |
| 7 — Monitoring and Alerting | DMV queries, Extended Events sessions, and custom alert frameworks run against the live TarLogistics database |
| 8 — Automation and Scripting | SQL Agent jobs for index maintenance, statistics updates, and report delivery — all targeting TarLogistics |
| 9 — Azure SQL and Cloud Migration | Schema compatibility review; migration exercises move TarLogistics to Azure SQL / SQL Managed Instance |
| 10 — The DBA Career Playbook | Capstone — the full DBA lifecycle demonstrated end-to-end on TarLogistics |

---

## Setup Options

### Option 1 — DDL only (schema, no data)

Run `TarLogistics-DDL.sql` against your SQL Server instance. This creates the database with all 21 tables, constraints, and indexes. Suitable for Chapters 4–7 exercises where seed data is not required.

Open in SSMS and press F5, or run via SQLCMD:

```
sqlcmd -S <your-server>\SQLDEV -E -C -i TarLogistics-DDL.sql
```

---

### Option 2 — DDL + seed data (recommended)

Run the DDL first (Option 1), then run the seed data. The seed scripts require SQLCMD — they use `:r` directives to chain the six seed files in order, and `:r` is a SQLCMD command, not T-SQL.

**Before running:**

1. Download the companion name bank CSV from the book's resource page. Place it at the path referenced in `seed/01-parties.sql`:
   ```
   BULK INSERT #NameBank FROM '<your-path>\tar-logistics-name-bank.csv' ...
   ```
   Update that path in `01-parties.sql` to match where you saved the file.

2. Update the `:r` file paths in `seed/00-run-all.sql` to match where you cloned this repository:
   ```sql
   :r "C:\your\path\to\SQL-Server-Mastery-Series\TarLogistics\seed\01-parties.sql"
   ```

3. Run via SQLCMD (required — SSMS with SQLCMD Mode enabled also works):
   ```
   sqlcmd -S <your-server>\SQLDEV -E -C -i "C:\your\path\to\seed\00-run-all.sql"
   ```

The seed runs in this order: `01-parties` → `02-network` → `03-hr` → `04-catalog` → `05-operations` → `06-finance`. Order matters — later files depend on rows created by earlier ones.

After the seed completes, `00-run-all.sql` automatically runs verification checks (row counts, XOR constraint violations, orphan checks, temporal ordering). If all checks pass, the database is ready.

**Enabling SQLCMD Mode in SSMS:**
Query menu → SQLCMD Mode. The `:r` directives will not work without it.

---

### Option 3 — Backup restore

A `.bak` file with the complete database (DDL + seed data) is available as a release asset on this repository's Releases page. This is the fastest option if you want to skip the seed process.

Download the file, then restore:

```sql
RESTORE DATABASE TarLogistics
FROM DISK = 'C:\your\download\path\TarLogistics.bak'
WITH MOVE 'TarLogistics'     TO 'E:\DEV\DATA\TarLogistics.mdf',
     MOVE 'TarLogistics_log' TO 'L:\DEV\LOG\TarLogistics_log.ldf';
```

Adjust the file paths to match your SQL Server data and log directories. If you are not sure where those are, run this first:

```sql
SELECT name, physical_name FROM sys.master_files WHERE database_id = 1;
```

The `master` database paths will show you the default data and log directories for your instance.

---

## Requirements

- SQL Server 2022 Developer Edition (free) or any edition of SQL Server 2019+
- SQL Server Management Studio (SSMS) 19 or later
- SQLCMD — required for seed data only; included with SQL Server tools

---

## Seed File Reference

| File | Cluster | What It Populates |
|------|---------|-------------------|
| `00-run-all.sql` | All | Orchestrates the full seed run and runs verification checks |
| `01-parties.sql` | Parties | Addresses, Customers, BusinessAccounts, BusinessContacts, BusinessAccountAddresses |
| `02-network.sql` | Network | Facilities, ServiceZones, ZonePostalCodes, Routes |
| `03-hr.sql` | Operations | Employees, Drivers, Vehicles, Assignments |
| `04-catalog.sql` | Commercial | RateCards |
| `05-operations.sql` | Shipments | Shipments, Packages, FreightBills, Pallets, TrackingEvents |
| `06-finance.sql` | Commercial | Invoices, InvoiceLineItems, Payments |
 
