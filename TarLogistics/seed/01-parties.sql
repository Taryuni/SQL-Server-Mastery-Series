-- =============================================================================
-- 01-parties.sql
-- Cluster 1: Addresses, Customers, BusinessAccounts, BusinessContacts,
--            BusinessAccountAddresses
-- =============================================================================
-- Audit columns (CreatedAt/ModifiedAt/CreatedBy/ModifiedBy) are stamped with a
-- fixed seed timestamp/user rather than SYSUTCDATETIME()/SYSTEM_USER so reruns
-- are reproducible and do not depend on when the script happens to execute.
-- Business/event dates (HireDate, ShipmentCreatedAt, etc., in later files)
-- carry the real historical spread instead.
--
-- Random-pick technique: SQL Server can (and on this engine build, does) cache
-- the result of a correlated "TOP 1 ... ORDER BY NEWID()" subquery — whether
-- via CROSS APPLY or an inline scalar subquery — and replay the SAME row for
-- every outer row sharing the same correlation key, instead of re-rolling per
-- row. Every random pick in this file is therefore done in two deterministic
-- steps: (1) materialize a random index with ABS(CHECKSUM(NEWID())) % N
-- directly in an UPDATE...SET (a plain per-row expression, not a subquery —
-- reliably re-evaluated per row), then (2) JOIN to a numbered reference table
-- on that already-materialized index. Never "ORDER BY NEWID()" inside a
-- subquery/APPLY in this series of scripts.
--
-- NOTE: This file requires a companion name-bank CSV file.
-- Update the BULK INSERT path below to match where you have placed
-- tar-logistics-name-bank.csv on your machine.
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

    -- -------------------------------------------------------------------
    -- Name bank: load once, filter by origin_category throughout this file
    -- Update this path to match your local copy of tar-logistics-name-bank.csv
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
        first_name, last_name, origin_category,
        ROW_NUMBER() OVER (PARTITION BY origin_category ORDER BY (SELECT NULL)) AS CatRowNum
    INTO #NameBankNumbered
    FROM #NameBank;
    CREATE CLUSTERED INDEX IX_NBN ON #NameBankNumbered (origin_category, CatRowNum);

    -- -------------------------------------------------------------------
    -- Tally: general-purpose row generator
    -- -------------------------------------------------------------------
    IF OBJECT_ID('tempdb..#Tally') IS NOT NULL DROP TABLE #Tally;
    ;WITH T(n) AS (
        SELECT TOP (20000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
        FROM sys.all_objects a CROSS JOIN sys.all_objects b
    )
    SELECT n INTO #Tally FROM T;
    CREATE UNIQUE CLUSTERED INDEX IX_Tally ON #Tally (n);

    -- -------------------------------------------------------------------
    -- Real city / state / postal-code reference pool (US + Canada)
    -- -------------------------------------------------------------------
    IF OBJECT_ID('tempdb..#CityRef') IS NOT NULL DROP TABLE #CityRef;
    CREATE TABLE #CityRef (
        City            NVARCHAR(100),
        StateProvince   NVARCHAR(100),
        CountryCode     CHAR(2),
        ZipBase         NVARCHAR(10),
        AreaCode        NVARCHAR(3)
    );
    INSERT INTO #CityRef (City, StateProvince, CountryCode, ZipBase, AreaCode) VALUES
    -- US-NE
    ('Boston','MA','US','021','617'), ('Worcester','MA','US','016','508'),
    ('Hartford','CT','US','061','860'), ('New Haven','CT','US','065','203'),
    ('Providence','RI','US','029','401'), ('Manchester','NH','US','031','603'),
    ('Portland','ME','US','041','207'), ('Burlington','VT','US','054','802'),
    ('Newark','NJ','US','071','973'), ('Jersey City','NJ','US','073','201'),
    ('New York','NY','US','100','212'), ('Buffalo','NY','US','142','716'),
    ('Rochester','NY','US','146','585'), ('Philadelphia','PA','US','191','215'),
    ('Pittsburgh','PA','US','152','412'),
    -- US-SE
    ('Atlanta','GA','US','303','404'), ('Savannah','GA','US','314','912'),
    ('Miami','FL','US','331','305'), ('Orlando','FL','US','328','407'),
    ('Tampa','FL','US','336','813'), ('Jacksonville','FL','US','322','904'),
    ('Charlotte','NC','US','282','704'), ('Raleigh','NC','US','276','919'),
    ('Charleston','SC','US','294','843'), ('Columbia','SC','US','292','803'),
    ('Nashville','TN','US','372','615'), ('Memphis','TN','US','381','901'),
    ('Richmond','VA','US','232','804'), ('Norfolk','VA','US','235','757'),
    ('Birmingham','AL','US','352','205'), ('Jackson','MS','US','392','601'),
    -- US-MW
    ('Chicago','IL','US','606','312'), ('Springfield','IL','US','627','217'),
    ('Indianapolis','IN','US','462','317'), ('Louisville','KY','US','402','502'),
    ('Detroit','MI','US','482','313'), ('Grand Rapids','MI','US','495','616'),
    ('Minneapolis','MN','US','554','612'), ('Saint Paul','MN','US','551','651'),
    ('Kansas City','MO','US','641','816'), ('Saint Louis','MO','US','631','314'),
    ('Columbus','OH','US','432','614'), ('Cleveland','OH','US','441','216'),
    ('Cincinnati','OH','US','452','513'), ('Milwaukee','WI','US','532','414'),
    ('Charleston','WV','US','253','304'),
    -- US-SC
    ('Little Rock','AR','US','722','501'), ('New Orleans','LA','US','701','504'),
    ('Baton Rouge','LA','US','708','225'), ('Oklahoma City','OK','US','731','405'),
    ('Tulsa','OK','US','741','918'), ('Dallas','TX','US','752','214'),
    ('Houston','TX','US','770','713'), ('Austin','TX','US','787','512'),
    ('San Antonio','TX','US','782','210'), ('Fort Worth','TX','US','761','817'),
    -- US-WC
    ('Phoenix','AZ','US','850','602'), ('Tucson','AZ','US','857','520'),
    ('Los Angeles','CA','US','900','213'), ('San Diego','CA','US','921','619'),
    ('San Francisco','CA','US','941','415'), ('Sacramento','CA','US','958','916'),
    ('Oakland','CA','US','946','510'), ('Las Vegas','NV','US','891','702'),
    ('Reno','NV','US','895','775'), ('Portland','OR','US','972','503'),
    ('Eugene','OR','US','974','541'), ('Seattle','WA','US','981','206'),
    ('Spokane','WA','US','992','509'), ('Tacoma','WA','US','984','253'),
    -- US-MT
    ('Denver','CO','US','802','303'), ('Colorado Springs','CO','US','809','719'),
    ('Boise','ID','US','837','208'), ('Billings','MT','US','591','406'),
    ('Missoula','MT','US','598','406'), ('Albuquerque','NM','US','871','505'),
    ('Santa Fe','NM','US','875','505'), ('Salt Lake City','UT','US','841','801'),
    ('Cheyenne','WY','US','820','307'),
    -- CA-ON
    ('Toronto','ON','CA','M5H','416'), ('Ottawa','ON','CA','K1A','613'),
    ('Mississauga','ON','CA','L5B','905'), ('Hamilton','ON','CA','L8P','905'),
    ('London','ON','CA','N6A','519'), ('Kingston','ON','CA','K7L','613'),
    -- CA-QC
    ('Montreal','QC','CA','H2X','514'), ('Quebec City','QC','CA','G1R','418'),
    ('Halifax','NS','CA','B3H','902'), ('Saint John','NB','CA','E3B','506'),
    ('Moncton','NB','CA','E1C','506'), ('St. John''s','NL','CA','A1C','709'),
    -- CA-WC
    ('Vancouver','BC','CA','V6B','604'), ('Victoria','BC','CA','V8W','250'),
    ('Calgary','AB','CA','T2P','403'), ('Edmonton','AB','CA','T5J','780'),
    ('Winnipeg','MB','CA','R3B','204'), ('Saskatoon','SK','CA','S7K','306');

    IF OBJECT_ID('tempdb..#CityRefNumbered') IS NOT NULL DROP TABLE #CityRefNumbered;
    SELECT
        City, StateProvince, CountryCode, ZipBase, AreaCode,
        ROW_NUMBER() OVER (PARTITION BY CountryCode ORDER BY (SELECT NULL)) AS CountryRowNum
    INTO #CityRefNumbered
    FROM #CityRef;
    CREATE CLUSTERED INDEX IX_CRN ON #CityRefNumbered (CountryCode, CountryRowNum);

    IF OBJECT_ID('tempdb..#CityRefCounts') IS NOT NULL DROP TABLE #CityRefCounts;
    SELECT CountryCode, COUNT(*) AS CountryCount
    INTO #CityRefCounts
    FROM #CityRef
    GROUP BY CountryCode;

    IF OBJECT_ID('tempdb..#StreetNames') IS NOT NULL DROP TABLE #StreetNames;
    SELECT StreetName, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS RowNum
    INTO #StreetNames
    FROM (VALUES
        ('Main St'),('Oak Ave'),('Maple St'),('Elm St'),('Washington Ave'),
        ('Park Rd'),('Lincoln Ave'),('Jefferson St'),('Madison Ave'),('Cedar Ln'),
        ('Pine St'),('Birch Rd'),('Willow Ave'),('Sunset Blvd'),('River Rd'),
        ('Highland Ave'),('Church St'),('Mill St'),('King St'),('Queen St'),
        ('Victoria Ave'),('Bay St'),('Front St'),('Water St'),('Broadway'),
        ('1st Ave'),('2nd St'),('5th Ave'),('Industrial Pkwy'),('Commerce Dr'),
        ('Grand Ave'),('Franklin St'),('Adams St'),('Jackson Blvd'),('Union St'),
        ('Spring St'),('Chestnut St'),('Walnut St'),('Ridge Rd'),('Valley Rd')
    ) x(StreetName);
    DECLARE @StreetCount INT = 40;

    IF OBJECT_ID('tempdb..#BizNameParts') IS NOT NULL DROP TABLE #BizNameParts;
    SELECT Part, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS RowNum
    INTO #BizNameParts
    FROM (VALUES
        ('Summit'),('Cascade'),('Harbor'),('Northgate'),('Prairie'),('Lakeside'),('Crescent'),
        ('Ironwood'),('Redwood'),('Meridian'),('Vanguard'),('Beacon'),('Cornerstone'),('Foothill'),
        ('Riverside'),('Timberline'),('Sterling'),('Frontier'),('Maple Leaf'),('Granite'),
        ('Pinnacle'),('Crestview'),('Anchor'),('Bridgeway'),('Coastal'),('Highland'),('Union'),
        ('Keystone'),('Silverline'),('Northstar')
    ) x(Part);
    DECLARE @PartCount INT = 30;

    IF OBJECT_ID('tempdb..#BizNameSuffix') IS NOT NULL DROP TABLE #BizNameSuffix;
    SELECT Suffix, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS RowNum
    INTO #BizNameSuffix
    FROM (VALUES
        ('Manufacturing'),('Distribution'),('Logistics'),('Wholesale'),('Trading Co.'),('Supply Co.'),
        ('Industries'),('Foods'),('Textiles'),('Electronics'),('Hardware'),('Furnishings'),
        ('Pharmaceuticals'),('Auto Parts'),('Building Supply'),('Print & Packaging'),('Retail Group'),
        ('Import-Export'),('Materials'),('Components')
    ) x(Suffix);
    DECLARE @SuffixCount INT = 20;

    IF OBJECT_ID('tempdb..#JobTitlesBC') IS NOT NULL DROP TABLE #JobTitlesBC;
    SELECT JobTitle, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS RowNum
    INTO #JobTitlesBC
    FROM (VALUES
        ('Shipping Manager'),('Logistics Coordinator'),('Accounts Payable Clerk'),
        ('Office Manager'),('Procurement Manager'),('Operations Director'),
        ('Warehouse Supervisor'),('Owner')
    ) x(JobTitle);
    DECLARE @JobTitleCount INT = 8;

    -- =====================================================================
    -- CUSTOMERS  (target 1,500 -> 900 US / 600 Canadian)
    -- =====================================================================
    IF OBJECT_ID('tempdb..#CustomerPlan') IS NOT NULL DROP TABLE #CustomerPlan;
    SELECT
        t.n                                                                AS SeqNum,
        CASE WHEN t.n <= 900 THEN 'US' ELSE 'CA' END                       AS CustCountry,
        CAST(NULL AS NVARCHAR(30))                                         AS OriginCategory,
        CAST(NULL AS INT)                                                  AS NameRandIdx,
        CAST(NULL AS INT)                                                  AS PhoneCityRandIdx,
        CAST(NULL AS INT)                                                  AS AddrCityRandIdx,
        (ABS(CHECKSUM(NEWID())) % @StreetCount) + 1                        AS StreetRandIdx
    INTO #CustomerPlan
    FROM #Tally t
    WHERE t.n <= 1500;

    UPDATE #CustomerPlan
    SET OriginCategory = CASE
        WHEN r <= 75 THEN 'US'
        WHEN r <= 78 THEN 'Cameroonian'
        WHEN r <= 83 THEN 'Nigerian'
        WHEN r <= 88 THEN 'Other African'
        WHEN r <= 91 THEN 'UK'
        ELSE 'Spanish'
    END
    FROM (SELECT SeqNum, ABS(CHECKSUM(NEWID())) % 100 + 1 AS r FROM #CustomerPlan WHERE CustCountry = 'US') x
    WHERE #CustomerPlan.SeqNum = x.SeqNum;

    UPDATE #CustomerPlan
    SET OriginCategory = CASE
        WHEN r <= 55 THEN 'Canadian'
        WHEN r <= 75 THEN 'French'
        WHEN r <= 85 THEN 'Cameroonian'
        WHEN r <= 95 THEN 'Other African'
        ELSE 'UK'
    END
    FROM (SELECT SeqNum, ABS(CHECKSUM(NEWID())) % 100 + 1 AS r FROM #CustomerPlan WHERE CustCountry = 'CA') x
    WHERE #CustomerPlan.SeqNum = x.SeqNum;

    UPDATE cp
    SET NameRandIdx      = (ABS(CHECKSUM(NEWID())) % nc.CatCount) + 1,
        PhoneCityRandIdx = (ABS(CHECKSUM(NEWID())) % cc.CountryCount) + 1,
        AddrCityRandIdx  = (ABS(CHECKSUM(NEWID())) % cc.CountryCount) + 1
    FROM #CustomerPlan cp
    JOIN #NameBankCatCounts nc ON nc.origin_category = cp.OriginCategory
    JOIN #CityRefCounts cc ON cc.CountryCode = cp.CustCountry;

    INSERT INTO dbo.Customers (FirstName, LastName, Email, Phone, CreatedAt, CreatedBy, ModifiedAt, ModifiedBy)
    SELECT
        nb.first_name,
        nb.last_name,
        LOWER(nb.first_name) + '.' + LOWER(nb.last_name) + CAST(p.SeqNum AS VARCHAR(10)) +
            CASE ABS(CHECKSUM(NEWID())) % 5
                WHEN 0 THEN '@gmail.com' WHEN 1 THEN '@yahoo.com' WHEN 2 THEN '@outlook.com'
                WHEN 3 THEN '@hotmail.com' ELSE '@icloud.com' END,
        CASE WHEN ABS(CHECKSUM(NEWID())) % 100 < 85
             THEN '(' + pc.AreaCode + ') ' + RIGHT('000' + CAST(ABS(CHECKSUM(NEWID())) % 1000 AS VARCHAR(3)), 3) + '-' + RIGHT('0000' + CAST(ABS(CHECKSUM(NEWID())) % 10000 AS VARCHAR(4)), 4)
             ELSE NULL END,
        @SeedDate, @TarYuni, @SeedDate, @TarYuni
    FROM #CustomerPlan p
    JOIN #NameBankNumbered nb ON nb.origin_category = p.OriginCategory AND nb.CatRowNum = p.NameRandIdx
    JOIN #CityRefNumbered pc ON pc.CountryCode = p.CustCountry AND pc.CountryRowNum = p.PhoneCityRandIdx
    ORDER BY p.SeqNum;

    PRINT 'Customers inserted: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    INSERT INTO dbo.Addresses (AddressLine1, AddressLine2, City, StateProvince, PostalCode, CountryCode,
                                CreatedAt, CreatedBy, ModifiedAt, ModifiedBy)
    SELECT
        CAST(ABS(CHECKSUM(NEWID())) % 9899 + 100 AS VARCHAR(5)) + ' ' + sn.StreetName,
        CASE WHEN ABS(CHECKSUM(NEWID())) % 100 < 25 THEN 'Apt ' + CAST(ABS(CHECKSUM(NEWID())) % 400 + 1 AS VARCHAR(4)) ELSE NULL END,
        ac.City, ac.StateProvince,
        CASE WHEN p.CustCountry = 'US'
             THEN ac.ZipBase + RIGHT('00' + CAST(ABS(CHECKSUM(NEWID())) % 100 AS VARCHAR(2)), 2)
             ELSE ac.ZipBase + ' ' + CHAR(65 + ABS(CHECKSUM(NEWID())) % 26) + CAST(ABS(CHECKSUM(NEWID())) % 10 AS VARCHAR(1)) + CHAR(65 + ABS(CHECKSUM(NEWID())) % 26)
        END,
        p.CustCountry,
        @SeedDate, @TarYuni, @SeedDate, @TarYuni
    FROM #CustomerPlan p
    JOIN #CityRefNumbered ac ON ac.CountryCode = p.CustCountry AND ac.CountryRowNum = p.AddrCityRandIdx
    JOIN #StreetNames sn ON sn.RowNum = p.StreetRandIdx
    ORDER BY p.SeqNum;

    PRINT 'Customer-pool Addresses inserted: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    -- =====================================================================
    -- BUSINESS ACCOUNTS (target 250 -> 150 US / 100 Canadian)
    -- =====================================================================
    IF OBJECT_ID('tempdb..#BAPlan') IS NOT NULL DROP TABLE #BAPlan;
    SELECT
        t.n AS SeqNum,
        CASE WHEN t.n <= 150 THEN 'US' ELSE 'CA' END AS AcctCountry,
        (ABS(CHECKSUM(NEWID())) % @PartCount) + 1     AS PartRandIdx,
        (ABS(CHECKSUM(NEWID())) % @SuffixCount) + 1   AS SuffixRandIdx
    INTO #BAPlan
    FROM #Tally t
    WHERE t.n <= 250;

    INSERT INTO dbo.BusinessAccounts (AccountName, TaxID, CreditLimit, CreditLimitCurrency, PaymentTermsDays, AccountStatus,
                                       CreatedAt, CreatedBy, ModifiedAt, ModifiedBy)
    SELECT
        np.Part + ' ' + ns.Suffix,
        CASE WHEN p.AcctCountry = 'US'
             THEN RIGHT('00' + CAST(ABS(CHECKSUM(NEWID())) % 100 AS VARCHAR(2)), 2) + '-' + RIGHT('0000000' + CAST(ABS(CHECKSUM(NEWID())) % 10000000 AS VARCHAR(7)), 7)
             ELSE CAST(ABS(CHECKSUM(NEWID())) % 900000000 + 100000000 AS VARCHAR(9)) + 'RC0001'
        END,
        CASE WHEN ABS(CHECKSUM(NEWID())) % 100 < 80
             THEN CAST((ABS(CHECKSUM(NEWID())) % 480 + 20) * 500 AS DECIMAL(12,2))
             ELSE NULL END,
        CASE WHEN p.AcctCountry = 'US' THEN 'USD' ELSE 'CAD' END,
        CASE ABS(CHECKSUM(NEWID())) % 8
            WHEN 0 THEN 0 WHEN 1 THEN 15 WHEN 2 THEN 30 WHEN 3 THEN 30
            WHEN 4 THEN 30 WHEN 5 THEN 45 WHEN 6 THEN 60 ELSE 90 END,
        CASE WHEN ABS(CHECKSUM(NEWID())) % 11 = 9 THEN 'Suspended'
             WHEN ABS(CHECKSUM(NEWID())) % 11 = 10 THEN 'Closed'
             ELSE 'Active' END,
        @SeedDate, @TarYuni, @SeedDate, @TarYuni
    FROM #BAPlan p
    JOIN #BizNameParts np ON np.RowNum = p.PartRandIdx
    JOIN #BizNameSuffix ns ON ns.RowNum = p.SuffixRandIdx
    ORDER BY p.SeqNum;

    PRINT 'BusinessAccounts inserted: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    IF OBJECT_ID('tempdb..#BAMap') IS NOT NULL DROP TABLE #BAMap;
    SELECT
        ba.BusinessAccountID,
        p.AcctCountry,
        CAST(NULL AS INT) AS ContactCount,
        CAST(NULL AS INT) AS RoleCount
    INTO #BAMap
    FROM dbo.BusinessAccounts ba
    JOIN (SELECT BusinessAccountID, ROW_NUMBER() OVER (ORDER BY BusinessAccountID) AS rn FROM dbo.BusinessAccounts) r
        ON r.BusinessAccountID = ba.BusinessAccountID
    JOIN #BAPlan p ON p.SeqNum = r.rn;

    UPDATE #BAMap
    SET ContactCount = CASE WHEN ABS(CHECKSUM(NEWID())) % 100 < 50 THEN 2 ELSE 3 END,
        RoleCount    = CASE WHEN ABS(CHECKSUM(NEWID())) % 100 < 60 THEN 1 ELSE 2 END;

    -- =====================================================================
    -- BUSINESS CONTACTS (target ~600, 2-3 per account)
    -- =====================================================================
    IF OBJECT_ID('tempdb..#ContactPlan') IS NOT NULL DROP TABLE #ContactPlan;
    SELECT
        m.BusinessAccountID,
        m.AcctCountry,
        t.n AS ContactNum,
        CAST(NULL AS NVARCHAR(30)) AS OriginCategory,
        CAST(NULL AS INT) AS NameRandIdx,
        CAST(NULL AS INT) AS PhoneCityRandIdx,
        (ABS(CHECKSUM(NEWID())) % @JobTitleCount) + 1 AS JobRandIdx
    INTO #ContactPlan
    FROM #BAMap m
    JOIN #Tally t ON t.n <= m.ContactCount;

    UPDATE #ContactPlan
    SET OriginCategory = CASE
        WHEN r <= 75 THEN 'US' WHEN r <= 78 THEN 'Cameroonian' WHEN r <= 83 THEN 'Nigerian'
        WHEN r <= 88 THEN 'Other African' WHEN r <= 91 THEN 'UK' ELSE 'Spanish' END
    FROM (SELECT BusinessAccountID, ContactNum, ABS(CHECKSUM(NEWID())) % 100 + 1 AS r FROM #ContactPlan WHERE AcctCountry = 'US') x
    WHERE #ContactPlan.BusinessAccountID = x.BusinessAccountID AND #ContactPlan.ContactNum = x.ContactNum;

    UPDATE #ContactPlan
    SET OriginCategory = CASE
        WHEN r <= 55 THEN 'Canadian' WHEN r <= 75 THEN 'French' WHEN r <= 85 THEN 'Cameroonian'
        WHEN r <= 95 THEN 'Other African' ELSE 'UK' END
    FROM (SELECT BusinessAccountID, ContactNum, ABS(CHECKSUM(NEWID())) % 100 + 1 AS r FROM #ContactPlan WHERE AcctCountry = 'CA') x
    WHERE #ContactPlan.BusinessAccountID = x.BusinessAccountID AND #ContactPlan.ContactNum = x.ContactNum;

    UPDATE cp
    SET NameRandIdx      = (ABS(CHECKSUM(NEWID())) % nc.CatCount) + 1,
        PhoneCityRandIdx = (ABS(CHECKSUM(NEWID())) % cc.CountryCount) + 1
    FROM #ContactPlan cp
    JOIN #NameBankCatCounts nc ON nc.origin_category = cp.OriginCategory
    JOIN #CityRefCounts cc ON cc.CountryCode = cp.AcctCountry;

    INSERT INTO dbo.BusinessContacts (BusinessAccountID, FirstName, LastName, Email, Phone, JobTitle, IsPrimary,
                                       CreatedAt, CreatedBy, ModifiedAt, ModifiedBy)
    SELECT
        cp.BusinessAccountID,
        nb.first_name, nb.last_name,
        CASE WHEN ABS(CHECKSUM(NEWID())) % 100 < 88
             THEN LOWER(nb.first_name) + '.' + LOWER(nb.last_name) + CAST(cp.BusinessAccountID AS VARCHAR(10)) + CAST(cp.ContactNum AS VARCHAR(2)) + '@business.example.com'
             ELSE NULL END,
        '(' + pc.AreaCode + ') ' + RIGHT('000' + CAST(ABS(CHECKSUM(NEWID())) % 1000 AS VARCHAR(3)), 3) + '-' + RIGHT('0000' + CAST(ABS(CHECKSUM(NEWID())) % 10000 AS VARCHAR(4)), 4),
        jt.JobTitle,
        CASE WHEN cp.ContactNum = 1 THEN 1 ELSE 0 END,
        @SeedDate, @TarYuni, @SeedDate, @TarYuni
    FROM #ContactPlan cp
    JOIN #NameBankNumbered nb ON nb.origin_category = cp.OriginCategory AND nb.CatRowNum = cp.NameRandIdx
    JOIN #CityRefNumbered pc ON pc.CountryCode = cp.AcctCountry AND pc.CountryRowNum = cp.PhoneCityRandIdx
    JOIN #JobTitlesBC jt ON jt.RowNum = cp.JobRandIdx;

    PRINT 'BusinessContacts inserted: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    -- =====================================================================
    -- BUSINESS ACCOUNT ADDRESSES (target ~400, 1-2 per account)
    -- =====================================================================
    IF OBJECT_ID('tempdb..#BAARolePlan') IS NOT NULL DROP TABLE #BAARolePlan;
    SELECT
        m.BusinessAccountID,
        m.AcctCountry,
        t.n AS RoleNum,
        CAST(NULL AS INT) AS CityRandIdx,
        (ABS(CHECKSUM(NEWID())) % @StreetCount) + 1 AS StreetRandIdx,
        CASE WHEN t.n = 1
             THEN (CASE ABS(CHECKSUM(NEWID())) % 5 WHEN 3 THEN 'Warehouse' WHEN 4 THEN 'Pickup' ELSE 'Billing' END)
             ELSE (CASE ABS(CHECKSUM(NEWID())) % 4 WHEN 0 THEN 'Warehouse' WHEN 1 THEN 'Pickup' WHEN 2 THEN 'Delivery' ELSE 'Other' END)
        END AS AddressRole
    INTO #BAARolePlan
    FROM #BAMap m
    JOIN #Tally t ON t.n <= m.RoleCount;

    UPDATE rp
    SET CityRandIdx = (ABS(CHECKSUM(NEWID())) % cc.CountryCount) + 1
    FROM #BAARolePlan rp
    JOIN #CityRefCounts cc ON cc.CountryCode = rp.AcctCountry;

    IF OBJECT_ID('tempdb..#BAASource') IS NOT NULL DROP TABLE #BAASource;
    SELECT
        rp.BusinessAccountID,
        rp.RoleNum,
        rp.AddressRole,
        CAST(ABS(CHECKSUM(NEWID())) % 9899 + 100 AS VARCHAR(5)) + ' ' + sn.StreetName AS AddressLine1,
        CASE WHEN ABS(CHECKSUM(NEWID())) % 100 < 15 THEN 'Suite ' + CAST(ABS(CHECKSUM(NEWID())) % 900 + 100 AS VARCHAR(4)) ELSE NULL END AS AddressLine2,
        ac.City, ac.StateProvince,
        CASE WHEN rp.AcctCountry = 'US'
             THEN ac.ZipBase + RIGHT('00' + CAST(ABS(CHECKSUM(NEWID())) % 100 AS VARCHAR(2)), 2)
             ELSE ac.ZipBase + ' ' + CHAR(65 + ABS(CHECKSUM(NEWID())) % 26) + CAST(ABS(CHECKSUM(NEWID())) % 10 AS VARCHAR(1)) + CHAR(65 + ABS(CHECKSUM(NEWID())) % 26)
        END AS PostalCode,
        rp.AcctCountry AS CountryCode
    INTO #BAASource
    FROM #BAARolePlan rp
    JOIN #CityRefNumbered ac ON ac.CountryCode = rp.AcctCountry AND ac.CountryRowNum = rp.CityRandIdx
    JOIN #StreetNames sn ON sn.RowNum = rp.StreetRandIdx;

    IF OBJECT_ID('tempdb..#BAAResult') IS NOT NULL DROP TABLE #BAAResult;
    CREATE TABLE #BAAResult (BusinessAccountID INT, AddressRole NVARCHAR(30), RoleNum INT, AddressID INT);

    MERGE INTO dbo.Addresses AS tgt
    USING #BAASource AS src
    ON 1 = 0
    WHEN NOT MATCHED THEN
        INSERT (AddressLine1, AddressLine2, City, StateProvince, PostalCode, CountryCode, CreatedAt, CreatedBy, ModifiedAt, ModifiedBy)
        VALUES (src.AddressLine1, src.AddressLine2, src.City, src.StateProvince, src.PostalCode, src.CountryCode, @SeedDate, @TarYuni, @SeedDate, @TarYuni)
    OUTPUT src.BusinessAccountID, src.AddressRole, src.RoleNum, inserted.AddressID
    INTO #BAAResult (BusinessAccountID, AddressRole, RoleNum, AddressID);

    PRINT 'BusinessAccountAddresses pool Addresses inserted: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    INSERT INTO dbo.BusinessAccountAddresses (BusinessAccountID, AddressID, AddressRole, IsPrimary, CreatedAt, CreatedBy, ModifiedAt, ModifiedBy)
    SELECT BusinessAccountID, AddressID, AddressRole, CASE WHEN RoleNum = 1 THEN 1 ELSE 0 END, @SeedDate, @TarYuni, @SeedDate, @TarYuni
    FROM #BAAResult;

    PRINT 'BusinessAccountAddresses inserted: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    COMMIT TRANSACTION;
    PRINT '01-parties.sql completed successfully.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
    DECLARE @ErrSeverity INT = ERROR_SEVERITY();
    DECLARE @ErrState INT = ERROR_STATE();
    RAISERROR('01-parties.sql failed: %s', @ErrSeverity, @ErrState, @ErrMsg);
END CATCH
GO
