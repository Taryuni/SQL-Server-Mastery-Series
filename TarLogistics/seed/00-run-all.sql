-- =============================================================================
-- 00-run-all.sql
-- Runs the full TarLogistics seed in order, then verifies the result.
-- =============================================================================
-- Must be executed via sqlcmd (or SSMS with SQLCMD Mode enabled) — the
-- ":r" directives below are SQLCMD scripting commands, not T-SQL.
--
--   sqlcmd -S <server>\SQLDEV -E -C -i "00-run-all.sql"
--
-- IMPORTANT: Update the file paths in the :r directives below to match
-- the location where you cloned this repository on your machine.
-- For example, if you cloned to C:\repos\sql-server-mastery-series, the
-- paths should read:
--   :r "C:\repos\sql-server-mastery-series\TarLogistics\seed\01-parties.sql"
--
-- Run order matters: 03-hr.sql populates dbo.Assignments because Assignments
-- needs Drivers and Vehicles, both created in 03-hr.sql.
-- =============================================================================

USE TarLogistics;
GO
SET NOCOUNT ON;
PRINT '=============================================================================';
PRINT 'TarLogistics seed - starting run: ' + CONVERT(VARCHAR(30), SYSUTCDATETIME(), 120);
PRINT '=============================================================================';
GO

-- Update these paths to match your local clone location:
:r ".\01-parties.sql"
:r ".\02-network.sql"
:r ".\03-hr.sql"
:r ".\04-catalog.sql"
:r ".\05-operations.sql"
:r ".\06-finance.sql"

PRINT '=============================================================================';
PRINT 'All seed files completed. Running verification checks...';
PRINT '=============================================================================';
GO

-- =============================================================================
-- VERIFICATION
-- =============================================================================

-- 1. Row counts per table
SELECT 'Addresses'             AS TableName, COUNT(*) AS Rows FROM dbo.Addresses
UNION ALL SELECT 'Customers',             COUNT(*) FROM dbo.Customers
UNION ALL SELECT 'BusinessAccounts',      COUNT(*) FROM dbo.BusinessAccounts
UNION ALL SELECT 'BusinessContacts',      COUNT(*) FROM dbo.BusinessContacts
UNION ALL SELECT 'BusinessAccountAddresses', COUNT(*) FROM dbo.BusinessAccountAddresses
UNION ALL SELECT 'Facilities',            COUNT(*) FROM dbo.Facilities
UNION ALL SELECT 'ServiceZones',          COUNT(*) FROM dbo.ServiceZones
UNION ALL SELECT 'ZonePostalCodes',       COUNT(*) FROM dbo.ZonePostalCodes
UNION ALL SELECT 'Routes',                COUNT(*) FROM dbo.Routes
UNION ALL SELECT 'Employees',             COUNT(*) FROM dbo.Employees
UNION ALL SELECT 'Drivers',               COUNT(*) FROM dbo.Drivers
UNION ALL SELECT 'Vehicles',              COUNT(*) FROM dbo.Vehicles
UNION ALL SELECT 'Assignments',           COUNT(*) FROM dbo.Assignments
UNION ALL SELECT 'RateCards',             COUNT(*) FROM dbo.RateCards
UNION ALL SELECT 'Shipments',             COUNT(*) FROM dbo.Shipments
UNION ALL SELECT 'Packages',              COUNT(*) FROM dbo.Packages
UNION ALL SELECT 'Pallets',               COUNT(*) FROM dbo.Pallets
UNION ALL SELECT 'FreightBills',          COUNT(*) FROM dbo.FreightBills
UNION ALL SELECT 'TrackingEvents',        COUNT(*) FROM dbo.TrackingEvents
UNION ALL SELECT 'Invoices',              COUNT(*) FROM dbo.Invoices
UNION ALL SELECT 'InvoiceLineItems',      COUNT(*) FROM dbo.InvoiceLineItems
UNION ALL SELECT 'Payments',              COUNT(*) FROM dbo.Payments;
GO

-- 2. XOR constraint verification — must return 0
DECLARE @ShipmentXorViolations INT;
SELECT @ShipmentXorViolations = COUNT(*) FROM dbo.Shipments
WHERE NOT (
    (SenderCustomerID IS NOT NULL AND SenderBusinessAccountID IS NULL)
    OR (SenderCustomerID IS NULL  AND SenderBusinessAccountID IS NOT NULL)
);
SELECT @ShipmentXorViolations AS Shipment_XOR_Violations;
IF @ShipmentXorViolations <> 0
    RAISERROR('Verification FAILED: Shipment sender XOR returned %d violations.', 16, 1, @ShipmentXorViolations);
GO

-- 3. TrackingEvents orphan check — must return 0
DECLARE @OrphanedTrackingEvents INT;
SELECT @OrphanedTrackingEvents = COUNT(*)
FROM dbo.TrackingEvents te
LEFT JOIN dbo.Employees e ON te.OperatorEmployeeID = e.EmployeeID
WHERE te.OperatorEmployeeID IS NOT NULL AND e.EmployeeID IS NULL;
SELECT @OrphanedTrackingEvents AS Orphaned_TrackingEvents;
IF @OrphanedTrackingEvents <> 0
    RAISERROR('Verification FAILED: Orphaned TrackingEvents returned %d violations.', 16, 1, @OrphanedTrackingEvents);
GO

-- 4. FreightBill/Shipment integrity — must return 0
DECLARE @FreightBillsWithoutPallets INT;
SELECT @FreightBillsWithoutPallets = COUNT(*)
FROM dbo.FreightBills fb
LEFT JOIN dbo.Pallets p ON p.FreightBillID = fb.FreightBillID
WHERE p.PalletID IS NULL;
SELECT @FreightBillsWithoutPallets AS FreightBills_Without_Pallets;
IF @FreightBillsWithoutPallets <> 0
    RAISERROR('Verification FAILED: FreightBills without Pallets returned %d violations.', 16, 1, @FreightBillsWithoutPallets);
GO

-- 5. Tracking event temporal ordering
DECLARE @TrueOutOfOrder INT;
SELECT @TrueOutOfOrder = COUNT(*) FROM (
    SELECT PackageID, PalletID, EventTimestamp,
           LAG(EventTimestamp) OVER (
               PARTITION BY EntityType, COALESCE(PackageID, PalletID)
               ORDER BY TrackingEventID
           ) AS PrevTimestamp
    FROM dbo.TrackingEvents
) x
WHERE EventTimestamp < PrevTimestamp;
SELECT @TrueOutOfOrder AS Out_Of_Order_Events_Corrected;
IF @TrueOutOfOrder <> 0
    RAISERROR('Verification FAILED: TrackingEvents out-of-order returned %d violations.', 16, 1, @TrueOutOfOrder);
GO

PRINT '=============================================================================';
PRINT 'Verification complete. Any failures were raised as errors above.';
PRINT 'Finished: ' + CONVERT(VARCHAR(30), SYSUTCDATETIME(), 120);
PRINT '=============================================================================';
GO
