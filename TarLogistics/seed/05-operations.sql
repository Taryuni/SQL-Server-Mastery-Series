-- =============================================================================
-- 05-operations.sql
-- Cluster 3: Shipments, Packages, Pallets, FreightBills, TrackingEvents
-- =============================================================================
-- ServiceTier mix: Ground 41% / Express 47% / Freight 12%.
-- FreightBills has a UNIQUE constraint on ShipmentID (one bill per freight
-- shipment) and targets ~1,200 rows — 12% of 10,000, not 30%.
-- "Overnight" folds into Express; "International" = IsCrossBorder flag.
--
-- Address strategy: origins/destinations are drawn from the existing
-- Addresses pool built in 01-parties.sql / 02-network.sql rather than
-- minting new rows per shipment.
--
-- TrackingEvents facility routing: PICKUP/delivery events use a random
-- facility from all 14; hub scans use a random hub from the 3.
-- =============================================================================

USE TarLogistics;
GO
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @SeedDate DATETIME2(7) = '2026-07-20T00:00:00.0000000';
    DECLARE @TarYuni NVARCHAR(100) = 'taryuni';
    DECLARE @Today DATE = '2026-07-20';
    DECLARE @RecentCutoff DATETIME2(7) = '2026-06-20T00:00:00.0000000';
    DECLARE @RangeDays INT = DATEDIFF(DAY, '2024-01-01', '2026-07-20');

    IF OBJECT_ID('tempdb..#Tally') IS NOT NULL DROP TABLE #Tally;
    ;WITH T(n) AS (
        SELECT TOP (100000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
        FROM sys.all_objects a CROSS JOIN sys.all_objects b
    )
    SELECT n INTO #Tally FROM T;
    CREATE UNIQUE CLUSTERED INDEX IX_Tally ON #Tally (n);

    -- Numbered address, customer, account, and facility pools
    IF OBJECT_ID('tempdb..#AddrPoolNumbered') IS NOT NULL DROP TABLE #AddrPoolNumbered;
    SELECT AddressID, CountryCode,
           ROW_NUMBER() OVER (PARTITION BY CountryCode ORDER BY AddressID) AS RowNum
    INTO #AddrPoolNumbered
    FROM dbo.Addresses
    WHERE CountryCode IN ('US','CA');
    CREATE CLUSTERED INDEX IX_APN ON #AddrPoolNumbered (CountryCode, RowNum);

    IF OBJECT_ID('tempdb..#AddrPoolCounts') IS NOT NULL DROP TABLE #AddrPoolCounts;
    SELECT CountryCode, COUNT(*) AS Cnt INTO #AddrPoolCounts FROM #AddrPoolNumbered GROUP BY CountryCode;

    IF OBJECT_ID('tempdb..#CustomerNumbered') IS NOT NULL DROP TABLE #CustomerNumbered;
    SELECT CustomerID, ROW_NUMBER() OVER (ORDER BY CustomerID) AS RowNum INTO #CustomerNumbered FROM dbo.Customers;
    DECLARE @CustomerCount INT = (SELECT COUNT(*) FROM #CustomerNumbered);

    IF OBJECT_ID('tempdb..#BizAcctNumbered') IS NOT NULL DROP TABLE #BizAcctNumbered;
    SELECT BusinessAccountID, ROW_NUMBER() OVER (ORDER BY BusinessAccountID) AS RowNum INTO #BizAcctNumbered FROM dbo.BusinessAccounts;
    DECLARE @BizAcctCount INT = (SELECT COUNT(*) FROM #BizAcctNumbered);

    IF OBJECT_ID('tempdb..#AllFacNumbered') IS NOT NULL DROP TABLE #AllFacNumbered;
    SELECT FacilityID, ROW_NUMBER() OVER (ORDER BY FacilityID) AS RowNum INTO #AllFacNumbered FROM dbo.Facilities;
    DECLARE @AllFacCount INT = (SELECT COUNT(*) FROM #AllFacNumbered);

    IF OBJECT_ID('tempdb..#HubFacNumbered') IS NOT NULL DROP TABLE #HubFacNumbered;
    SELECT FacilityID, ROW_NUMBER() OVER (ORDER BY FacilityID) AS RowNum INTO #HubFacNumbered FROM dbo.Facilities WHERE FacilityType = 'Hub';
    DECLARE @HubFacCount INT = (SELECT COUNT(*) FROM #HubFacNumbered);

    IF OBJECT_ID('tempdb..#EmpByFacility') IS NOT NULL DROP TABLE #EmpByFacility;
    SELECT EmployeeID, FacilityID, ROW_NUMBER() OVER (PARTITION BY FacilityID ORDER BY EmployeeID) AS RowInFacility
    INTO #EmpByFacility
    FROM dbo.Employees;
    CREATE CLUSTERED INDEX IX_EBF ON #EmpByFacility (FacilityID, RowInFacility);

    IF OBJECT_ID('tempdb..#EmpCountByFacility') IS NOT NULL DROP TABLE #EmpCountByFacility;
    SELECT FacilityID, COUNT(*) AS Cnt INTO #EmpCountByFacility FROM #EmpByFacility GROUP BY FacilityID;

    -- =====================================================================
    -- SHIPMENTS (10,000)
    -- =====================================================================
    IF OBJECT_ID('tempdb..#ShipPlan') IS NOT NULL DROP TABLE #ShipPlan;
    SELECT t.n AS SeqNum INTO #ShipPlan FROM #Tally t WHERE t.n <= 10000;

    ALTER TABLE #ShipPlan ADD
        ServiceTier NVARCHAR(20), ServiceCode CHAR(1),
        OriginCountry CHAR(2), DestCountry CHAR(2), IsCrossBorder BIT,
        SenderType NVARCHAR(10),
        CreatedAt DATETIME2(7),
        OriginPickIdx INT, DestPickIdxRaw INT, DestPickIdx INT,
        OriginAddressID INT, DestinationAddressID INT,
        SenderPickIdx INT, SenderCustomerID INT, SenderBusinessAccountID INT,
        ShipmentStatus NVARCHAR(30),
        SeqVal BIGINT, TrackingNumber NCHAR(18);

    -- ServiceTier: Ground 41% / Express 47% / Freight 12%
    UPDATE #ShipPlan
    SET ServiceTier = CASE WHEN r < 41 THEN 'Ground' WHEN r < 88 THEN 'Express' ELSE 'Freight' END,
        ServiceCode = CASE WHEN r < 41 THEN 'G' WHEN r < 88 THEN 'E' ELSE 'F' END
    FROM (SELECT SeqNum, ABS(CHECKSUM(NEWID())) % 100 AS r FROM #ShipPlan) x
    WHERE #ShipPlan.SeqNum = x.SeqNum;

    -- Geography: 60% US/US, 25% CA/CA, 7.5% US->CA, 7.5% CA->US
    UPDATE #ShipPlan
    SET OriginCountry = CASE WHEN r < 60 THEN 'US' WHEN r < 85 THEN 'CA' WHEN r < 92 THEN 'US' ELSE 'CA' END,
        DestCountry   = CASE WHEN r < 60 THEN 'US' WHEN r < 85 THEN 'CA' WHEN r < 92 THEN 'CA' ELSE 'US' END,
        IsCrossBorder = CASE WHEN r < 85 THEN 0 ELSE 1 END
    FROM (SELECT SeqNum, ABS(CHECKSUM(NEWID())) % 100 AS r FROM #ShipPlan) x
    WHERE #ShipPlan.SeqNum = x.SeqNum;

    -- SenderType: Freight always Business; else 60% Customer / 40% Business
    UPDATE #ShipPlan
    SET SenderType = CASE
        WHEN ServiceTier = 'Freight' THEN 'Business'
        WHEN r < 60 THEN 'Customer'
        ELSE 'Business' END
    FROM (SELECT SeqNum, ABS(CHECKSUM(NEWID())) % 100 AS r FROM #ShipPlan) x
    WHERE #ShipPlan.SeqNum = x.SeqNum;

    -- CreatedAt: uniform across 2-year window, hour 06-20
    UPDATE #ShipPlan
    SET CreatedAt = DATEADD(HOUR, 6 + ABS(CHECKSUM(NEWID())) % 15,
                     DATEADD(DAY, ABS(CHECKSUM(NEWID())) % @RangeDays, CAST('2024-01-01' AS DATETIME2(7))));

    UPDATE sp
    SET OriginPickIdx = (ABS(CHECKSUM(NEWID())) % oc.Cnt) + 1,
        DestPickIdxRaw = (ABS(CHECKSUM(NEWID())) % dc.Cnt) + 1
    FROM #ShipPlan sp
    JOIN #AddrPoolCounts oc ON oc.CountryCode = sp.OriginCountry
    JOIN #AddrPoolCounts dc ON dc.CountryCode = sp.DestCountry;

    UPDATE sp
    SET DestPickIdx = CASE
        WHEN sp.OriginCountry = sp.DestCountry AND sp.DestPickIdxRaw = sp.OriginPickIdx
             THEN (sp.DestPickIdxRaw % dc.Cnt) + 1
        ELSE sp.DestPickIdxRaw END
    FROM #ShipPlan sp
    JOIN #AddrPoolCounts dc ON dc.CountryCode = sp.DestCountry;

    UPDATE sp SET OriginAddressID = oa.AddressID
    FROM #ShipPlan sp
    JOIN #AddrPoolNumbered oa ON oa.CountryCode = sp.OriginCountry AND oa.RowNum = sp.OriginPickIdx;

    UPDATE sp SET DestinationAddressID = da.AddressID
    FROM #ShipPlan sp
    JOIN #AddrPoolNumbered da ON da.CountryCode = sp.DestCountry AND da.RowNum = sp.DestPickIdx;

    UPDATE sp
    SET SenderPickIdx = CASE WHEN SenderType = 'Customer'
            THEN (ABS(CHECKSUM(NEWID())) % @CustomerCount) + 1
            ELSE (ABS(CHECKSUM(NEWID())) % @BizAcctCount) + 1 END
    FROM #ShipPlan sp;

    UPDATE sp SET SenderCustomerID = cn.CustomerID
    FROM #ShipPlan sp JOIN #CustomerNumbered cn ON cn.RowNum = sp.SenderPickIdx
    WHERE sp.SenderType = 'Customer';

    UPDATE sp SET SenderBusinessAccountID = ban.BusinessAccountID
    FROM #ShipPlan sp JOIN #BizAcctNumbered ban ON ban.RowNum = sp.SenderPickIdx
    WHERE sp.SenderType = 'Business';

    UPDATE #ShipPlan
    SET ShipmentStatus = CASE
        WHEN CreatedAt >= @RecentCutoff THEN
            CASE WHEN r < 10 THEN 'Created' WHEN r < 25 THEN 'PickedUp' WHEN r < 65 THEN 'InTransit'
                 WHEN r < 85 THEN 'OutForDelivery' ELSE 'Delivered' END
        ELSE
            CASE WHEN r < 88 THEN 'Delivered' WHEN r < 92 THEN 'Returned'
                 WHEN r < 95 THEN 'Cancelled' ELSE 'FailedDelivery' END
    END
    FROM (SELECT SeqNum, ABS(CHECKSUM(NEWID())) % 100 AS r FROM #ShipPlan) x
    WHERE #ShipPlan.SeqNum = x.SeqNum;

    UPDATE #ShipPlan SET SeqVal = NEXT VALUE FOR dbo.TrackingNumberSeq;

    UPDATE #ShipPlan
    SET TrackingNumber = 'TL' + ServiceCode + FORMAT(CreatedAt, 'yyyyMMdd') +
        RIGHT('0' + CAST(DATEPART(HOUR, CreatedAt) AS VARCHAR(2)), 2) +
        RIGHT('00000' + CAST(SeqVal % 100000 AS VARCHAR(5)), 5);

    INSERT INTO dbo.Shipments (
        TrackingNumber, ServiceTier, SenderCustomerID, SenderBusinessAccountID,
        OriginAddressID, DestinationAddressID,
        IsCrossBorder, CustomsDeclarationValue, CustomsCurrency, DutiesAmount, CustomsClearedAt,
        ShipmentStatus,
        RetailPaymentStatus, RetailPaymentMethod, RetailAmountCharged, RetailCurrency,
        CreatedAt, CreatedBy, ModifiedAt, ModifiedBy)
    SELECT
        sp.TrackingNumber, sp.ServiceTier, sp.SenderCustomerID, sp.SenderBusinessAccountID,
        sp.OriginAddressID, sp.DestinationAddressID,
        sp.IsCrossBorder,
        CASE WHEN sp.IsCrossBorder = 1 THEN CAST(50 + ABS(CHECKSUM(NEWID())) % 4950 AS DECIMAL(12,2)) ELSE NULL END,
        CASE WHEN sp.IsCrossBorder = 1 THEN 'USD' ELSE NULL END,
        CASE WHEN sp.IsCrossBorder = 1 THEN CAST(5 + ABS(CHECKSUM(NEWID())) % 495 AS DECIMAL(12,2)) ELSE NULL END,
        CASE WHEN sp.IsCrossBorder = 1 AND sp.ShipmentStatus IN ('Delivered','OutForDelivery')
             THEN DATEADD(HOUR, 6 + ABS(CHECKSUM(NEWID())) % 48, sp.CreatedAt) ELSE NULL END,
        sp.ShipmentStatus,
        CASE WHEN sp.SenderType = 'Customer' THEN
            CASE WHEN sp.CreatedAt >= @RecentCutoff AND ABS(CHECKSUM(NEWID())) % 100 < 15 THEN 'Pending' ELSE 'Paid' END
        ELSE NULL END,
        CASE WHEN sp.SenderType = 'Customer' THEN
            CASE ABS(CHECKSUM(NEWID())) % 3 WHEN 0 THEN 'Credit Card' WHEN 1 THEN 'Debit Card' ELSE 'Cash' END
        ELSE NULL END,
        CASE WHEN sp.SenderType = 'Customer' THEN
            CASE sp.ServiceTier WHEN 'Ground' THEN CAST(8 + ABS(CHECKSUM(NEWID())) % 3700 / 100.0 AS DECIMAL(10,2))
                                 ELSE CAST(15 + ABS(CHECKSUM(NEWID())) % 7500 / 100.0 AS DECIMAL(10,2)) END
        ELSE NULL END,
        CASE WHEN sp.SenderType = 'Customer' THEN
            CASE WHEN sp.OriginCountry = 'US' THEN 'USD' ELSE 'CAD' END
        ELSE NULL END,
        sp.CreatedAt, @TarYuni, sp.CreatedAt, @TarYuni
    FROM #ShipPlan sp;

    PRINT 'Shipments inserted: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    IF OBJECT_ID('tempdb..#ShipMap') IS NOT NULL DROP TABLE #ShipMap;
    SELECT s.ShipmentID, sp.*
    INTO #ShipMap
    FROM dbo.Shipments s
    JOIN (SELECT ShipmentID, ROW_NUMBER() OVER (ORDER BY ShipmentID) AS rn FROM dbo.Shipments) r ON r.ShipmentID = s.ShipmentID
    JOIN #ShipPlan sp ON sp.SeqNum = r.rn;
    CREATE UNIQUE CLUSTERED INDEX IX_ShipMap ON #ShipMap (ShipmentID);

    -- =====================================================================
    -- PACKAGES (~22,000: parcel shipments x ~2.5 avg packages)
    -- =====================================================================
    IF OBJECT_ID('tempdb..#ParcelShip') IS NOT NULL DROP TABLE #ParcelShip;
    SELECT ShipmentID, ShipmentStatus, CreatedAt AS ShipCreatedAt, ServiceCode,
           CAST(NULL AS INT) AS PackageCount
    INTO #ParcelShip
    FROM #ShipMap
    WHERE ServiceTier IN ('Ground', 'Express');

    UPDATE #ParcelShip
    SET PackageCount = CASE WHEN r < 25 THEN 1 WHEN r < 55 THEN 2 WHEN r < 80 THEN 3 WHEN r < 92 THEN 4 ELSE 5 END
    FROM (SELECT ShipmentID, ABS(CHECKSUM(NEWID())) % 100 AS r FROM #ParcelShip) x
    WHERE #ParcelShip.ShipmentID = x.ShipmentID;

    IF OBJECT_ID('tempdb..#PkgPlan') IS NOT NULL DROP TABLE #PkgPlan;
    SELECT ps.ShipmentID, ps.ShipmentStatus, ps.ShipCreatedAt, ps.ServiceCode, t.n AS PkgSlot
    INTO #PkgPlan
    FROM #ParcelShip ps
    JOIN #Tally t ON t.n <= ps.PackageCount;

    ALTER TABLE #PkgPlan ADD SeqVal BIGINT, TrackingNumber NCHAR(18), PackageStatus NVARCHAR(30);
    UPDATE #PkgPlan SET SeqVal = NEXT VALUE FOR dbo.TrackingNumberSeq;

    UPDATE #PkgPlan
    SET TrackingNumber = 'TL' + ServiceCode + FORMAT(ShipCreatedAt, 'yyyyMMdd') +
        RIGHT('0' + CAST(DATEPART(HOUR, ShipCreatedAt) AS VARCHAR(2)), 2) +
        RIGHT('00000' + CAST(SeqVal % 100000 AS VARCHAR(5)), 5),
        PackageStatus = CASE ShipmentStatus
            WHEN 'Delivered' THEN 'Delivered' WHEN 'FailedDelivery' THEN 'DeliveryAttempted'
            WHEN 'Returned' THEN 'DeliveryAttempted' WHEN 'Cancelled' THEN 'Created'
            WHEN 'OutForDelivery' THEN 'OutForDelivery' ELSE 'InTransit' END;

    IF OBJECT_ID('tempdb..#PkgMap') IS NOT NULL DROP TABLE #PkgMap;
    CREATE TABLE #PkgMap (PackageID INT, ShipmentID INT, ShipmentStatus NVARCHAR(30), ShipCreatedAt DATETIME2(7));

    MERGE INTO dbo.Packages AS tgt
    USING #PkgPlan AS src
    ON 1 = 0
    WHEN NOT MATCHED THEN
        INSERT (ShipmentID, TrackingNumber, ActualWeightKg, LengthCm, WidthCm, HeightCm,
                PackageStatus, Notes, CreatedAt, CreatedBy, ModifiedAt, ModifiedBy)
        VALUES (src.ShipmentID, src.TrackingNumber,
                CAST(0.5 + ABS(CHECKSUM(NEWID())) % 4950 / 100.0 AS DECIMAL(8,2)),
                CAST(10 + ABS(CHECKSUM(NEWID())) % 111 AS DECIMAL(8,2)),
                CAST(10 + ABS(CHECKSUM(NEWID())) % 111 AS DECIMAL(8,2)),
                CAST(10 + ABS(CHECKSUM(NEWID())) % 111 AS DECIMAL(8,2)),
                src.PackageStatus, NULL, src.ShipCreatedAt, @TarYuni, src.ShipCreatedAt, @TarYuni)
    OUTPUT inserted.PackageID, src.ShipmentID, src.ShipmentStatus, src.ShipCreatedAt
    INTO #PkgMap (PackageID, ShipmentID, ShipmentStatus, ShipCreatedAt);

    PRINT 'Packages inserted: ' + CAST(@@ROWCOUNT AS VARCHAR(10));
    CREATE UNIQUE CLUSTERED INDEX IX_PkgMap ON #PkgMap (PackageID);

    -- =====================================================================
    -- FREIGHTBILLS (~1,200) + PALLETS (~1,800)
    -- =====================================================================
    IF OBJECT_ID('tempdb..#FreightShip') IS NOT NULL DROP TABLE #FreightShip;
    SELECT ShipmentID, ShipmentStatus, CreatedAt AS ShipCreatedAt, CAST(NULL AS BIGINT) AS SeqVal
    INTO #FreightShip
    FROM #ShipMap
    WHERE ServiceTier = 'Freight';

    UPDATE #FreightShip SET SeqVal = NEXT VALUE FOR dbo.TrackingNumberSeq;

    IF OBJECT_ID('tempdb..#FBResult') IS NOT NULL DROP TABLE #FBResult;
    CREATE TABLE #FBResult (FreightBillID INT, ShipmentID INT, ShipmentStatus NVARCHAR(30), ShipCreatedAt DATETIME2(7));

    MERGE INTO dbo.FreightBills AS tgt
    USING #FreightShip AS src
    ON 1 = 0
    WHEN NOT MATCHED THEN
        INSERT (ShipmentID, BillOfLadingNumber, TotalWeightKg, TotalPallets, HazmatFlag, SpecialInstructions,
                CreatedAt, CreatedBy, ModifiedAt, ModifiedBy)
        VALUES (src.ShipmentID,
                'BOL' + FORMAT(src.ShipCreatedAt, 'yyyyMMdd') + '-' + RIGHT('000000' + CAST(src.SeqVal % 1000000 AS VARCHAR(6)), 6),
                1.00, 1,
                CASE WHEN ABS(CHECKSUM(NEWID())) % 100 < 8 THEN 1 ELSE 0 END,
                CASE WHEN ABS(CHECKSUM(NEWID())) % 100 < 30
                     THEN (CASE ABS(CHECKSUM(NEWID())) % 4
                               WHEN 0 THEN 'Liftgate required at delivery.'
                               WHEN 1 THEN 'Call before delivery.'
                               WHEN 2 THEN 'Inside delivery required.'
                               ELSE 'Deliver to loading dock only.' END)
                     ELSE NULL END,
                src.ShipCreatedAt, @TarYuni, src.ShipCreatedAt, @TarYuni)
    OUTPUT inserted.FreightBillID, src.ShipmentID, src.ShipmentStatus, src.ShipCreatedAt
    INTO #FBResult (FreightBillID, ShipmentID, ShipmentStatus, ShipCreatedAt);

    PRINT 'FreightBills inserted: ' + CAST(@@ROWCOUNT AS VARCHAR(10));
    CREATE UNIQUE CLUSTERED INDEX IX_FBResult ON #FBResult (FreightBillID);

    ALTER TABLE #FBResult ADD PalletCount INT;
    UPDATE #FBResult
    SET PalletCount = CASE WHEN r < 65 THEN 1 WHEN r < 87 THEN 2 WHEN r < 96 THEN 3 WHEN r < 99 THEN 4 ELSE 5 END
    FROM (SELECT FreightBillID, ABS(CHECKSUM(NEWID())) % 100 AS r FROM #FBResult) x
    WHERE #FBResult.FreightBillID = x.FreightBillID;

    IF OBJECT_ID('tempdb..#PalletPlan') IS NOT NULL DROP TABLE #PalletPlan;
    SELECT fb.FreightBillID, fb.ShipmentStatus, fb.ShipCreatedAt, t.n AS PalletNumber
    INTO #PalletPlan
    FROM #FBResult fb
    JOIN #Tally t ON t.n <= fb.PalletCount;

    IF OBJECT_ID('tempdb..#PalletMap') IS NOT NULL DROP TABLE #PalletMap;
    CREATE TABLE #PalletMap (PalletID INT, FreightBillID INT, ShipmentStatus NVARCHAR(30), ShipCreatedAt DATETIME2(7), WeightKg DECIMAL(8,2));

    MERGE INTO dbo.Pallets AS tgt
    USING #PalletPlan AS src
    ON 1 = 0
    WHEN NOT MATCHED THEN
        INSERT (FreightBillID, PalletNumber, WeightKg, Description, HazmatFlag,
                CreatedAt, CreatedBy, ModifiedAt, ModifiedBy)
        VALUES (src.FreightBillID, src.PalletNumber,
                CAST(100 + ABS(CHECKSUM(NEWID())) % 190000 / 100.0 AS DECIMAL(8,2)),
                CASE WHEN ABS(CHECKSUM(NEWID())) % 100 < 40
                     THEN (CASE ABS(CHECKSUM(NEWID())) % 5
                               WHEN 0 THEN 'Palletized dry goods' WHEN 1 THEN 'Shrink-wrapped cartons'
                               WHEN 2 THEN 'Machine parts, crated' WHEN 3 THEN 'Retail inventory restock'
                               ELSE 'Bulk packaged materials' END)
                     ELSE NULL END,
                CASE WHEN ABS(CHECKSUM(NEWID())) % 100 < 6 THEN 1 ELSE 0 END,
                src.ShipCreatedAt, @TarYuni, src.ShipCreatedAt, @TarYuni)
    OUTPUT inserted.PalletID, src.FreightBillID, src.ShipmentStatus, src.ShipCreatedAt, inserted.WeightKg
    INTO #PalletMap (PalletID, FreightBillID, ShipmentStatus, ShipCreatedAt, WeightKg);

    PRINT 'Pallets inserted: ' + CAST(@@ROWCOUNT AS VARCHAR(10));
    CREATE CLUSTERED INDEX IX_PalletMap ON #PalletMap (FreightBillID, PalletID);

    UPDATE fb
    SET TotalWeightKg = agg.SumWeight, TotalPallets = agg.Cnt
    FROM dbo.FreightBills fb
    JOIN (SELECT FreightBillID, SUM(WeightKg) AS SumWeight, COUNT(*) AS Cnt FROM #PalletMap GROUP BY FreightBillID) agg
        ON agg.FreightBillID = fb.FreightBillID;

    PRINT 'FreightBills totals corrected: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    -- =====================================================================
    -- TRACKING EVENTS (~80,000: 3-6 per Package/Pallet)
    -- =====================================================================
    IF OBJECT_ID('tempdb..#SlotTemplate') IS NOT NULL DROP TABLE #SlotTemplate;
    CREATE TABLE #SlotTemplate (PathType NVARCHAR(12), CountGroup INT, Slot INT, EventCodeTemplate NVARCHAR(20));
    INSERT INTO #SlotTemplate (PathType, CountGroup, Slot, EventCodeTemplate) VALUES
    ('InProgress',3,1,'PICKUP'),('InProgress',3,2,'SCAN_HUB'),('InProgress',3,3,'SCAN_HUB'),
    ('InProgress',4,1,'PICKUP'),('InProgress',4,2,'SCAN_HUB'),('InProgress',4,3,'SCAN_HUB'),('InProgress',4,4,'OUT_FOR_DELIVERY'),
    ('Completed',3,1,'PICKUP'),('Completed',3,2,'OUT_FOR_DELIVERY'),('Completed',3,3,'FINAL'),
    ('Completed',4,1,'PICKUP'),('Completed',4,2,'SCAN_HUB'),('Completed',4,3,'OUT_FOR_DELIVERY'),('Completed',4,4,'FINAL'),
    ('Completed',5,1,'PICKUP'),('Completed',5,2,'SCAN_HUB'),('Completed',5,3,'SCAN_HUB'),('Completed',5,4,'OUT_FOR_DELIVERY'),('Completed',5,5,'FINAL'),
    ('Completed',6,1,'PICKUP'),('Completed',6,2,'SCAN_HUB'),('Completed',6,3,'SCAN_HUB'),('Completed',6,4,'SCAN_DEPOT'),('Completed',6,5,'OUT_FOR_DELIVERY'),('Completed',6,6,'FINAL');

    -- ── PACKAGE EVENTS ──────────────────────────────────────────────────
    IF OBJECT_ID('tempdb..#PkgEventBase') IS NOT NULL DROP TABLE #PkgEventBase;
    SELECT pm.PackageID, pm.ShipmentStatus, pm.ShipCreatedAt, sm.ServiceTier,
           CAST(NULL AS NVARCHAR(12)) AS PathType, CAST(NULL AS INT) AS CountGroup, CAST(NULL AS NVARCHAR(20)) AS FinalCode
    INTO #PkgEventBase
    FROM #PkgMap pm
    JOIN #ShipMap sm ON sm.ShipmentID = pm.ShipmentID;

    UPDATE #PkgEventBase
    SET PathType = 'InProgress',
        CountGroup = CASE WHEN ShipmentStatus = 'OutForDelivery' THEN 4 ELSE 3 END
    WHERE ShipCreatedAt >= @RecentCutoff AND ShipmentStatus IN ('Created','PickedUp','InTransit','OutForDelivery');

    UPDATE peb
    SET PathType = 'Completed',
        CountGroup = CASE WHEN r < 75 THEN 3 WHEN r < 93 THEN 4 WHEN r < 98 THEN 5 ELSE 6 END,
        FinalCode = 'DELIVERED'
    FROM #PkgEventBase peb
    JOIN (SELECT PackageID, ABS(CHECKSUM(NEWID())) % 100 AS r FROM #PkgEventBase) x ON x.PackageID = peb.PackageID
    WHERE peb.ShipmentStatus = 'Delivered';

    UPDATE peb
    SET PathType = 'Completed',
        CountGroup = CASE WHEN r < 75 THEN 3 WHEN r < 93 THEN 4 WHEN r < 98 THEN 5 ELSE 6 END,
        FinalCode = 'FAILED_DELIVERY'
    FROM #PkgEventBase peb
    JOIN (SELECT PackageID, ABS(CHECKSUM(NEWID())) % 100 AS r FROM #PkgEventBase) x ON x.PackageID = peb.PackageID
    WHERE peb.ShipmentStatus IN ('FailedDelivery','Returned');

    UPDATE #PkgEventBase SET PathType = 'InProgress', CountGroup = 3 WHERE ShipmentStatus = 'Cancelled';
    UPDATE #PkgEventBase SET PathType = 'InProgress', CountGroup = 3 WHERE CountGroup IS NULL;

    IF OBJECT_ID('tempdb..#PkgEventRows') IS NOT NULL DROP TABLE #PkgEventRows;
    SELECT peb.PackageID, peb.ShipCreatedAt, peb.ServiceTier, peb.PathType, peb.CountGroup, peb.FinalCode, t.n AS Slot
    INTO #PkgEventRows
    FROM #PkgEventBase peb
    JOIN #Tally t ON t.n <= peb.CountGroup;

    ALTER TABLE #PkgEventRows ADD
        EventCodeTemplate NVARCHAR(20), EventCode NVARCHAR(30),
        AllFacPickIdx INT, HubFacPickIdx INT, FacilityID INT,
        EmpPickIdx INT, OperatorEmployeeID INT,
        IncrementHours DECIMAL(10,2), EventTimestamp DATETIME2(7);

    UPDATE per
    SET EventCodeTemplate = st.EventCodeTemplate
    FROM #PkgEventRows per
    JOIN #SlotTemplate st ON st.PathType = per.PathType AND st.CountGroup = per.CountGroup AND st.Slot = per.Slot;

    UPDATE #PkgEventRows SET EventCode = CASE WHEN EventCodeTemplate = 'FINAL' THEN FinalCode ELSE EventCodeTemplate END;

    UPDATE #PkgEventRows
    SET AllFacPickIdx = (ABS(CHECKSUM(NEWID())) % @AllFacCount) + 1,
        HubFacPickIdx = (ABS(CHECKSUM(NEWID())) % @HubFacCount) + 1;

    UPDATE per
    SET FacilityID = CASE WHEN per.EventCode = 'SCAN_HUB' THEN hf.FacilityID ELSE af.FacilityID END
    FROM #PkgEventRows per
    JOIN #AllFacNumbered af ON af.RowNum = per.AllFacPickIdx
    JOIN #HubFacNumbered hf ON hf.RowNum = per.HubFacPickIdx;

    UPDATE per
    SET EmpPickIdx = CASE WHEN ABS(CHECKSUM(NEWID())) % 100 < 60
                          THEN (ABS(CHECKSUM(NEWID())) % ec.Cnt) + 1 ELSE NULL END
    FROM #PkgEventRows per
    JOIN #EmpCountByFacility ec ON ec.FacilityID = per.FacilityID;

    UPDATE per
    SET OperatorEmployeeID = eb.EmployeeID
    FROM #PkgEventRows per
    JOIN #EmpByFacility eb ON eb.FacilityID = per.FacilityID AND eb.RowInFacility = per.EmpPickIdx
    WHERE per.EmpPickIdx IS NOT NULL;

    UPDATE #PkgEventRows
    SET IncrementHours = CASE
        WHEN EventCode = 'PICKUP' THEN 0 + ABS(CHECKSUM(NEWID())) % 5
        WHEN EventCode = 'SCAN_HUB' AND Slot = 2 THEN
            CASE ServiceTier WHEN 'Ground' THEN 24 + ABS(CHECKSUM(NEWID())) % 49
                              WHEN 'Express' THEN 8 + ABS(CHECKSUM(NEWID())) % 23
                              ELSE 24 + ABS(CHECKSUM(NEWID())) % 73 END
        WHEN EventCode = 'SCAN_HUB' AND Slot = 3 THEN 2 + ABS(CHECKSUM(NEWID())) % 7
        WHEN EventCode = 'SCAN_DEPOT' THEN
            CASE ServiceTier WHEN 'Ground' THEN 24 + ABS(CHECKSUM(NEWID())) % 49
                              WHEN 'Express' THEN 8 + ABS(CHECKSUM(NEWID())) % 23
                              ELSE 24 + ABS(CHECKSUM(NEWID())) % 73 END
        WHEN EventCode = 'OUT_FOR_DELIVERY' THEN 8 + ABS(CHECKSUM(NEWID())) % 9
        ELSE 2 + ABS(CHECKSUM(NEWID())) % 7
    END;

    UPDATE per
    SET EventTimestamp = DATEADD(MINUTE, CAST(cum.CumHours * 60 AS INT), per.ShipCreatedAt)
    FROM #PkgEventRows per
    JOIN (SELECT PackageID, Slot,
                 SUM(IncrementHours) OVER (PARTITION BY PackageID ORDER BY Slot ROWS UNBOUNDED PRECEDING) AS CumHours
          FROM #PkgEventRows) cum ON cum.PackageID = per.PackageID AND cum.Slot = per.Slot;

    INSERT INTO dbo.TrackingEvents (PackageID, PalletID, EntityType, FacilityID, EventCode, EventTimestamp,
                                     StatusDescription, OperatorEmployeeID, CreatedAt, CreatedBy)
    SELECT per.PackageID, NULL, 'Package', per.FacilityID, per.EventCode, per.EventTimestamp,
        CASE per.EventCode
            WHEN 'PICKUP' THEN 'Package picked up from origin.'
            WHEN 'SCAN_HUB' THEN 'Scanned at hub facility.'
            WHEN 'SCAN_DEPOT' THEN 'Arrived at delivery-area facility.'
            WHEN 'OUT_FOR_DELIVERY' THEN 'Out for delivery.'
            WHEN 'DELIVERED' THEN 'Delivered.'
            WHEN 'FAILED_DELIVERY' THEN 'Delivery attempt failed.'
            ELSE NULL END,
        per.OperatorEmployeeID, per.EventTimestamp, @TarYuni
    FROM #PkgEventRows per
    ORDER BY per.PackageID, per.Slot
    OPTION (MAXDOP 1);

    PRINT 'Package TrackingEvents inserted: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    -- ── PALLET EVENTS ────────────────────────────────────────────────────
    IF OBJECT_ID('tempdb..#PalEventBase') IS NOT NULL DROP TABLE #PalEventBase;
    SELECT plm.PalletID, plm.ShipmentStatus, plm.ShipCreatedAt,
           CAST('Freight' AS NVARCHAR(20)) AS ServiceTier,
           CAST(NULL AS NVARCHAR(12)) AS PathType, CAST(NULL AS INT) AS CountGroup, CAST(NULL AS NVARCHAR(20)) AS FinalCode
    INTO #PalEventBase
    FROM #PalletMap plm;

    UPDATE #PalEventBase
    SET PathType = 'InProgress',
        CountGroup = CASE WHEN ShipmentStatus = 'OutForDelivery' THEN 4 ELSE 3 END
    WHERE ShipCreatedAt >= @RecentCutoff AND ShipmentStatus IN ('Created','PickedUp','InTransit','OutForDelivery');

    UPDATE peb
    SET PathType = 'Completed',
        CountGroup = CASE WHEN r < 45 THEN 3 WHEN r < 75 THEN 4 WHEN r < 92 THEN 5 ELSE 6 END,
        FinalCode = 'DELIVERED'
    FROM #PalEventBase peb
    JOIN (SELECT PalletID, ABS(CHECKSUM(NEWID())) % 100 AS r FROM #PalEventBase) x ON x.PalletID = peb.PalletID
    WHERE peb.ShipmentStatus = 'Delivered';

    UPDATE peb
    SET PathType = 'Completed',
        CountGroup = CASE WHEN r < 45 THEN 3 WHEN r < 75 THEN 4 WHEN r < 92 THEN 5 ELSE 6 END,
        FinalCode = 'FAILED_DELIVERY'
    FROM #PalEventBase peb
    JOIN (SELECT PalletID, ABS(CHECKSUM(NEWID())) % 100 AS r FROM #PalEventBase) x ON x.PalletID = peb.PalletID
    WHERE peb.ShipmentStatus IN ('FailedDelivery','Returned');

    UPDATE #PalEventBase SET PathType = 'InProgress', CountGroup = 3 WHERE ShipmentStatus = 'Cancelled';
    UPDATE #PalEventBase SET PathType = 'InProgress', CountGroup = 3 WHERE CountGroup IS NULL;

    IF OBJECT_ID('tempdb..#PalEventRows') IS NOT NULL DROP TABLE #PalEventRows;
    SELECT peb.PalletID, peb.ShipCreatedAt, peb.ServiceTier, peb.PathType, peb.CountGroup, peb.FinalCode, t.n AS Slot
    INTO #PalEventRows
    FROM #PalEventBase peb
    JOIN #Tally t ON t.n <= peb.CountGroup;

    ALTER TABLE #PalEventRows ADD
        EventCodeTemplate NVARCHAR(20), EventCode NVARCHAR(30),
        AllFacPickIdx INT, HubFacPickIdx INT, FacilityID INT,
        EmpPickIdx INT, OperatorEmployeeID INT,
        IncrementHours DECIMAL(10,2), EventTimestamp DATETIME2(7);

    UPDATE per SET EventCodeTemplate = st.EventCodeTemplate
    FROM #PalEventRows per
    JOIN #SlotTemplate st ON st.PathType = per.PathType AND st.CountGroup = per.CountGroup AND st.Slot = per.Slot;

    UPDATE #PalEventRows SET EventCode = CASE WHEN EventCodeTemplate = 'FINAL' THEN FinalCode ELSE EventCodeTemplate END;

    UPDATE #PalEventRows
    SET AllFacPickIdx = (ABS(CHECKSUM(NEWID())) % @AllFacCount) + 1,
        HubFacPickIdx = (ABS(CHECKSUM(NEWID())) % @HubFacCount) + 1;

    UPDATE per
    SET FacilityID = CASE WHEN per.EventCode = 'SCAN_HUB' THEN hf.FacilityID ELSE af.FacilityID END
    FROM #PalEventRows per
    JOIN #AllFacNumbered af ON af.RowNum = per.AllFacPickIdx
    JOIN #HubFacNumbered hf ON hf.RowNum = per.HubFacPickIdx;

    UPDATE per
    SET EmpPickIdx = CASE WHEN ABS(CHECKSUM(NEWID())) % 100 < 60
                          THEN (ABS(CHECKSUM(NEWID())) % ec.Cnt) + 1 ELSE NULL END
    FROM #PalEventRows per
    JOIN #EmpCountByFacility ec ON ec.FacilityID = per.FacilityID;

    UPDATE per SET OperatorEmployeeID = eb.EmployeeID
    FROM #PalEventRows per
    JOIN #EmpByFacility eb ON eb.FacilityID = per.FacilityID AND eb.RowInFacility = per.EmpPickIdx
    WHERE per.EmpPickIdx IS NOT NULL;

    UPDATE #PalEventRows
    SET IncrementHours = CASE
        WHEN EventCode = 'PICKUP' THEN 0 + ABS(CHECKSUM(NEWID())) % 5
        WHEN EventCode = 'SCAN_HUB' AND Slot = 2 THEN 24 + ABS(CHECKSUM(NEWID())) % 73
        WHEN EventCode = 'SCAN_HUB' AND Slot = 3 THEN 4 + ABS(CHECKSUM(NEWID())) % 13
        WHEN EventCode = 'SCAN_DEPOT' THEN 24 + ABS(CHECKSUM(NEWID())) % 73
        WHEN EventCode = 'OUT_FOR_DELIVERY' THEN 8 + ABS(CHECKSUM(NEWID())) % 9
        ELSE 2 + ABS(CHECKSUM(NEWID())) % 7
    END;

    UPDATE per
    SET EventTimestamp = DATEADD(MINUTE, CAST(cum.CumHours * 60 AS INT), per.ShipCreatedAt)
    FROM #PalEventRows per
    JOIN (SELECT PalletID, Slot,
                 SUM(IncrementHours) OVER (PARTITION BY PalletID ORDER BY Slot ROWS UNBOUNDED PRECEDING) AS CumHours
          FROM #PalEventRows) cum ON cum.PalletID = per.PalletID AND cum.Slot = per.Slot;

    INSERT INTO dbo.TrackingEvents (PackageID, PalletID, EntityType, FacilityID, EventCode, EventTimestamp,
                                     StatusDescription, OperatorEmployeeID, CreatedAt, CreatedBy)
    SELECT NULL, per.PalletID, 'Pallet', per.FacilityID, per.EventCode, per.EventTimestamp,
        CASE per.EventCode
            WHEN 'PICKUP' THEN 'Pallet picked up from shipper.'
            WHEN 'SCAN_HUB' THEN 'Scanned at hub facility.'
            WHEN 'SCAN_DEPOT' THEN 'Arrived at delivery-area facility.'
            WHEN 'OUT_FOR_DELIVERY' THEN 'Out for delivery.'
            WHEN 'DELIVERED' THEN 'Delivered.'
            WHEN 'FAILED_DELIVERY' THEN 'Delivery attempt failed.'
            ELSE NULL END,
        per.OperatorEmployeeID, per.EventTimestamp, @TarYuni
    FROM #PalEventRows per
    ORDER BY per.PalletID, per.Slot
    OPTION (MAXDOP 1);

    PRINT 'Pallet TrackingEvents inserted: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    COMMIT TRANSACTION;
    PRINT '05-operations.sql completed successfully.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
    DECLARE @ErrSeverity INT = ERROR_SEVERITY();
    DECLARE @ErrState INT = ERROR_STATE();
    RAISERROR('05-operations.sql failed: %s', @ErrSeverity, @ErrState, @ErrMsg);
END CATCH
GO
