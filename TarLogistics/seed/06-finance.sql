-- =============================================================================
-- 06-finance.sql
-- Cluster 5 (commercial portion): InvoiceLineItems, Invoices, Payments
-- =============================================================================
-- Only business-account-sent shipments are invoiced — retail (Customer-sent)
-- shipments pay at booking time via Shipments.RetailPaymentStatus.
-- InvoiceLineItems is populated with one row per business shipment so that
-- TotalAmount can be computed as a genuine sum of per-shipment charges.
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

    -- One (arbitrary but stable) country/currency per business account
    IF OBJECT_ID('tempdb..#BizAcctCountry') IS NOT NULL DROP TABLE #BizAcctCountry;
    SELECT ba.BusinessAccountID, MIN(a.CountryCode) AS CountryCode
    INTO #BizAcctCountry
    FROM dbo.BusinessAccounts ba
    JOIN dbo.BusinessAccountAddresses baa ON baa.BusinessAccountID = ba.BusinessAccountID
    JOIN dbo.Addresses a ON a.AddressID = baa.AddressID
    GROUP BY ba.BusinessAccountID;

    -- Business-sent shipments with a synthetic tier-appropriate charge
    IF OBJECT_ID('tempdb..#BizShip') IS NOT NULL DROP TABLE #BizShip;
    SELECT
        s.ShipmentID, s.SenderBusinessAccountID AS BusinessAccountID, s.ServiceTier, s.CreatedAt,
        YEAR(s.CreatedAt) AS InvYear, MONTH(s.CreatedAt) AS InvMonth,
        CAST(NULL AS DECIMAL(10,2)) AS LineAmount
    INTO #BizShip
    FROM dbo.Shipments s
    WHERE s.SenderBusinessAccountID IS NOT NULL;

    UPDATE #BizShip
    SET LineAmount = CASE ServiceTier
        WHEN 'Ground'  THEN CAST(15 + ABS(CHECKSUM(NEWID())) % 13500 / 100.0 AS DECIMAL(10,2))
        WHEN 'Express' THEN CAST(25 + ABS(CHECKSUM(NEWID())) % 22500 / 100.0 AS DECIMAL(10,2))
        ELSE                CAST(200 + ABS(CHECKSUM(NEWID())) % 330000 / 100.0 AS DECIMAL(10,2))
    END;

    -- One invoice per (BusinessAccount, month-with-shipments)
    IF OBJECT_ID('tempdb..#InvoicePlan') IS NOT NULL DROP TABLE #InvoicePlan;
    SELECT DISTINCT
        bs.BusinessAccountID, bs.InvYear, bs.InvMonth,
        bac.CountryCode,
        DATEFROMPARTS(bs.InvYear, bs.InvMonth, 1) AS ShipMonthStart
    INTO #InvoicePlan
    FROM #BizShip bs
    JOIN #BizAcctCountry bac ON bac.BusinessAccountID = bs.BusinessAccountID;

    ALTER TABLE #InvoicePlan ADD InvoiceDate DATE, DueDate DATE, InvoiceNumber NVARCHAR(30), SeqVal BIGINT;

    -- Billing runs on the 5th of the month after the shipments occurred
    UPDATE #InvoicePlan
    SET InvoiceDate = DATEADD(DAY, 4, DATEADD(MONTH, 1, ShipMonthStart)),
        DueDate     = DATEADD(DAY, 34, DATEADD(MONTH, 1, ShipMonthStart));

    UPDATE #InvoicePlan SET SeqVal = NEXT VALUE FOR dbo.TrackingNumberSeq;

    UPDATE #InvoicePlan
    SET InvoiceNumber = 'INV-' + CAST(InvYear AS VARCHAR(4)) + '-' + RIGHT('000000' + CAST(SeqVal % 1000000 AS VARCHAR(6)), 6);

    IF OBJECT_ID('tempdb..#InvoiceResult') IS NOT NULL DROP TABLE #InvoiceResult;
    CREATE TABLE #InvoiceResult (InvoiceID INT, BusinessAccountID INT, InvYear INT, InvMonth INT, InvoiceDate DATE, DueDate DATE, CountryCode CHAR(2));

    MERGE INTO dbo.Invoices AS tgt
    USING #InvoicePlan AS src
    ON 1 = 0
    WHEN NOT MATCHED THEN
        INSERT (InvoiceNumber, BusinessAccountID, InvoiceDate, DueDate, TotalAmount, CurrencyCode, ExchangeRateToUSD,
                InvoiceStatus, Notes, CreatedAt, CreatedBy, ModifiedAt, ModifiedBy)
        VALUES (src.InvoiceNumber, src.BusinessAccountID, src.InvoiceDate, src.DueDate,
                0.00,
                CASE WHEN src.CountryCode = 'US' THEN 'USD' ELSE 'CAD' END,
                CASE WHEN src.CountryCode = 'US' THEN 1.000000 ELSE 0.730000 END,
                'Draft', NULL,
                CAST(src.InvoiceDate AS DATETIME2(7)), @TarYuni, CAST(src.InvoiceDate AS DATETIME2(7)), @TarYuni)
    OUTPUT inserted.InvoiceID, src.BusinessAccountID, src.InvYear, src.InvMonth, src.InvoiceDate, src.DueDate, src.CountryCode
    INTO #InvoiceResult (InvoiceID, BusinessAccountID, InvYear, InvMonth, InvoiceDate, DueDate, CountryCode);

    PRINT 'Invoices inserted: ' + CAST(@@ROWCOUNT AS VARCHAR(10));
    CREATE UNIQUE CLUSTERED INDEX IX_InvoiceResult ON #InvoiceResult (InvoiceID);
    CREATE NONCLUSTERED INDEX IX_InvoiceResult_Acct ON #InvoiceResult (BusinessAccountID, InvYear, InvMonth);

    -- InvoiceLineItems: one per business shipment
    INSERT INTO dbo.InvoiceLineItems (InvoiceID, ShipmentID, LineDescription, LineAmount, CurrencyCode,
                                       CreatedAt, CreatedBy, ModifiedAt, ModifiedBy)
    SELECT
        ir.InvoiceID, bs.ShipmentID,
        bs.ServiceTier + ' shipment charge',
        bs.LineAmount,
        CASE WHEN ir.CountryCode = 'US' THEN 'USD' ELSE 'CAD' END,
        CAST(ir.InvoiceDate AS DATETIME2(7)), @TarYuni, CAST(ir.InvoiceDate AS DATETIME2(7)), @TarYuni
    FROM #BizShip bs
    JOIN #InvoiceResult ir ON ir.BusinessAccountID = bs.BusinessAccountID AND ir.InvYear = bs.InvYear AND ir.InvMonth = bs.InvMonth;

    PRINT 'InvoiceLineItems inserted: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    -- Correct TotalAmount and set initial InvoiceStatus
    -- CK_Invoices_Status allows: Draft/Issued/PartiallyPaid/Paid/Overdue/Cancelled/Disputed
    UPDATE inv
    SET TotalAmount = agg.SumAmount
    FROM dbo.Invoices inv
    JOIN (SELECT InvoiceID, SUM(LineAmount) AS SumAmount FROM dbo.InvoiceLineItems GROUP BY InvoiceID) agg
        ON agg.InvoiceID = inv.InvoiceID;

    UPDATE inv
    SET InvoiceStatus = CASE
        WHEN DATEDIFF(DAY, inv.InvoiceDate, @Today) > 60 THEN 'Overdue'
        ELSE 'Issued' END
    FROM dbo.Invoices inv;

    PRINT 'Invoice totals/status set: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    -- =====================================================================
    -- PAYMENTS (~88% of invoices)
    -- =====================================================================
    IF OBJECT_ID('tempdb..#PaymentPlan') IS NOT NULL DROP TABLE #PaymentPlan;
    SELECT ir.InvoiceID, ir.InvoiceDate, ir.CountryCode, inv.TotalAmount,
           CAST(NULL AS BIT) AS WillPay
    INTO #PaymentPlan
    FROM #InvoiceResult ir
    JOIN dbo.Invoices inv ON inv.InvoiceID = ir.InvoiceID;

    UPDATE pp
    SET WillPay = CASE WHEN r < 88 THEN 1 ELSE 0 END
    FROM #PaymentPlan pp
    JOIN (SELECT InvoiceID, ABS(CHECKSUM(NEWID())) % 100 AS r FROM #PaymentPlan) x ON x.InvoiceID = pp.InvoiceID;

    -- Invoices created within the last 15 days can't have a realistic payment yet
    UPDATE #PaymentPlan SET WillPay = 0 WHERE DATEDIFF(DAY, InvoiceDate, @Today) < 15;

    ALTER TABLE #PaymentPlan ADD PaymentDate DATE;
    UPDATE #PaymentPlan SET PaymentDate = DATEADD(DAY, 15 + ABS(CHECKSUM(NEWID())) % 31, InvoiceDate) WHERE WillPay = 1;

    INSERT INTO dbo.Payments (InvoiceID, PaymentDate, AmountPaid, CurrencyCode, ExchangeRateToUSD,
                               PaymentMethod, PaymentReference, Notes,
                               CreatedAt, CreatedBy, ModifiedAt, ModifiedBy)
    SELECT
        pp.InvoiceID, pp.PaymentDate, pp.TotalAmount,
        CASE WHEN pp.CountryCode = 'US' THEN 'USD' ELSE 'CAD' END,
        CASE WHEN pp.CountryCode = 'US' THEN 1.000000 ELSE 0.730000 END,
        CASE ABS(CHECKSUM(NEWID())) % 4 WHEN 0 THEN 'Wire' WHEN 1 THEN 'ACH' WHEN 2 THEN 'Check' ELSE 'EFT' END,
        'REF' + RIGHT('0000000000' + CAST(ABS(CHECKSUM(NEWID())) AS VARCHAR(10)), 10),
        NULL,
        CAST(pp.PaymentDate AS DATETIME2(7)), @TarYuni,
        CAST(pp.PaymentDate AS DATETIME2(7)), @TarYuni
    FROM #PaymentPlan pp
    WHERE pp.WillPay = 1;

    PRINT 'Payments inserted: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    -- Paid invoices flip to 'Paid'
    UPDATE inv
    SET InvoiceStatus = 'Paid'
    FROM dbo.Invoices inv
    JOIN dbo.Payments p ON p.InvoiceID = inv.InvoiceID;

    PRINT 'Invoices marked Paid: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    COMMIT TRANSACTION;
    PRINT '06-finance.sql completed successfully.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
    DECLARE @ErrSeverity INT = ERROR_SEVERITY();
    DECLARE @ErrState INT = ERROR_STATE();
    RAISERROR('06-finance.sql failed: %s', @ErrSeverity, @ErrState, @ErrMsg);
END CATCH
GO
