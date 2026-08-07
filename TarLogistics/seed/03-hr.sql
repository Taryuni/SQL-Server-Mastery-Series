-- =============================================================================
-- 03-hr.sql
-- Cluster 4: Employees (+ self-ref manager), Drivers, Vehicles
-- Plus: Assignments (RouteAssignments) — see note below.
-- =============================================================================
-- Assignments (dbo.Assignments) is generated at the end of this file rather
-- than in 02-network.sql, because it has NOT NULL FKs to Drivers and
-- Vehicles, both created here. See the header note in 02-network.sql.
-- =============================================================================
-- NOTE: This file requires the same companion name-bank CSV as 01-parties.sql.
-- Update the BULK INSERT path below to match your local copy.
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

    -- -------------------------------------------------------------------
    -- Name bank — update this path to match your local clone location
    -- -------------------------------------------------------------------
    IF OBJECT_ID('tempdb..#NameBank') IS NOT NULL DROP TABLE #NameBank;
    CREATE TABLE #NameBank (
        first_name      NVARCHAR(100),
        last_name       NVARCHAR(100),
        origin_category NVARCHAR(30),
        origin_country  NVARCHAR(50),
        sub_group       NVARCHAR(50),
        gender          CHAR(1)
    );
    BULK INSERT #NameBank
    FROM 'C:\path\to\tar-logistics-name-bank.csv'  -- UPDATE THIS PATH
    WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', TABLOCK);

    IF OBJECT_ID('tempdb..#NameBankCatCounts') IS NOT NULL DROP TABLE #NameBankCatCounts;
    SELECT origin_category, COUNT(*) AS CatCount
    INTO #NameBankCatCounts
    FROM #NameBank
    GROUP BY origin_category;

    IF OBJECT_ID('tempdb..#NameBankNumbered') IS NOT NULL DROP TABLE #NameBankNumbered;
    SELECT
        first_name, last_name, gender, origin_category,
        ROW_NUMBER() OVER (PARTITION BY origin_category ORDER BY (SELECT NULL)) AS CatRowNum
    INTO #NameBankNumbered
    FROM #NameBank;
    CREATE CLUSTERED INDEX IX_NBN ON #NameBankNumbered (origin_category, CatRowNum);

    IF OBJECT_ID('tempdb..#Tally') IS NOT NULL DROP TABLE #Tally;
    ;WITH T(n) AS (
        SELECT TOP (20000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
        FROM sys.all_objects a CROSS JOIN sys.all_objects b
    )
    SELECT n INTO #Tally FROM T;
    CREATE UNIQUE CLUSTERED INDEX IX_Tally ON #Tally (n);

    -- -------------------------------------------------------------------
    -- Per-facility reference data: area code / state / country + headcount targets
    -- -------------------------------------------------------------------
    IF OBJECT_ID('tempdb..#FacilityInfo') IS NOT NULL DROP TABLE #FacilityInfo;
    CREATE TABLE #FacilityInfo (FacilityCode NVARCHAR(10), AreaCode NVARCHAR(3), StateProvince NVARCHAR(100), CountryCode CHAR(2), FacilityType NVARCHAR(30));
    INSERT INTO #FacilityInfo (FacilityCode, AreaCode, StateProvince, CountryCode, FacilityType) VALUES
    ('CMH-HUB-01','614','OH','US','Hub'), ('YYZ-HUB-01','905','ON','CA','Hub'), ('YUL-HUB-01','514','QC','CA','Hub'),
    ('ORD-DEP-01','773','IL','US','Depot'), ('JFK-DEP-01','718','NY','US','Depot'), ('ATL-DEP-01','404','GA','US','Depot'),
    ('DFW-DEP-01','972','TX','US','Depot'), ('LAX-DEP-01','310','CA','US','Depot'), ('YVR-DEP-01','604','BC','CA','Depot'),
    ('YYC-DEP-01','403','AB','CA','Depot'),
    ('BOS-RET-01','617','MA','US','RetailCounter'), ('MIA-RET-01','305','FL','US','RetailCounter'),
    ('SEA-RET-01','206','WA','US','RetailCounter'), ('YOW-RET-01','613','ON','CA','RetailCounter');

    IF OBJECT_ID('tempdb..#FacilityRoster') IS NOT NULL DROP TABLE #FacilityRoster;
    CREATE TABLE #FacilityRoster (FacilityCode NVARCHAR(10), TotalHeadcount INT, DriverTarget INT, SupervisorCount INT, VehicleCount INT);
    INSERT INTO #FacilityRoster (FacilityCode, TotalHeadcount, DriverTarget, SupervisorCount, VehicleCount) VALUES
    ('CMH-HUB-01', 98, 32, 5, 27), ('YYZ-HUB-01', 93, 30, 5, 26), ('YUL-HUB-01', 90, 28, 4, 27),
    ('ORD-DEP-01', 31, 13, 0, 16), ('JFK-DEP-01', 33, 14, 0, 16), ('ATL-DEP-01', 29, 12, 0, 15),
    ('DFW-DEP-01', 28, 12, 0, 15), ('LAX-DEP-01', 34, 14, 0, 16), ('YVR-DEP-01', 27, 12, 0, 15),
    ('YYC-DEP-01', 26, 12, 0, 15),
    ('BOS-RET-01', 7, 1, 0, 3), ('MIA-RET-01', 6, 1, 0, 3), ('SEA-RET-01', 8, 2, 0, 3), ('YOW-RET-01', 6, 1, 0, 3);

    -- Name-origin mix per facility
    IF OBJECT_ID('tempdb..#FacilityNameMix') IS NOT NULL DROP TABLE #FacilityNameMix;
    CREATE TABLE #FacilityNameMix (FacilityCode NVARCHAR(10), OriginCategory NVARCHAR(30), WeightPct INT);
    INSERT INTO #FacilityNameMix (FacilityCode, OriginCategory, WeightPct) VALUES
    ('CMH-HUB-01','US',55),('CMH-HUB-01','Cameroonian',12),('CMH-HUB-01','Nigerian',10),('CMH-HUB-01','Other African',10),('CMH-HUB-01','UK',5),('CMH-HUB-01','German',5),('CMH-HUB-01','Spanish',3),
    ('YYZ-HUB-01','US',10),('YYZ-HUB-01','Canadian',35),('YYZ-HUB-01','French',5),('YYZ-HUB-01','Cameroonian',20),('YYZ-HUB-01','Nigerian',15),('YYZ-HUB-01','Other African',10),('YYZ-HUB-01','UK',5),
    ('YUL-HUB-01','Canadian',20),('YUL-HUB-01','French',35),('YUL-HUB-01','Cameroonian',25),('YUL-HUB-01','Other African',10),('YUL-HUB-01','UK',5),('YUL-HUB-01','German',5),
    ('ORD-DEP-01','US',65),('ORD-DEP-01','Cameroonian',8),('ORD-DEP-01','Nigerian',10),('ORD-DEP-01','Other African',7),('ORD-DEP-01','UK',5),('ORD-DEP-01','German',3),('ORD-DEP-01','Spanish',2),
    ('JFK-DEP-01','US',50),('JFK-DEP-01','Cameroonian',8),('JFK-DEP-01','Nigerian',10),('JFK-DEP-01','Other African',7),('JFK-DEP-01','UK',10),('JFK-DEP-01','Spanish',15),
    ('ATL-DEP-01','US',70),('ATL-DEP-01','Cameroonian',8),('ATL-DEP-01','Nigerian',8),('ATL-DEP-01','Other African',7),('ATL-DEP-01','UK',5),('ATL-DEP-01','Spanish',2),
    ('DFW-DEP-01','US',55),('DFW-DEP-01','Cameroonian',5),('DFW-DEP-01','Nigerian',5),('DFW-DEP-01','Other African',5),('DFW-DEP-01','UK',5),('DFW-DEP-01','Spanish',25),
    ('LAX-DEP-01','US',45),('LAX-DEP-01','Cameroonian',5),('LAX-DEP-01','Nigerian',5),('LAX-DEP-01','Other African',5),('LAX-DEP-01','UK',5),('LAX-DEP-01','Spanish',35),
    ('YVR-DEP-01','US',10),('YVR-DEP-01','Canadian',40),('YVR-DEP-01','French',5),('YVR-DEP-01','Cameroonian',15),('YVR-DEP-01','Nigerian',10),('YVR-DEP-01','Other African',10),('YVR-DEP-01','UK',10),
    ('YYC-DEP-01','US',15),('YYC-DEP-01','Canadian',50),('YYC-DEP-01','Cameroonian',10),('YYC-DEP-01','Nigerian',5),('YYC-DEP-01','Other African',5),('YYC-DEP-01','UK',15),
    ('BOS-RET-01','US',65),('BOS-RET-01','Cameroonian',8),('BOS-RET-01','Nigerian',7),('BOS-RET-01','Other African',7),('BOS-RET-01','UK',13),
    ('MIA-RET-01','US',40),('MIA-RET-01','Cameroonian',5),('MIA-RET-01','Nigerian',5),('MIA-RET-01','Other African',5),('MIA-RET-01','Spanish',45),
    ('SEA-RET-01','US',55),('SEA-RET-01','Cameroonian',10),('SEA-RET-01','Nigerian',8),('SEA-RET-01','Other African',8),('SEA-RET-01','UK',10),('SEA-RET-01','German',9),
    ('YOW-RET-01','US',5),('YOW-RET-01','Canadian',40),('YOW-RET-01','French',20),('YOW-RET-01','Cameroonian',20),('YOW-RET-01','Other African',10),('YOW-RET-01','UK',5);

    -- Cumulative weight ranges per facility for weighted-random category pick
    IF OBJECT_ID('tempdb..#FacilityNameMixRanges') IS NOT NULL DROP TABLE #FacilityNameMixRanges;
    SELECT
        FacilityCode, OriginCategory, WeightPct,
        SUM(WeightPct) OVER (PARTITION BY FacilityCode ORDER BY OriginCategory ROWS UNBOUNDED PRECEDING) AS CumHigh,
        SUM(WeightPct) OVER (PARTITION BY FacilityCode ORDER BY OriginCategory ROWS UNBOUNDED PRECEDING) - WeightPct + 1 AS CumLow
    INTO #FacilityNameMixRanges
    FROM #FacilityNameMix;

    -- =====================================================================
    -- EMPLOYEE PLAN
    -- RoleLevel: 1 = Facility Manager, 2 = Supervisor (hubs only), 3 = Staff
    -- =====================================================================
    IF OBJECT_ID('tempdb..#EmpPlan') IS NOT NULL DROP TABLE #EmpPlan;
    SELECT
        ROW_NUMBER() OVER (ORDER BY fr.FacilityCode, t.n) AS GlobalSeq,
        fr.FacilityCode, t.n AS SlotNum, fr.TotalHeadcount, fr.DriverTarget, fr.SupervisorCount
    INTO #EmpPlan
    FROM #FacilityRoster fr
    JOIN #Tally t ON t.n <= fr.TotalHeadcount;

    ALTER TABLE #EmpPlan ADD RoleLevel TINYINT, JobTitle NVARCHAR(100), IsDriver BIT, OriginCategory NVARCHAR(30),
        NameRandIdx INT, HireDate DATE, TerminationDate DATE, WeightRoll INT;

    UPDATE #EmpPlan
    SET RoleLevel = CASE
        WHEN SlotNum = 1 THEN 1
        WHEN SlotNum <= 1 + SupervisorCount THEN 2
        ELSE 3 END;

    IF OBJECT_ID('tempdb..#StaffOrdinal') IS NOT NULL DROP TABLE #StaffOrdinal;
    SELECT GlobalSeq, ROW_NUMBER() OVER (PARTITION BY FacilityCode ORDER BY SlotNum) AS StaffSlotNum
    INTO #StaffOrdinal
    FROM #EmpPlan
    WHERE RoleLevel = 3;

    UPDATE ep
    SET IsDriver = CASE WHEN so.StaffSlotNum <= ep.DriverTarget THEN 1 ELSE 0 END
    FROM #EmpPlan ep
    JOIN #StaffOrdinal so ON so.GlobalSeq = ep.GlobalSeq;

    UPDATE #EmpPlan SET IsDriver = 0 WHERE IsDriver IS NULL;

    UPDATE #EmpPlan
    SET JobTitle = CASE
        WHEN RoleLevel = 1 THEN 'Facility Manager'
        WHEN RoleLevel = 2 THEN CASE WHEN ABS(CHECKSUM(NEWID())) % 2 = 0 THEN 'Operations Supervisor' ELSE 'Dispatch Supervisor' END
        WHEN RoleLevel = 3 AND IsDriver = 1 THEN CASE WHEN ABS(CHECKSUM(NEWID())) % 100 < 25 THEN 'Senior Driver' ELSE 'Driver' END
        ELSE 'Parcel Handler'
    END;

    UPDATE #EmpPlan
    SET JobTitle = CASE
        WHEN r < 35 THEN 'Parcel Handler'
        WHEN r < 55 THEN 'Freight Handler'
        WHEN r < 70 THEN 'Customer Service Representative'
        WHEN r < 80 THEN 'Billing Coordinator'
        WHEN r < 90 THEN 'IT Support Technician'
        ELSE 'Administrative Assistant'
    END
    FROM (SELECT GlobalSeq, ABS(CHECKSUM(NEWID())) % 100 AS r FROM #EmpPlan WHERE RoleLevel = 3 AND IsDriver = 0) x
    WHERE #EmpPlan.GlobalSeq = x.GlobalSeq;

    UPDATE #EmpPlan SET WeightRoll = ABS(CHECKSUM(NEWID())) % 100 + 1;

    UPDATE ep
    SET OriginCategory = mr.OriginCategory
    FROM #EmpPlan ep
    JOIN #FacilityNameMixRanges mr ON mr.FacilityCode = ep.FacilityCode AND ep.WeightRoll BETWEEN mr.CumLow AND mr.CumHigh;

    UPDATE ep
    SET NameRandIdx = (ABS(CHECKSUM(NEWID())) % nc.CatCount) + 1
    FROM #EmpPlan ep
    JOIN #NameBankCatCounts nc ON nc.origin_category = ep.OriginCategory;

    UPDATE #EmpPlan
    SET HireDate = CASE RoleLevel
        WHEN 1 THEN DATEADD(DAY, ABS(CHECKSUM(NEWID())) % 2190, '2016-01-01')
        WHEN 2 THEN DATEADD(DAY, ABS(CHECKSUM(NEWID())) % 2190, '2018-01-01')
        ELSE DATEADD(DAY, ABS(CHECKSUM(NEWID())) % 2707, '2019-01-01')
    END;

    UPDATE #EmpPlan
    SET TerminationDate = CASE
        WHEN HireDate <= '2025-01-01' AND ABS(CHECKSUM(NEWID())) % 100 < 6
            THEN (CASE WHEN DATEADD(DAY, 120 + ABS(CHECKSUM(NEWID())) % 450, HireDate) > @Today
                       THEN NULL
                       ELSE DATEADD(DAY, 120 + ABS(CHECKSUM(NEWID())) % 450, HireDate) END)
        ELSE NULL
    END;

    -- =====================================================================
    -- STAGE A: Facility Managers
    -- =====================================================================
    IF OBJECT_ID('tempdb..#ManagerResult') IS NOT NULL DROP TABLE #ManagerResult;
    CREATE TABLE #ManagerResult (FacilityCode NVARCHAR(10), EmployeeID INT);

    MERGE INTO dbo.Employees AS tgt
    USING (
        SELECT ep.FacilityCode, ep.JobTitle, ep.HireDate, ep.TerminationDate,
               nb.first_name, nb.last_name, fi.AreaCode, f.FacilityID
        FROM #EmpPlan ep
        JOIN #NameBankNumbered nb ON nb.origin_category = ep.OriginCategory AND nb.CatRowNum = ep.NameRandIdx
        JOIN #FacilityInfo fi ON fi.FacilityCode = ep.FacilityCode
        JOIN dbo.Facilities f ON f.FacilityCode = ep.FacilityCode
        WHERE ep.RoleLevel = 1
    ) AS src
    ON 1 = 0
    WHEN NOT MATCHED THEN
        INSERT (EmployeeNumber, FirstName, LastName, Email, Phone, FacilityID, ManagerEmployeeID, JobTitle, HireDate, TerminationDate,
                CreatedAt, CreatedBy, ModifiedAt, ModifiedBy)
        VALUES ('MGR-' + src.FacilityCode, src.first_name, src.last_name,
                LOWER(src.first_name) + '.' + LOWER(src.last_name) + '.' + LOWER(src.FacilityCode) + '@tarlogistics.com',
                '(' + src.AreaCode + ') ' + RIGHT('000' + CAST(ABS(CHECKSUM(NEWID())) % 1000 AS VARCHAR(3)), 3) + '-' + RIGHT('0000' + CAST(ABS(CHECKSUM(NEWID())) % 10000 AS VARCHAR(4)), 4),
                src.FacilityID, NULL, src.JobTitle, src.HireDate, src.TerminationDate,
                @SeedDate, @TarYuni, @SeedDate, @TarYuni)
    OUTPUT src.FacilityCode, inserted.EmployeeID
    INTO #ManagerResult (FacilityCode, EmployeeID);

    PRINT 'Facility Managers inserted: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    -- =====================================================================
    -- STAGE B: Supervisors (hubs only)
    -- =====================================================================
    IF OBJECT_ID('tempdb..#SupervisorResult') IS NOT NULL DROP TABLE #SupervisorResult;
    CREATE TABLE #SupervisorResult (FacilityCode NVARCHAR(10), SupervisorIdx INT, EmployeeID INT);

    MERGE INTO dbo.Employees AS tgt
    USING (
        SELECT ep.FacilityCode, ep.SlotNum - 1 AS SupervisorIdx, ep.JobTitle, ep.HireDate, ep.TerminationDate,
               nb.first_name, nb.last_name, fi.AreaCode, f.FacilityID, mr.EmployeeID AS ManagerEmployeeID
        FROM #EmpPlan ep
        JOIN #NameBankNumbered nb ON nb.origin_category = ep.OriginCategory AND nb.CatRowNum = ep.NameRandIdx
        JOIN #FacilityInfo fi ON fi.FacilityCode = ep.FacilityCode
        JOIN dbo.Facilities f ON f.FacilityCode = ep.FacilityCode
        JOIN #ManagerResult mr ON mr.FacilityCode = ep.FacilityCode
        WHERE ep.RoleLevel = 2
    ) AS src
    ON 1 = 0
    WHEN NOT MATCHED THEN
        INSERT (EmployeeNumber, FirstName, LastName, Email, Phone, FacilityID, ManagerEmployeeID, JobTitle, HireDate, TerminationDate,
                CreatedAt, CreatedBy, ModifiedAt, ModifiedBy)
        VALUES ('SUP-' + src.FacilityCode + '-' + CAST(src.SupervisorIdx AS VARCHAR(3)), src.first_name, src.last_name,
                LOWER(src.first_name) + '.' + LOWER(src.last_name) + '.' + LOWER(src.FacilityCode) + CAST(src.SupervisorIdx AS VARCHAR(3)) + '@tarlogistics.com',
                '(' + src.AreaCode + ') ' + RIGHT('000' + CAST(ABS(CHECKSUM(NEWID())) % 1000 AS VARCHAR(3)), 3) + '-' + RIGHT('0000' + CAST(ABS(CHECKSUM(NEWID())) % 10000 AS VARCHAR(4)), 4),
                src.FacilityID, src.ManagerEmployeeID, src.JobTitle, src.HireDate, src.TerminationDate,
                @SeedDate, @TarYuni, @SeedDate, @TarYuni)
    OUTPUT src.FacilityCode, src.SupervisorIdx, inserted.EmployeeID
    INTO #SupervisorResult (FacilityCode, SupervisorIdx, EmployeeID);

    PRINT 'Supervisors inserted: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    -- =====================================================================
    -- STAGE C: Staff
    -- =====================================================================
    IF OBJECT_ID('tempdb..#StaffPlan') IS NOT NULL DROP TABLE #StaffPlan;
    SELECT
        ep.GlobalSeq, ep.FacilityCode, ep.JobTitle, ep.HireDate, ep.TerminationDate, ep.SupervisorCount,
        nb.first_name, nb.last_name, fi.AreaCode, f.FacilityID, mr.EmployeeID AS ManagerEmployeeID,
        CASE WHEN ep.SupervisorCount > 0 AND ABS(CHECKSUM(NEWID())) % 100 < 70
             THEN (ABS(CHECKSUM(NEWID())) % ep.SupervisorCount) + 1
             ELSE NULL END AS SupervisorPickIdx
    INTO #StaffPlan
    FROM #EmpPlan ep
    JOIN #NameBankNumbered nb ON nb.origin_category = ep.OriginCategory AND nb.CatRowNum = ep.NameRandIdx
    JOIN #FacilityInfo fi ON fi.FacilityCode = ep.FacilityCode
    JOIN dbo.Facilities f ON f.FacilityCode = ep.FacilityCode
    JOIN #ManagerResult mr ON mr.FacilityCode = ep.FacilityCode
    WHERE ep.RoleLevel = 3;

    IF OBJECT_ID('tempdb..#StaffResult') IS NOT NULL DROP TABLE #StaffResult;
    CREATE TABLE #StaffResult (GlobalSeq INT, EmployeeID INT);

    MERGE INTO dbo.Employees AS tgt
    USING (
        SELECT sp.GlobalSeq, sp.JobTitle, sp.HireDate, sp.TerminationDate, sp.first_name, sp.last_name,
               sp.AreaCode, sp.FacilityID,
               COALESCE(sv.EmployeeID, sp.ManagerEmployeeID) AS ReportsTo
        FROM #StaffPlan sp
        LEFT JOIN #SupervisorResult sv ON sv.FacilityCode = sp.FacilityCode AND sv.SupervisorIdx = sp.SupervisorPickIdx
    ) AS src
    ON 1 = 0
    WHEN NOT MATCHED THEN
        INSERT (EmployeeNumber, FirstName, LastName, Email, Phone, FacilityID, ManagerEmployeeID, JobTitle, HireDate, TerminationDate,
                CreatedAt, CreatedBy, ModifiedAt, ModifiedBy)
        VALUES ('STF-' + CAST(src.GlobalSeq AS VARCHAR(10)), src.first_name, src.last_name,
                LOWER(src.first_name) + '.' + LOWER(src.last_name) + CAST(src.GlobalSeq AS VARCHAR(10)) + '@tarlogistics.com',
                '(' + src.AreaCode + ') ' + RIGHT('000' + CAST(ABS(CHECKSUM(NEWID())) % 1000 AS VARCHAR(3)), 3) + '-' + RIGHT('0000' + CAST(ABS(CHECKSUM(NEWID())) % 10000 AS VARCHAR(4)), 4),
                src.FacilityID, src.ReportsTo, src.JobTitle, src.HireDate, src.TerminationDate,
                @SeedDate, @TarYuni, @SeedDate, @TarYuni)
    OUTPUT src.GlobalSeq, inserted.EmployeeID
    INTO #StaffResult (GlobalSeq, EmployeeID);

    PRINT 'Staff inserted: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    UPDATE dbo.Employees
    SET EmployeeNumber = 'TL-EMP-' + RIGHT('00000' + CAST(EmployeeID AS VARCHAR(10)), 5);

    PRINT 'EmployeeNumbers assigned: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    -- =====================================================================
    -- DRIVERS
    -- =====================================================================
    IF OBJECT_ID('tempdb..#DriverCandidates') IS NOT NULL DROP TABLE #DriverCandidates;
    SELECT e.EmployeeID, f.FacilityCode, fi.StateProvince, fi.CountryCode, fi.FacilityType
    INTO #DriverCandidates
    FROM dbo.Employees e
    JOIN dbo.Facilities f ON f.FacilityID = e.FacilityID
    JOIN #FacilityInfo fi ON fi.FacilityCode = f.FacilityCode
    WHERE e.JobTitle IN ('Senior Driver', 'Driver');

    INSERT INTO dbo.Drivers (EmployeeID, LicenseClass, LicenseNumber, LicenseExpiry, LicenseState,
                              CreatedAt, CreatedBy, ModifiedAt, ModifiedBy)
    SELECT
        dc.EmployeeID,
        CASE
            WHEN dc.FacilityType = 'Hub'   THEN CASE WHEN ABS(CHECKSUM(NEWID())) % 100 < 70 THEN 'CDL-A' ELSE 'CDL-B' END
            WHEN dc.FacilityType = 'Depot' THEN CASE WHEN ABS(CHECKSUM(NEWID())) % 100 < 50 THEN 'CDL-A' ELSE 'CDL-B' END
            ELSE 'Class-G'
        END,
        'DL' + RIGHT('00000000' + CAST(ABS(CHECKSUM(NEWID())) % 100000000 AS VARCHAR(8)), 8),
        DATEADD(DAY, 200 + ABS(CHECKSUM(NEWID())) % 1400, @Today),
        dc.StateProvince,
        @SeedDate, @TarYuni, @SeedDate, @TarYuni
    FROM #DriverCandidates dc;

    PRINT 'Drivers inserted: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    -- =====================================================================
    -- VEHICLES (~200 total, distributed per facility)
    -- =====================================================================
    IF OBJECT_ID('tempdb..#VehiclePlan') IS NOT NULL DROP TABLE #VehiclePlan;
    SELECT fr.FacilityCode, t.n AS VehicleSlot, fi.FacilityType, fi.StateProvince
    INTO #VehiclePlan
    FROM #FacilityRoster fr
    JOIN #FacilityInfo fi ON fi.FacilityCode = fr.FacilityCode
    JOIN #Tally t ON t.n <= fr.VehicleCount;

    INSERT INTO dbo.Vehicles (LicensePlate, LicensePlateState, VehicleType, CapacityClass, MaxPayloadKg,
                               HomeBaseFacilityID, VehicleStatus, Year, Make, Model,
                               CreatedAt, CreatedBy, ModifiedAt, ModifiedBy)
    SELECT
        UPPER(LEFT(vp.FacilityCode, 3)) + '-' + RIGHT('00' + CAST(vp.VehicleSlot AS VARCHAR(2)), 2) + RIGHT('00' + CAST(ABS(CHECKSUM(NEWID())) % 100 AS VARCHAR(2)), 2),
        vp.StateProvince,
        vt.VehicleType, vt.CapacityClass, vt.MaxPayloadKg,
        f.FacilityID,
        CASE WHEN ABS(CHECKSUM(NEWID())) % 100 < 80 THEN 'Available'
             WHEN ABS(CHECKSUM(NEWID())) % 100 < 93 THEN 'In Use'
             WHEN ABS(CHECKSUM(NEWID())) % 100 < 98 THEN 'Maintenance'
             ELSE 'Retired' END,
        2015 + ABS(CHECKSUM(NEWID())) % 11,
        mk.Make, mk.Model,
        @SeedDate, @TarYuni, @SeedDate, @TarYuni
    FROM #VehiclePlan vp
    JOIN dbo.Facilities f ON f.FacilityCode = vp.FacilityCode
    CROSS APPLY (
        SELECT
            CASE
                WHEN vp.FacilityType = 'Hub' THEN
                    CASE WHEN ABS(CHECKSUM(NEWID())) % 100 < 45 THEN 'Semi'
                         WHEN ABS(CHECKSUM(NEWID())) % 100 < 80 THEN 'Box Truck'
                         WHEN ABS(CHECKSUM(NEWID())) % 100 < 92 THEN 'Refrigerated'
                         ELSE 'Flatbed' END
                WHEN vp.FacilityType = 'Depot' THEN
                    CASE WHEN ABS(CHECKSUM(NEWID())) % 100 < 55 THEN 'Box Truck'
                         WHEN ABS(CHECKSUM(NEWID())) % 100 < 90 THEN 'Cargo Van'
                         ELSE 'Refrigerated' END
                ELSE 'Cargo Van'
            END AS VehicleType
    ) vtype
    CROSS APPLY (
        SELECT
            CASE vtype.VehicleType WHEN 'Semi' THEN 'Heavy' WHEN 'Flatbed' THEN 'Heavy'
                 WHEN 'Box Truck' THEN 'Medium' WHEN 'Refrigerated' THEN 'Medium' ELSE 'Light' END AS CapacityClass,
            CASE vtype.VehicleType
                WHEN 'Semi' THEN CAST(15000 + ABS(CHECKSUM(NEWID())) % 10000 AS DECIMAL(10,2))
                WHEN 'Flatbed' THEN CAST(12000 + ABS(CHECKSUM(NEWID())) % 8000 AS DECIMAL(10,2))
                WHEN 'Box Truck' THEN CAST(2000 + ABS(CHECKSUM(NEWID())) % 4000 AS DECIMAL(10,2))
                WHEN 'Refrigerated' THEN CAST(2500 + ABS(CHECKSUM(NEWID())) % 3500 AS DECIMAL(10,2))
                ELSE CAST(500 + ABS(CHECKSUM(NEWID())) % 1000 AS DECIMAL(10,2))
            END AS MaxPayloadKg,
            vtype.VehicleType
    ) vt
    CROSS APPLY (
        SELECT
            CASE vt.VehicleType
                WHEN 'Semi' THEN CASE ABS(CHECKSUM(NEWID())) % 3 WHEN 0 THEN 'Freightliner' WHEN 1 THEN 'Peterbilt' ELSE 'Kenworth' END
                WHEN 'Flatbed' THEN CASE ABS(CHECKSUM(NEWID())) % 2 WHEN 0 THEN 'Peterbilt' ELSE 'Volvo' END
                WHEN 'Box Truck' THEN CASE ABS(CHECKSUM(NEWID())) % 3 WHEN 0 THEN 'International' WHEN 1 THEN 'Isuzu' ELSE 'Freightliner' END
                WHEN 'Refrigerated' THEN CASE ABS(CHECKSUM(NEWID())) % 2 WHEN 0 THEN 'Isuzu' ELSE 'International' END
                ELSE CASE ABS(CHECKSUM(NEWID())) % 2 WHEN 0 THEN 'Ford' ELSE 'Mercedes-Benz' END
            END AS Make,
            CASE vt.VehicleType
                WHEN 'Semi' THEN 'Cascadia' WHEN 'Flatbed' THEN 'Flatbed 48ft' WHEN 'Box Truck' THEN 'MT45'
                WHEN 'Refrigerated' THEN 'NRR Reefer'
                ELSE CASE ABS(CHECKSUM(NEWID())) % 2 WHEN 0 THEN 'Transit' ELSE 'Sprinter' END
            END AS Model
    ) mk;

    PRINT 'Vehicles inserted: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    -- =====================================================================
    -- ASSIGNMENTS (~3 per route, drawn from facility-matched drivers/vehicles)
    -- =====================================================================
    IF OBJECT_ID('tempdb..#DriversByFacility') IS NOT NULL DROP TABLE #DriversByFacility;
    SELECT d.EmployeeID, e.FacilityID,
           ROW_NUMBER() OVER (PARTITION BY e.FacilityID ORDER BY d.EmployeeID) AS RowInFacility
    INTO #DriversByFacility
    FROM dbo.Drivers d
    JOIN dbo.Employees e ON e.EmployeeID = d.EmployeeID;

    IF OBJECT_ID('tempdb..#DriverCountByFacility') IS NOT NULL DROP TABLE #DriverCountByFacility;
    SELECT FacilityID, COUNT(*) AS Cnt INTO #DriverCountByFacility FROM #DriversByFacility GROUP BY FacilityID;

    IF OBJECT_ID('tempdb..#VehiclesByFacility') IS NOT NULL DROP TABLE #VehiclesByFacility;
    SELECT v.VehicleID, v.HomeBaseFacilityID,
           ROW_NUMBER() OVER (PARTITION BY v.HomeBaseFacilityID ORDER BY v.VehicleID) AS RowInFacility
    INTO #VehiclesByFacility
    FROM dbo.Vehicles v;

    IF OBJECT_ID('tempdb..#VehicleCountByFacility') IS NOT NULL DROP TABLE #VehicleCountByFacility;
    SELECT HomeBaseFacilityID, COUNT(*) AS Cnt INTO #VehicleCountByFacility FROM #VehiclesByFacility GROUP BY HomeBaseFacilityID;

    IF OBJECT_ID('tempdb..#AssignPlan') IS NOT NULL DROP TABLE #AssignPlan;
    SELECT r.RouteID, r.OriginFacilityID, t.n AS AssignSlot
    INTO #AssignPlan
    FROM dbo.Routes r
    JOIN #Tally t ON t.n <= 3;

    ALTER TABLE #AssignPlan ADD DriverPickIdx INT, VehiclePickIdx INT, DriverEmployeeID INT, VehicleID INT, AssignmentDate DATE, ShiftStartHour INT;

    UPDATE ap
    SET DriverPickIdx  = (ABS(CHECKSUM(NEWID())) % dc.Cnt) + 1,
        VehiclePickIdx = (ABS(CHECKSUM(NEWID())) % vc.Cnt) + 1
    FROM #AssignPlan ap
    JOIN #DriverCountByFacility dc ON dc.FacilityID = ap.OriginFacilityID
    JOIN #VehicleCountByFacility vc ON vc.HomeBaseFacilityID = ap.OriginFacilityID;

    UPDATE ap
    SET DriverEmployeeID = db.EmployeeID
    FROM #AssignPlan ap
    JOIN #DriversByFacility db ON db.FacilityID = ap.OriginFacilityID AND db.RowInFacility = ap.DriverPickIdx;

    UPDATE ap
    SET VehicleID = vb.VehicleID
    FROM #AssignPlan ap
    JOIN #VehiclesByFacility vb ON vb.HomeBaseFacilityID = ap.OriginFacilityID AND vb.RowInFacility = ap.VehiclePickIdx;

    UPDATE #AssignPlan
    SET AssignmentDate = DATEADD(DAY, ABS(CHECKSUM(NEWID())) % 930, '2024-01-01'),
        ShiftStartHour = 5 + ABS(CHECKSUM(NEWID())) % 10;

    DELETE FROM #AssignPlan WHERE DriverEmployeeID IS NULL OR VehicleID IS NULL;

    INSERT INTO dbo.Assignments (DriverID, VehicleID, RouteID, AssignmentDate, ShiftStart, ShiftEnd, AssignmentStatus, Notes,
                                  CreatedAt, CreatedBy, ModifiedAt, ModifiedBy)
    SELECT
        ap.DriverEmployeeID, ap.VehicleID, ap.RouteID, ap.AssignmentDate,
        CAST(RIGHT('0' + CAST(ap.ShiftStartHour AS VARCHAR(2)), 2) + ':00:00' AS TIME(0)),
        CAST(RIGHT('0' + CAST(ap.ShiftStartHour + 8 AS VARCHAR(2)), 2) + ':00:00' AS TIME(0)),
        CASE WHEN ap.AssignmentDate >= @Today THEN 'Scheduled'
             WHEN ABS(CHECKSUM(NEWID())) % 100 < 92 THEN 'Completed'
             ELSE 'Cancelled' END,
        NULL,
        CAST(ap.AssignmentDate AS DATETIME2(7)), @TarYuni, CAST(ap.AssignmentDate AS DATETIME2(7)), @TarYuni
    FROM #AssignPlan ap;

    PRINT 'Assignments inserted: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    COMMIT TRANSACTION;
    PRINT '03-hr.sql completed successfully.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
    DECLARE @ErrSeverity INT = ERROR_SEVERITY();
    DECLARE @ErrState INT = ERROR_STATE();
    RAISERROR('03-hr.sql failed: %s', @ErrSeverity, @ErrState, @ErrMsg);
END CATCH
GO
