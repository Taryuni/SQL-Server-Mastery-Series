-- =============================================================================
-- 02-network.sql
-- Cluster 2: Facilities (+ self-ref parent FKs), ServiceZones, ZonePostalCodes,
--            Routes
-- =============================================================================
-- Deviation from the original file plan: RouteAssignments (dbo.Assignments)
-- is generated in 03-hr.sql, not here. dbo.Assignments has NOT NULL FKs to
-- Drivers and Vehicles, both of which are created in 03-hr.sql — populating
-- it here would fail before those tables exist. Its content and doc block
-- still describe it as "network/route assignment" data; only the physical
-- file location changed to respect the real dependency order.
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

    -- =====================================================================
    -- FACILITIES (14 total: 3 hubs, 7 depots, 4 retail counters)
    -- Each facility needs an Address row first (FK NOT NULL), inserted via a
    -- dummy MERGE so OUTPUT can correlate the new AddressID back to the
    -- FacilityCode it belongs to.
    -- =====================================================================
    IF OBJECT_ID('tempdb..#FacilitySource') IS NOT NULL DROP TABLE #FacilitySource;
    CREATE TABLE #FacilitySource (
        FacilityCode  NVARCHAR(10),
        FacilityName  NVARCHAR(200),
        FacilityType  NVARCHAR(30),
        ParentCode    NVARCHAR(10) NULL,
        AddressLine1  NVARCHAR(200),
        City          NVARCHAR(100),
        StateProvince NVARCHAR(100),
        PostalCode    NVARCHAR(20),
        CountryCode   CHAR(2)
    );
    INSERT INTO #FacilitySource (FacilityCode, FacilityName, FacilityType, ParentCode, AddressLine1, City, StateProvince, PostalCode, CountryCode) VALUES
    -- Hubs
    ('CMH-HUB-01', 'Columbus Gateway Hub',       'Hub',           NULL,         '4500 Fisher Rd',            'Columbus',    'OH', '43228',    'US'),
    ('YYZ-HUB-01', 'Toronto Canadian Gateway',    'Hub',           NULL,         '5900 Explorer Dr',          'Mississauga', 'ON', 'L4W 5N8',  'CA'),
    ('YUL-HUB-01', 'Montréal Regional Hub',       'Hub',           NULL,         '800 Chemin de la Côte-de-Liesse', 'Dorval', 'QC', 'H9P 1A1',  'CA'),
    -- Depots
    ('ORD-DEP-01', 'Chicago Depot',               'Depot',         'CMH-HUB-01', '4433 S Kildare Ave',        'Chicago',     'IL', '60632',    'US'),
    ('JFK-DEP-01', 'New York Depot',               'Depot',        'CMH-HUB-01', '168-30 Baisley Blvd',       'New York',    'NY', '11434',    'US'),
    ('ATL-DEP-01', 'Atlanta Depot',                'Depot',        'CMH-HUB-01', '3400 Camp Creek Pkwy',      'Atlanta',     'GA', '30331',    'US'),
    ('DFW-DEP-01', 'Dallas Depot',                 'Depot',        'CMH-HUB-01', '2200 Regent Blvd',          'Dallas',      'TX', '75261',    'US'),
    ('LAX-DEP-01', 'Los Angeles Depot',            'Depot',        'CMH-HUB-01', '5959 W Century Blvd',       'Los Angeles', 'CA', '90045',    'US'),
    ('YVR-DEP-01', 'Vancouver Depot',              'Depot',        'YYZ-HUB-01', '5911 Miller Rd',            'Vancouver',   'BC', 'V7B 1K7',  'CA'),
    ('YYC-DEP-01', 'Calgary Depot',                'Depot',        'YYZ-HUB-01', '2450 44 Ave NE',            'Calgary',     'AB', 'T2E 6L1',  'CA'),
    -- Retail counters
    ('BOS-RET-01', 'Boston Counter',               'RetailCounter','JFK-DEP-01', '800 Boylston St',           'Boston',      'MA', '02199',    'US'),
    ('MIA-RET-01', 'Miami Counter',                'RetailCounter','ATL-DEP-01', '1200 Brickell Ave',         'Miami',       'FL', '33131',    'US'),
    ('SEA-RET-01', 'Seattle Counter',               'RetailCounter','LAX-DEP-01', '2001 6th Ave',              'Seattle',     'WA', '98121',    'US'),
    ('YOW-RET-01', 'Ottawa Counter',                'RetailCounter','YUL-HUB-01', '100 Rideau St',             'Ottawa',      'ON', 'K1A 0A1',  'CA');

    IF OBJECT_ID('tempdb..#FacilityAddrResult') IS NOT NULL DROP TABLE #FacilityAddrResult;
    CREATE TABLE #FacilityAddrResult (FacilityCode NVARCHAR(10), AddressID INT);

    MERGE INTO dbo.Addresses AS tgt
    USING #FacilitySource AS src
    ON 1 = 0
    WHEN NOT MATCHED THEN
        INSERT (AddressLine1, AddressLine2, City, StateProvince, PostalCode, CountryCode, CreatedAt, CreatedBy, ModifiedAt, ModifiedBy)
        VALUES (src.AddressLine1, NULL, src.City, src.StateProvince, src.PostalCode, src.CountryCode, @SeedDate, @TarYuni, @SeedDate, @TarYuni)
    OUTPUT src.FacilityCode, inserted.AddressID
    INTO #FacilityAddrResult (FacilityCode, AddressID);

    PRINT 'Facility Addresses inserted: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    -- Pass 1: insert facilities without ParentFacilityID
    INSERT INTO dbo.Facilities (FacilityCode, FacilityName, FacilityType, AddressID, ParentFacilityID,
                                 CreatedAt, CreatedBy, ModifiedAt, ModifiedBy)
    SELECT fs.FacilityCode, fs.FacilityName, fs.FacilityType, ar.AddressID, NULL,
           @SeedDate, @TarYuni, @SeedDate, @TarYuni
    FROM #FacilitySource fs
    JOIN #FacilityAddrResult ar ON ar.FacilityCode = fs.FacilityCode;

    PRINT 'Facilities inserted: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    -- Pass 2: wire up self-referencing ParentFacilityID
    UPDATE f
    SET f.ParentFacilityID = pf.FacilityID
    FROM dbo.Facilities f
    JOIN #FacilitySource fs ON fs.FacilityCode = f.FacilityCode
    JOIN dbo.Facilities pf ON pf.FacilityCode = fs.ParentCode
    WHERE fs.ParentCode IS NOT NULL;

    PRINT 'Facilities parent links set: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    -- =====================================================================
    -- SERVICE ZONES (6 US + 3 Canadian)
    -- =====================================================================
    INSERT INTO dbo.ServiceZones (ZoneCode, ZoneName, CountryCode, CreatedAt, CreatedBy, ModifiedAt, ModifiedBy) VALUES
    ('US-NE', 'Northeast',        'US', @SeedDate, @TarYuni, @SeedDate, @TarYuni),
    ('US-SE', 'Southeast',        'US', @SeedDate, @TarYuni, @SeedDate, @TarYuni),
    ('US-MW', 'Midwest',          'US', @SeedDate, @TarYuni, @SeedDate, @TarYuni),
    ('US-SC', 'South Central',    'US', @SeedDate, @TarYuni, @SeedDate, @TarYuni),
    ('US-WC', 'West Coast',       'US', @SeedDate, @TarYuni, @SeedDate, @TarYuni),
    ('US-MT', 'Mountain',         'US', @SeedDate, @TarYuni, @SeedDate, @TarYuni),
    ('CA-ON', 'Ontario',          'CA', @SeedDate, @TarYuni, @SeedDate, @TarYuni),
    ('CA-QC', 'Quebec & Atlantic','CA', @SeedDate, @TarYuni, @SeedDate, @TarYuni),
    ('CA-WC', 'Western Canada',   'CA', @SeedDate, @TarYuni, @SeedDate, @TarYuni);

    PRINT 'ServiceZones inserted: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    -- =====================================================================
    -- ZONE POSTAL CODES (~180 real codes)
    -- Each row is a single-code range (Min = Max) — satisfies CK_ZPC_Range.
    -- =====================================================================
    IF OBJECT_ID('tempdb..#ZonePostalSource') IS NOT NULL DROP TABLE #ZonePostalSource;
    CREATE TABLE #ZonePostalSource (ZoneCode NVARCHAR(10), Code NVARCHAR(20));
    INSERT INTO #ZonePostalSource (ZoneCode, Code) VALUES
    -- US-NE
    ('US-NE','02101'),('US-NE','02201'),('US-NE','06101'),('US-NE','07101'),('US-NE','07201'),
    ('US-NE','10001'),('US-NE','10101'),('US-NE','15201'),('US-NE','19101'),('US-NE','05401'),
    ('US-NE','02138'),('US-NE','03301'),('US-NE','04101'),('US-NE','06510'),('US-NE','08540'),
    ('US-NE','10451'),('US-NE','11201'),('US-NE','12207'),('US-NE','14604'),('US-NE','16501'),
    ('US-NE','18101'),('US-NE','02840'),
    -- US-SE
    ('US-SE','27601'),('US-SE','28201'),('US-SE','30301'),('US-SE','32201'),('US-SE','33101'),
    ('US-SE','33601'),('US-SE','35201'),('US-SE','37201'),('US-SE','38101'),('US-SE','23201'),
    ('US-SE','29201'),('US-SE','29401'),('US-SE','31401'),('US-SE','33602'),('US-SE','34102'),
    ('US-SE','36104'),('US-SE','39201'),('US-SE','22201'),('US-SE','23451'),('US-SE','27401'),
    ('US-SE','28801'),('US-SE','37402'),
    -- US-MW
    ('US-MW','43201'),('US-MW','44101'),('US-MW','45201'),('US-MW','46201'),('US-MW','48201'),
    ('US-MW','53201'),('US-MW','55401'),('US-MW','60601'),('US-MW','63101'),('US-MW','64101'),
    ('US-MW','43215'),('US-MW','46204'),('US-MW','47708'),('US-MW','48226'),('US-MW','49503'),
    ('US-MW','53703'),('US-MW','54301'),('US-MW','55101'),('US-MW','60614'),('US-MW','62701'),
    ('US-MW','65101'),('US-MW','41011'),
    -- US-SC
    ('US-SC','70112'),('US-SC','72201'),('US-SC','73101'),('US-SC','75201'),('US-SC','75301'),
    ('US-SC','77001'),('US-SC','78201'),('US-SC','78701'),('US-SC','70801'),('US-SC','71101'),
    ('US-SC','73401'),('US-SC','74103'),('US-SC','76102'),('US-SC','77002'),('US-SC','79401'),
    ('US-SC','79901'),('US-SC','72701'),('US-SC','70601'),
    -- US-WC
    ('US-WC','85001'),('US-WC','89101'),('US-WC','90001'),('US-WC','90201'),('US-WC','94101'),
    ('US-WC','97201'),('US-WC','92101'),('US-WC','85251'),('US-WC','90210'),('US-WC','91101'),
    ('US-WC','92037'),('US-WC','93101'),('US-WC','94102'),('US-WC','95814'),('US-WC','97401'),
    ('US-WC','98101'),('US-WC','98661'),('US-WC','89501'),('US-WC','86001'),
    -- US-MT
    ('US-MT','80201'),('US-MT','80301'),('US-MT','83701'),('US-MT','84101'),('US-MT','87101'),
    ('US-MT','59101'),('US-MT','82001'),('US-MT','80202'),('US-MT','80903'),('US-MT','83702'),
    ('US-MT','84604'),('US-MT','87501'),('US-MT','82601'),('US-MT','59601'),('US-MT','81301'),
    -- CA-ON
    ('CA-ON','K1A'),('CA-ON','K7L'),('CA-ON','L5B'),('CA-ON','L8P'),('CA-ON','M5H'),
    ('CA-ON','M5V'),('CA-ON','N6A'),('CA-ON','M4B'),('CA-ON','M6K'),('CA-ON','L4W'),
    ('CA-ON','L6T'),('CA-ON','L9H'),('CA-ON','K2P'),('CA-ON','N2L'),('CA-ON','P3E'),
    ('CA-ON','P7A'),('CA-ON','K9V'),
    -- CA-QC
    ('CA-QC','B3H'),('CA-QC','E1C'),('CA-QC','E3B'),('CA-QC','G1R'),('CA-QC','H2X'),
    ('CA-QC','H2Y'),('CA-QC','H7S'),('CA-QC','H3A'),('CA-QC','H4B'),('CA-QC','G7H'),
    ('CA-QC','J4B'),('CA-QC','B2Y'),('CA-QC','B4B'),('CA-QC','C1A'),('CA-QC','A1B'),
    ('CA-QC','E8J'),('CA-QC','J2S'),
    -- CA-WC
    ('CA-WC','R3B'),('CA-WC','S4P'),('CA-WC','S7K'),('CA-WC','T2P'),('CA-WC','T5J'),
    ('CA-WC','V6B'),('CA-WC','V8W'),('CA-WC','T3A'),('CA-WC','T6E'),('CA-WC','V5K'),
    ('CA-WC','V9A'),('CA-WC','R2C'),('CA-WC','S4S'),('CA-WC','V1Y'),('CA-WC','V2S'),
    ('CA-WC','T1Y');

    INSERT INTO dbo.ZonePostalCodes (ServiceZoneID, MinPostalCode, MaxPostalCode, CreatedAt, CreatedBy, ModifiedAt, ModifiedBy)
    SELECT sz.ServiceZoneID, zp.Code, zp.Code, @SeedDate, @TarYuni, @SeedDate, @TarYuni
    FROM #ZonePostalSource zp
    JOIN dbo.ServiceZones sz ON sz.ZoneCode = zp.ZoneCode;

    PRINT 'ZonePostalCodes inserted: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    -- =====================================================================
    -- ROUTES (30 directional hub-hub / hub-depot / depot-retail legs)
    -- =====================================================================
    IF OBJECT_ID('tempdb..#RouteSource') IS NOT NULL DROP TABLE #RouteSource;
    CREATE TABLE #RouteSource (OriginCode NVARCHAR(10), DestCode NVARCHAR(10), ServiceTier NVARCHAR(20), TransitDays INT);
    INSERT INTO #RouteSource (OriginCode, DestCode, ServiceTier, TransitDays) VALUES
    -- Hub <-> Hub trunk lines
    ('CMH-HUB-01','YYZ-HUB-01','Freight',2), ('YYZ-HUB-01','CMH-HUB-01','Freight',2),
    ('CMH-HUB-01','YUL-HUB-01','Freight',2), ('YUL-HUB-01','CMH-HUB-01','Freight',2),
    ('YYZ-HUB-01','YUL-HUB-01','Express',1), ('YUL-HUB-01','YYZ-HUB-01','Express',1),
    -- CMH hub <-> its depots
    ('CMH-HUB-01','ORD-DEP-01','Ground',1),  ('ORD-DEP-01','CMH-HUB-01','Ground',1),
    ('CMH-HUB-01','JFK-DEP-01','Express',1),  ('JFK-DEP-01','CMH-HUB-01','Express',1),
    ('CMH-HUB-01','ATL-DEP-01','Ground',1),  ('ATL-DEP-01','CMH-HUB-01','Ground',1),
    ('CMH-HUB-01','DFW-DEP-01','Ground',1),  ('DFW-DEP-01','CMH-HUB-01','Ground',1),
    ('CMH-HUB-01','LAX-DEP-01','Express',2),  ('LAX-DEP-01','CMH-HUB-01','Express',2),
    -- YYZ hub <-> its depots
    ('YYZ-HUB-01','YVR-DEP-01','Express',2),  ('YVR-DEP-01','YYZ-HUB-01','Express',2),
    ('YYZ-HUB-01','YYC-DEP-01','Ground',1),  ('YYC-DEP-01','YYZ-HUB-01','Ground',1),
    -- Depot <-> retail counter (last mile)
    ('JFK-DEP-01','BOS-RET-01','Ground',1),  ('BOS-RET-01','JFK-DEP-01','Ground',1),
    ('ATL-DEP-01','MIA-RET-01','Ground',1),  ('MIA-RET-01','ATL-DEP-01','Ground',1),
    ('LAX-DEP-01','SEA-RET-01','Ground',1),  ('SEA-RET-01','LAX-DEP-01','Ground',1),
    ('YUL-HUB-01','YOW-RET-01','Ground',1),  ('YOW-RET-01','YUL-HUB-01','Ground',1),
    -- Regional consolidation lane
    ('DFW-DEP-01','ATL-DEP-01','Ground',1),  ('ATL-DEP-01','DFW-DEP-01','Ground',1);

    INSERT INTO dbo.Routes (RouteCode, OriginFacilityID, DestinationFacilityID, ServiceTier, EstimatedTransitDays, IsActive,
                             CreatedAt, CreatedBy, ModifiedAt, ModifiedBy)
    SELECT
        LEFT(rs.OriginCode, 3) + '-' + LEFT(rs.DestCode, 3) + '-' +
            CASE rs.ServiceTier WHEN 'Ground' THEN 'GND' WHEN 'Express' THEN 'EXP' ELSE 'FRT' END,
        fo.FacilityID, fd.FacilityID, rs.ServiceTier, rs.TransitDays, 1,
        @SeedDate, @TarYuni, @SeedDate, @TarYuni
    FROM #RouteSource rs
    JOIN dbo.Facilities fo ON fo.FacilityCode = rs.OriginCode
    JOIN dbo.Facilities fd ON fd.FacilityCode = rs.DestCode;

    PRINT 'Routes inserted: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    COMMIT TRANSACTION;
    PRINT '02-network.sql completed successfully.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
    DECLARE @ErrSeverity INT = ERROR_SEVERITY();
    DECLARE @ErrState INT = ERROR_STATE();
    RAISERROR('02-network.sql failed: %s', @ErrSeverity, @ErrState, @ErrMsg);
END CATCH
GO
