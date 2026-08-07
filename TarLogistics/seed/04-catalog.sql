-- =============================================================================
-- 04-catalog.sql
-- Cluster 5 (catalog portion): RateCards
-- =============================================================================
-- RateCards uses the 3 DDL-valid ServiceTier values: Ground, Express, Freight.
-- Row count: 3 tiers x 9 zones x 3 SCD periods = 81 rows.
-- DestinationZoneID is set equal to OriginZoneID on every row — the column
-- is NOT NULL but not meaningfully distinct from origin in this schema.
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

    -- Current (2025-01-01+) base rates, USD per kg
    IF OBJECT_ID('tempdb..#RateBase') IS NOT NULL DROP TABLE #RateBase;
    CREATE TABLE #RateBase (ServiceTier NVARCHAR(20), BaseRateCurrent DECIMAL(10,4), SurchargeCurrent DECIMAL(8,4));
    INSERT INTO #RateBase (ServiceTier, BaseRateCurrent, SurchargeCurrent) VALUES
    ('Ground', 4.50, 0.15),
    ('Express', 9.00, 0.35),
    ('Freight', 2.80, 0.10);

    -- Three SCD Type 2 effective periods; rates step down ~5%/year going back
    IF OBJECT_ID('tempdb..#Periods') IS NOT NULL DROP TABLE #Periods;
    CREATE TABLE #Periods (PeriodLabel NVARCHAR(20), EffectiveFrom DATE, EffectiveTo DATE, YearsBeforeCurrent INT);
    INSERT INTO #Periods (PeriodLabel, EffectiveFrom, EffectiveTo, YearsBeforeCurrent) VALUES
    ('Historical v1', '2023-01-01', '2023-12-31', 2),
    ('Historical v2', '2024-01-01', '2024-12-31', 1),
    ('Current',       '2025-01-01', NULL,          0);

    INSERT INTO dbo.RateCards (ServiceTier, OriginZoneID, DestinationZoneID, MinWeightKg, MaxWeightKg,
                                BaseRate, RateCurrency, PerKgSurcharge, EffectiveFrom, EffectiveTo,
                                CreatedAt, CreatedBy, ModifiedAt, ModifiedBy)
    SELECT
        rb.ServiceTier,
        sz.ServiceZoneID, sz.ServiceZoneID,
        0.00, 999.99,
        CAST((rb.BaseRateCurrent / POWER(1.05, p.YearsBeforeCurrent)) *
             (CASE WHEN sz.CountryCode = 'CA' THEN 1.20 ELSE 1.00 END) AS DECIMAL(10,2)),
        'USD',
        CAST((rb.SurchargeCurrent / POWER(1.05, p.YearsBeforeCurrent)) *
             (CASE WHEN sz.CountryCode = 'CA' THEN 1.20 ELSE 1.00 END) AS DECIMAL(8,4)),
        p.EffectiveFrom, p.EffectiveTo,
        @SeedDate, @TarYuni, @SeedDate, @TarYuni
    FROM #RateBase rb
    CROSS JOIN dbo.ServiceZones sz
    CROSS JOIN #Periods p;

    PRINT 'RateCards inserted: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    COMMIT TRANSACTION;
    PRINT '04-catalog.sql completed successfully.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
    DECLARE @ErrSeverity INT = ERROR_SEVERITY();
    DECLARE @ErrState INT = ERROR_STATE();
    RAISERROR('04-catalog.sql failed: %s', @ErrSeverity, @ErrState, @ErrMsg);
END CATCH
GO
