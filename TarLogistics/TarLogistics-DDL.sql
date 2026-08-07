-- =============================================================================
-- TAR LOGISTICS — COMPLETE DATABASE DDL
-- =============================================================================
-- Series  : SQL Server Mastery | Book 1: SQL Server Fundamentals
-- Author  : Fonyuy Taryuni
-- Version : 1.0 | 2026-07-25
-- Target  : SQL Server 2022 (compatible with SQL Server 2019+)
--
-- Entity Clusters (21 tables total):
--   1. Parties     — Addresses, Customers, BusinessAccounts,
--                    BusinessContacts, BusinessAccountAddresses (*)
--   2. Network     — Facilities, ServiceZones, ZonePostalCodes, Routes
--   3. Shipments   — Shipments, Packages, FreightBills, Pallets,
--                    TrackingEvents
--   4. Operations  — Employees, Drivers, Vehicles, Assignments
--   5. Commercial  — RateCards, Invoices, InvoiceLineItems, Payments
--
-- (*) BusinessAccountAddresses is a junction table not shown in the original
--     entity list. It replaces a 1:many FK on Addresses with a cleaner
--     many-to-many structure that captures the role of each address
--     (Billing, Warehouse, Pickup). Discussed and approved during DDL review.
--
-- Conventions applied throughout:
--   PKs      : INT IDENTITY(1,1) on all tables except TrackingEvents (BIGINT)
--   Audit    : CreatedAt, CreatedBy, ModifiedAt, ModifiedBy on every table
--   Soft del : DeletedAt DATETIME2(7) NULL on all main entities
--              NULL = active record | timestamp = soft-deleted
--   UTC time : All timestamps use SYSUTCDATETIME()
--   Self-ref : Self-referencing FKs added via ALTER TABLE after table creation
-- =============================================================================


-- =============================================================================
-- SETUP
-- =============================================================================

USE master;
GO

IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = N'TarLogistics')
BEGIN
    CREATE DATABASE TarLogistics;
    PRINT 'Database TarLogistics created.';
END
ELSE
    PRINT 'Database TarLogistics already exists — skipping creation.';
GO

USE TarLogistics;
GO

-- -----------------------------------------------------------------------------
-- CLEAN REBUILD BLOCK
-- Uncomment only when doing a full teardown and rebuild in dev/demo environments.
-- Never run this in production.
-- -----------------------------------------------------------------------------
/*
DROP TABLE IF EXISTS dbo.Payments;
DROP TABLE IF EXISTS dbo.InvoiceLineItems;
DROP TABLE IF EXISTS dbo.Invoices;
DROP TABLE IF EXISTS dbo.RateCards;
DROP TABLE IF EXISTS dbo.TrackingEvents;
DROP TABLE IF EXISTS dbo.Assignments;
DROP TABLE IF EXISTS dbo.Drivers;
DROP TABLE IF EXISTS dbo.Vehicles;
DROP TABLE IF EXISTS dbo.Employees;
DROP TABLE IF EXISTS dbo.Pallets;
DROP TABLE IF EXISTS dbo.FreightBills;
DROP TABLE IF EXISTS dbo.Packages;
DROP TABLE IF EXISTS dbo.Shipments;
DROP TABLE IF EXISTS dbo.ZonePostalCodes;
DROP TABLE IF EXISTS dbo.ServiceZones;
DROP TABLE IF EXISTS dbo.Routes;
DROP TABLE IF EXISTS dbo.Facilities;
DROP TABLE IF EXISTS dbo.BusinessAccountAddresses;
DROP TABLE IF EXISTS dbo.BusinessContacts;
DROP TABLE IF EXISTS dbo.BusinessAccounts;
DROP TABLE IF EXISTS dbo.Customers;
DROP TABLE IF EXISTS dbo.Addresses;
DROP SEQUENCE  IF EXISTS dbo.TrackingNumberSeq;
*/


-- =============================================================================
-- SEQUENCE — Tracking Number Generator
-- =============================================================================

IF NOT EXISTS (
    SELECT 1 FROM sys.sequences
    WHERE name = 'TrackingNumberSeq' AND schema_id = SCHEMA_ID('dbo')
)
BEGIN
    CREATE SEQUENCE dbo.TrackingNumberSeq
        AS BIGINT
        START WITH 1
        INCREMENT BY 1
        NO CYCLE;
    PRINT 'Sequence dbo.TrackingNumberSeq created.';
END
GO


-- =============================================================================
-- CLUSTER 1: PARTIES
-- Tables: Addresses, Customers, BusinessAccounts, BusinessContacts,
--         BusinessAccountAddresses
-- =============================================================================

CREATE TABLE dbo.Addresses (
    AddressID       INT             NOT NULL    IDENTITY(1,1),
    AddressLine1    NVARCHAR(200)   NOT NULL,
    AddressLine2    NVARCHAR(200)       NULL,
    City            NVARCHAR(100)   NOT NULL,
    StateProvince   NVARCHAR(100)   NOT NULL,
    PostalCode      NVARCHAR(20)    NOT NULL,
    CountryCode     CHAR(2)         NOT NULL,

    CreatedAt       DATETIME2(7)    NOT NULL    CONSTRAINT DF_Addresses_CreatedAt  DEFAULT SYSUTCDATETIME(),
    CreatedBy       NVARCHAR(100)   NOT NULL    CONSTRAINT DF_Addresses_CreatedBy  DEFAULT SYSTEM_USER,
    ModifiedAt      DATETIME2(7)    NOT NULL    CONSTRAINT DF_Addresses_ModifiedAt DEFAULT SYSUTCDATETIME(),
    ModifiedBy      NVARCHAR(100)   NOT NULL    CONSTRAINT DF_Addresses_ModifiedBy DEFAULT SYSTEM_USER,
    DeletedAt       DATETIME2(7)        NULL,

    CONSTRAINT PK_Addresses
        PRIMARY KEY CLUSTERED (AddressID),
    CONSTRAINT CK_Addresses_CountryCode
        CHECK (CountryCode IN ('US','CA','GB','FR','DE','NL','BE','ES','IT'))
);
GO

CREATE TABLE dbo.Customers (
    CustomerID      INT             NOT NULL    IDENTITY(1,1),
    FirstName       NVARCHAR(100)   NOT NULL,
    LastName        NVARCHAR(100)   NOT NULL,
    Email           NVARCHAR(200)       NULL,
    Phone           NVARCHAR(30)        NULL,

    CreatedAt       DATETIME2(7)    NOT NULL    CONSTRAINT DF_Customers_CreatedAt  DEFAULT SYSUTCDATETIME(),
    CreatedBy       NVARCHAR(100)   NOT NULL    CONSTRAINT DF_Customers_CreatedBy  DEFAULT SYSTEM_USER,
    ModifiedAt      DATETIME2(7)    NOT NULL    CONSTRAINT DF_Customers_ModifiedAt DEFAULT SYSUTCDATETIME(),
    ModifiedBy      NVARCHAR(100)   NOT NULL    CONSTRAINT DF_Customers_ModifiedBy DEFAULT SYSTEM_USER,
    DeletedAt       DATETIME2(7)        NULL,

    CONSTRAINT PK_Customers
        PRIMARY KEY CLUSTERED (CustomerID),
    CONSTRAINT UQ_Customers_Email
        UNIQUE (Email)
);
GO

CREATE TABLE dbo.BusinessAccounts (
    BusinessAccountID   INT             NOT NULL    IDENTITY(1,1),
    AccountName         NVARCHAR(200)   NOT NULL,
    TaxID               NVARCHAR(50)        NULL,
    CreditLimit         DECIMAL(12,2)       NULL,
    CreditLimitCurrency CHAR(3)         NOT NULL    CONSTRAINT DF_BA_CreditCurrency DEFAULT 'USD',
    PaymentTermsDays    INT             NOT NULL    CONSTRAINT DF_BA_PaymentTerms   DEFAULT 30,
    AccountStatus       NVARCHAR(20)    NOT NULL    CONSTRAINT DF_BA_Status         DEFAULT 'Active',

    CreatedAt           DATETIME2(7)    NOT NULL    CONSTRAINT DF_BA_CreatedAt  DEFAULT SYSUTCDATETIME(),
    CreatedBy           NVARCHAR(100)   NOT NULL    CONSTRAINT DF_BA_CreatedBy  DEFAULT SYSTEM_USER,
    ModifiedAt          DATETIME2(7)    NOT NULL    CONSTRAINT DF_BA_ModifiedAt DEFAULT SYSUTCDATETIME(),
    ModifiedBy          NVARCHAR(100)   NOT NULL    CONSTRAINT DF_BA_ModifiedBy DEFAULT SYSTEM_USER,
    DeletedAt           DATETIME2(7)        NULL,

    CONSTRAINT PK_BusinessAccounts
        PRIMARY KEY CLUSTERED (BusinessAccountID),
    CONSTRAINT CK_BA_PaymentTerms
        CHECK (PaymentTermsDays IN (0, 15, 30, 45, 60, 90)),
    CONSTRAINT CK_BA_Status
        CHECK (AccountStatus IN ('Active','Suspended','Closed'))
);
GO

CREATE TABLE dbo.BusinessContacts (
    BusinessContactID   INT             NOT NULL    IDENTITY(1,1),
    BusinessAccountID   INT             NOT NULL,
    FirstName           NVARCHAR(100)   NOT NULL,
    LastName            NVARCHAR(100)   NOT NULL,
    Email               NVARCHAR(200)       NULL,
    Phone               NVARCHAR(30)        NULL,
    JobTitle            NVARCHAR(100)       NULL,
    IsPrimary           BIT             NOT NULL    CONSTRAINT DF_BC_IsPrimary DEFAULT 0,

    CreatedAt           DATETIME2(7)    NOT NULL    CONSTRAINT DF_BC_CreatedAt  DEFAULT SYSUTCDATETIME(),
    CreatedBy           NVARCHAR(100)   NOT NULL    CONSTRAINT DF_BC_CreatedBy  DEFAULT SYSTEM_USER,
    ModifiedAt          DATETIME2(7)    NOT NULL    CONSTRAINT DF_BC_ModifiedAt DEFAULT SYSUTCDATETIME(),
    ModifiedBy          NVARCHAR(100)   NOT NULL    CONSTRAINT DF_BC_ModifiedBy DEFAULT SYSTEM_USER,
    DeletedAt           DATETIME2(7)        NULL,

    CONSTRAINT PK_BusinessContacts
        PRIMARY KEY CLUSTERED (BusinessContactID),
    CONSTRAINT FK_BusinessContacts_BusinessAccounts
        FOREIGN KEY (BusinessAccountID) REFERENCES dbo.BusinessAccounts (BusinessAccountID)
);
GO

CREATE TABLE dbo.BusinessAccountAddresses (
    BusinessAccountAddressID    INT             NOT NULL    IDENTITY(1,1),
    BusinessAccountID           INT             NOT NULL,
    AddressID                   INT             NOT NULL,
    AddressRole                 NVARCHAR(30)    NOT NULL,
    IsPrimary                   BIT             NOT NULL    CONSTRAINT DF_BAA_IsPrimary DEFAULT 0,

    CreatedAt   DATETIME2(7)    NOT NULL    CONSTRAINT DF_BAA_CreatedAt  DEFAULT SYSUTCDATETIME(),
    CreatedBy   NVARCHAR(100)   NOT NULL    CONSTRAINT DF_BAA_CreatedBy  DEFAULT SYSTEM_USER,
    ModifiedAt  DATETIME2(7)    NOT NULL    CONSTRAINT DF_BAA_ModifiedAt DEFAULT SYSUTCDATETIME(),
    ModifiedBy  NVARCHAR(100)   NOT NULL    CONSTRAINT DF_BAA_ModifiedBy DEFAULT SYSTEM_USER,

    CONSTRAINT PK_BusinessAccountAddresses
        PRIMARY KEY CLUSTERED (BusinessAccountAddressID),
    CONSTRAINT FK_BAA_BusinessAccounts
        FOREIGN KEY (BusinessAccountID) REFERENCES dbo.BusinessAccounts (BusinessAccountID),
    CONSTRAINT FK_BAA_Addresses
        FOREIGN KEY (AddressID) REFERENCES dbo.Addresses (AddressID),
    CONSTRAINT UQ_BAA_Composite
        UNIQUE (BusinessAccountID, AddressID, AddressRole),
    CONSTRAINT CK_BAA_AddressRole
        CHECK (AddressRole IN ('Billing','Warehouse','Pickup','Delivery','Other'))
);
GO


-- =============================================================================
-- CLUSTER 2: NETWORK
-- Tables: Facilities, ServiceZones, ZonePostalCodes, Routes
-- =============================================================================

CREATE TABLE dbo.Facilities (
    FacilityID          INT             NOT NULL    IDENTITY(1,1),
    FacilityCode        NVARCHAR(10)    NOT NULL,
    FacilityName        NVARCHAR(200)   NOT NULL,
    FacilityType        NVARCHAR(30)    NOT NULL,
    AddressID           INT             NOT NULL,
    ParentFacilityID    INT                 NULL,

    CreatedAt           DATETIME2(7)    NOT NULL    CONSTRAINT DF_Facilities_CreatedAt  DEFAULT SYSUTCDATETIME(),
    CreatedBy           NVARCHAR(100)   NOT NULL    CONSTRAINT DF_Facilities_CreatedBy  DEFAULT SYSTEM_USER,
    ModifiedAt          DATETIME2(7)    NOT NULL    CONSTRAINT DF_Facilities_ModifiedAt DEFAULT SYSUTCDATETIME(),
    ModifiedBy          NVARCHAR(100)   NOT NULL    CONSTRAINT DF_Facilities_ModifiedBy DEFAULT SYSTEM_USER,
    DeletedAt           DATETIME2(7)        NULL,

    CONSTRAINT PK_Facilities
        PRIMARY KEY CLUSTERED (FacilityID),
    CONSTRAINT UQ_Facilities_Code
        UNIQUE (FacilityCode),
    CONSTRAINT FK_Facilities_Addresses
        FOREIGN KEY (AddressID) REFERENCES dbo.Addresses (AddressID),
    CONSTRAINT CK_Facilities_Type
        CHECK (FacilityType IN ('Hub','Depot','RetailCounter'))
);
GO

ALTER TABLE dbo.Facilities
    ADD CONSTRAINT FK_Facilities_Parent
        FOREIGN KEY (ParentFacilityID) REFERENCES dbo.Facilities (FacilityID);
GO

CREATE TABLE dbo.ServiceZones (
    ServiceZoneID   INT             NOT NULL    IDENTITY(1,1),
    ZoneCode        NVARCHAR(10)    NOT NULL,
    ZoneName        NVARCHAR(100)   NOT NULL,
    CountryCode     CHAR(2)         NOT NULL,

    CreatedAt       DATETIME2(7)    NOT NULL    CONSTRAINT DF_SZ_CreatedAt  DEFAULT SYSUTCDATETIME(),
    CreatedBy       NVARCHAR(100)   NOT NULL    CONSTRAINT DF_SZ_CreatedBy  DEFAULT SYSTEM_USER,
    ModifiedAt      DATETIME2(7)    NOT NULL    CONSTRAINT DF_SZ_ModifiedAt DEFAULT SYSUTCDATETIME(),
    ModifiedBy      NVARCHAR(100)   NOT NULL    CONSTRAINT DF_SZ_ModifiedBy DEFAULT SYSTEM_USER,

    CONSTRAINT PK_ServiceZones
        PRIMARY KEY CLUSTERED (ServiceZoneID),
    CONSTRAINT UQ_ServiceZones_Code
        UNIQUE (ZoneCode)
);
GO

CREATE TABLE dbo.ZonePostalCodes (
    ZonePostalCodeID    INT             NOT NULL    IDENTITY(1,1),
    ServiceZoneID       INT             NOT NULL,
    MinPostalCode       NVARCHAR(20)    NOT NULL,
    MaxPostalCode       NVARCHAR(20)    NOT NULL,

    CreatedAt           DATETIME2(7)    NOT NULL    CONSTRAINT DF_ZPC_CreatedAt  DEFAULT SYSUTCDATETIME(),
    CreatedBy           NVARCHAR(100)   NOT NULL    CONSTRAINT DF_ZPC_CreatedBy  DEFAULT SYSTEM_USER,
    ModifiedAt          DATETIME2(7)    NOT NULL    CONSTRAINT DF_ZPC_ModifiedAt DEFAULT SYSUTCDATETIME(),
    ModifiedBy          NVARCHAR(100)   NOT NULL    CONSTRAINT DF_ZPC_ModifiedBy DEFAULT SYSTEM_USER,

    CONSTRAINT PK_ZonePostalCodes
        PRIMARY KEY CLUSTERED (ZonePostalCodeID),
    CONSTRAINT FK_ZPC_ServiceZones
        FOREIGN KEY (ServiceZoneID) REFERENCES dbo.ServiceZones (ServiceZoneID),
    CONSTRAINT CK_ZPC_Range
        CHECK (MinPostalCode <= MaxPostalCode)
);
GO

CREATE TABLE dbo.Routes (
    RouteID                 INT             NOT NULL    IDENTITY(1,1),
    RouteCode               NVARCHAR(20)    NOT NULL,
    OriginFacilityID        INT             NOT NULL,
    DestinationFacilityID   INT             NOT NULL,
    ServiceTier             NVARCHAR(20)    NOT NULL,
    EstimatedTransitDays    INT             NOT NULL,
    IsActive                BIT             NOT NULL    CONSTRAINT DF_Routes_IsActive DEFAULT 1,

    CreatedAt               DATETIME2(7)    NOT NULL    CONSTRAINT DF_Routes_CreatedAt  DEFAULT SYSUTCDATETIME(),
    CreatedBy               NVARCHAR(100)   NOT NULL    CONSTRAINT DF_Routes_CreatedBy  DEFAULT SYSTEM_USER,
    ModifiedAt              DATETIME2(7)    NOT NULL    CONSTRAINT DF_Routes_ModifiedAt DEFAULT SYSUTCDATETIME(),
    ModifiedBy              NVARCHAR(100)   NOT NULL    CONSTRAINT DF_Routes_ModifiedBy DEFAULT SYSTEM_USER,

    CONSTRAINT PK_Routes
        PRIMARY KEY CLUSTERED (RouteID),
    CONSTRAINT UQ_Routes_Code
        UNIQUE (RouteCode),
    CONSTRAINT FK_Routes_Origin
        FOREIGN KEY (OriginFacilityID) REFERENCES dbo.Facilities (FacilityID),
    CONSTRAINT FK_Routes_Destination
        FOREIGN KEY (DestinationFacilityID) REFERENCES dbo.Facilities (FacilityID),
    CONSTRAINT CK_Routes_DifferentFacilities
        CHECK (OriginFacilityID <> DestinationFacilityID),
    CONSTRAINT CK_Routes_TransitDays
        CHECK (EstimatedTransitDays >= 1),
    CONSTRAINT CK_Routes_ServiceTier
        CHECK (ServiceTier IN ('Ground','Express','Freight'))
);
GO


-- =============================================================================
-- CLUSTER 3: SHIPMENTS
-- Tables: Shipments, Packages, FreightBills, Pallets, TrackingEvents
-- =============================================================================

CREATE TABLE dbo.Shipments (
    ShipmentID              INT             NOT NULL    IDENTITY(1,1),
    TrackingNumber          NCHAR(18)       NOT NULL,
    ServiceTier             NVARCHAR(20)    NOT NULL,

    SenderCustomerID        INT                 NULL,
    SenderBusinessAccountID INT                 NULL,

    OriginAddressID         INT             NOT NULL,
    DestinationAddressID    INT             NOT NULL,

    IsCrossBorder               BIT             NOT NULL    CONSTRAINT DF_Shipments_CrossBorder DEFAULT 0,
    CustomsDeclarationValue     DECIMAL(12,2)       NULL,
    CustomsCurrency             CHAR(3)             NULL,
    DutiesAmount                DECIMAL(12,2)       NULL,
    CustomsClearedAt            DATETIME2(7)        NULL,

    ShipmentStatus          NVARCHAR(30)    NOT NULL    CONSTRAINT DF_Shipments_Status DEFAULT 'Created',

    RetailPaymentStatus     NVARCHAR(20)        NULL,
    RetailPaymentMethod     NVARCHAR(30)        NULL,
    RetailAmountCharged     DECIMAL(10,2)       NULL,
    RetailCurrency          CHAR(3)             NULL,

    CreatedAt               DATETIME2(7)    NOT NULL    CONSTRAINT DF_Shipments_CreatedAt  DEFAULT SYSUTCDATETIME(),
    CreatedBy               NVARCHAR(100)   NOT NULL    CONSTRAINT DF_Shipments_CreatedBy  DEFAULT SYSTEM_USER,
    ModifiedAt              DATETIME2(7)    NOT NULL    CONSTRAINT DF_Shipments_ModifiedAt DEFAULT SYSUTCDATETIME(),
    ModifiedBy              NVARCHAR(100)   NOT NULL    CONSTRAINT DF_Shipments_ModifiedBy DEFAULT SYSTEM_USER,
    DeletedAt               DATETIME2(7)        NULL,

    CONSTRAINT PK_Shipments
        PRIMARY KEY CLUSTERED (ShipmentID),
    CONSTRAINT UQ_Shipments_TrackingNumber
        UNIQUE (TrackingNumber),
    CONSTRAINT FK_Shipments_Customer
        FOREIGN KEY (SenderCustomerID) REFERENCES dbo.Customers (CustomerID),
    CONSTRAINT FK_Shipments_BusinessAccount
        FOREIGN KEY (SenderBusinessAccountID) REFERENCES dbo.BusinessAccounts (BusinessAccountID),
    CONSTRAINT FK_Shipments_OriginAddress
        FOREIGN KEY (OriginAddressID) REFERENCES dbo.Addresses (AddressID),
    CONSTRAINT FK_Shipments_DestinationAddress
        FOREIGN KEY (DestinationAddressID) REFERENCES dbo.Addresses (AddressID),
    CONSTRAINT CK_Shipments_SenderXOR CHECK (
        (SenderCustomerID IS NOT NULL AND SenderBusinessAccountID IS NULL)
        OR
        (SenderCustomerID IS NULL     AND SenderBusinessAccountID IS NOT NULL)
    ),
    CONSTRAINT CK_Shipments_AddressesDiffer
        CHECK (OriginAddressID <> DestinationAddressID),
    CONSTRAINT CK_Shipments_ServiceTier
        CHECK (ServiceTier IN ('Ground','Express','Freight')),
    CONSTRAINT CK_Shipments_Status CHECK (ShipmentStatus IN (
        'Created','PickedUp','InTransit','OutForDelivery',
        'Delivered','FailedDelivery','Returned','Cancelled'
    )),
    CONSTRAINT CK_Shipments_RetailPaymentStatus CHECK (
        RetailPaymentStatus IS NULL
        OR RetailPaymentStatus IN ('Pending','Paid','Refunded','Waived')
    )
);
GO

CREATE TABLE dbo.Packages (
    PackageID       INT             NOT NULL    IDENTITY(1,1),
    ShipmentID      INT             NOT NULL,
    TrackingNumber  NCHAR(18)       NOT NULL,
    ActualWeightKg  DECIMAL(8,2)    NOT NULL,
    LengthCm        DECIMAL(8,2)    NOT NULL,
    WidthCm         DECIMAL(8,2)    NOT NULL,
    HeightCm        DECIMAL(8,2)    NOT NULL,
    DimWeightKg     AS (CAST((LengthCm * WidthCm * HeightCm) / 5000.0 AS DECIMAL(8,2))) PERSISTED,
    PackageStatus   NVARCHAR(30)    NOT NULL    CONSTRAINT DF_Packages_Status DEFAULT 'Created',
    Notes           NVARCHAR(500)       NULL,

    CreatedAt       DATETIME2(7)    NOT NULL    CONSTRAINT DF_Packages_CreatedAt  DEFAULT SYSUTCDATETIME(),
    CreatedBy       NVARCHAR(100)   NOT NULL    CONSTRAINT DF_Packages_CreatedBy  DEFAULT SYSTEM_USER,
    ModifiedAt      DATETIME2(7)    NOT NULL    CONSTRAINT DF_Packages_ModifiedAt DEFAULT SYSUTCDATETIME(),
    ModifiedBy      NVARCHAR(100)   NOT NULL    CONSTRAINT DF_Packages_ModifiedBy DEFAULT SYSTEM_USER,
    DeletedAt       DATETIME2(7)        NULL,

    CONSTRAINT PK_Packages
        PRIMARY KEY CLUSTERED (PackageID),
    CONSTRAINT UQ_Packages_TrackingNumber
        UNIQUE (TrackingNumber),
    CONSTRAINT FK_Packages_Shipments
        FOREIGN KEY (ShipmentID) REFERENCES dbo.Shipments (ShipmentID),
    CONSTRAINT CK_Packages_Weight
        CHECK (ActualWeightKg > 0),
    CONSTRAINT CK_Packages_Dimensions
        CHECK (LengthCm > 0 AND WidthCm > 0 AND HeightCm > 0)
);
GO

CREATE TABLE dbo.FreightBills (
    FreightBillID       INT             NOT NULL    IDENTITY(1,1),
    ShipmentID          INT             NOT NULL,
    BillOfLadingNumber  NVARCHAR(30)    NOT NULL,
    TotalWeightKg       DECIMAL(10,2)   NOT NULL,
    TotalPallets        INT             NOT NULL,
    HazmatFlag          BIT             NOT NULL    CONSTRAINT DF_FB_Hazmat DEFAULT 0,
    SpecialInstructions NVARCHAR(1000)      NULL,

    CreatedAt           DATETIME2(7)    NOT NULL    CONSTRAINT DF_FB_CreatedAt  DEFAULT SYSUTCDATETIME(),
    CreatedBy           NVARCHAR(100)   NOT NULL    CONSTRAINT DF_FB_CreatedBy  DEFAULT SYSTEM_USER,
    ModifiedAt          DATETIME2(7)    NOT NULL    CONSTRAINT DF_FB_ModifiedAt DEFAULT SYSUTCDATETIME(),
    ModifiedBy          NVARCHAR(100)   NOT NULL    CONSTRAINT DF_FB_ModifiedBy DEFAULT SYSTEM_USER,
    DeletedAt           DATETIME2(7)        NULL,

    CONSTRAINT PK_FreightBills
        PRIMARY KEY CLUSTERED (FreightBillID),
    CONSTRAINT UQ_FreightBills_ShipmentID
        UNIQUE (ShipmentID),
    CONSTRAINT UQ_FreightBills_BOL
        UNIQUE (BillOfLadingNumber),
    CONSTRAINT FK_FreightBills_Shipments
        FOREIGN KEY (ShipmentID) REFERENCES dbo.Shipments (ShipmentID),
    CONSTRAINT CK_FreightBills_Weight
        CHECK (TotalWeightKg > 0),
    CONSTRAINT CK_FreightBills_Pallets
        CHECK (TotalPallets >= 1)
);
GO

CREATE TABLE dbo.Pallets (
    PalletID        INT             NOT NULL    IDENTITY(1,1),
    FreightBillID   INT             NOT NULL,
    PalletNumber    INT             NOT NULL,
    WeightKg        DECIMAL(8,2)    NOT NULL,
    Description     NVARCHAR(500)       NULL,
    HazmatFlag      BIT             NOT NULL    CONSTRAINT DF_Pallets_Hazmat DEFAULT 0,

    CreatedAt       DATETIME2(7)    NOT NULL    CONSTRAINT DF_Pallets_CreatedAt  DEFAULT SYSUTCDATETIME(),
    CreatedBy       NVARCHAR(100)   NOT NULL    CONSTRAINT DF_Pallets_CreatedBy  DEFAULT SYSTEM_USER,
    ModifiedAt      DATETIME2(7)    NOT NULL    CONSTRAINT DF_Pallets_ModifiedAt DEFAULT SYSUTCDATETIME(),
    ModifiedBy      NVARCHAR(100)   NOT NULL    CONSTRAINT DF_Pallets_ModifiedBy DEFAULT SYSTEM_USER,
    DeletedAt       DATETIME2(7)        NULL,

    CONSTRAINT PK_Pallets
        PRIMARY KEY CLUSTERED (PalletID),
    CONSTRAINT FK_Pallets_FreightBills
        FOREIGN KEY (FreightBillID) REFERENCES dbo.FreightBills (FreightBillID),
    CONSTRAINT UQ_Pallets_Number
        UNIQUE (FreightBillID, PalletNumber),
    CONSTRAINT CK_Pallets_Weight
        CHECK (WeightKg > 0)
);
GO

CREATE TABLE dbo.TrackingEvents (
    TrackingEventID     BIGINT          NOT NULL    IDENTITY(1,1),
    PackageID           INT                 NULL,
    PalletID            INT                 NULL,
    EntityType          NVARCHAR(10)    NOT NULL,
    FacilityID          INT             NOT NULL,
    EventCode           NVARCHAR(30)    NOT NULL,
    EventTimestamp      DATETIME2(7)    NOT NULL,
    StatusDescription   NVARCHAR(500)       NULL,
    OperatorEmployeeID  INT                 NULL,

    CreatedAt           DATETIME2(7)    NOT NULL    CONSTRAINT DF_TE_CreatedAt DEFAULT SYSUTCDATETIME(),
    CreatedBy           NVARCHAR(100)   NOT NULL    CONSTRAINT DF_TE_CreatedBy DEFAULT SYSTEM_USER,

    CONSTRAINT PK_TrackingEvents
        PRIMARY KEY CLUSTERED (TrackingEventID),
    CONSTRAINT FK_TrackingEvents_Packages
        FOREIGN KEY (PackageID) REFERENCES dbo.Packages (PackageID),
    CONSTRAINT FK_TrackingEvents_Pallets
        FOREIGN KEY (PalletID) REFERENCES dbo.Pallets (PalletID),
    CONSTRAINT FK_TrackingEvents_Facilities
        FOREIGN KEY (FacilityID) REFERENCES dbo.Facilities (FacilityID),
    CONSTRAINT CK_TrackingEvents_EntityXOR CHECK (
        (PackageID IS NOT NULL AND PalletID IS NULL AND EntityType = 'Package')
        OR
        (PalletID  IS NOT NULL AND PackageID IS NULL AND EntityType = 'Pallet')
    ),
    CONSTRAINT CK_TrackingEvents_EventCode CHECK (EventCode IN (
        'PICKUP','SCAN_HUB','SCAN_DEPOT','OUT_FOR_DELIVERY',
        'DELIVERED','FAILED_DELIVERY','CUSTOMS_HOLD','CUSTOMS_CLEARED',
        'RETURNED_TO_SENDER','DAMAGED','EXCEPTION'
    ))
);
GO


-- =============================================================================
-- CLUSTER 4: OPERATIONS
-- Tables: Employees, Drivers, Vehicles, Assignments
-- =============================================================================

CREATE TABLE dbo.Employees (
    EmployeeID          INT             NOT NULL    IDENTITY(1,1),
    EmployeeNumber      NVARCHAR(20)    NOT NULL,
    FirstName           NVARCHAR(100)   NOT NULL,
    LastName            NVARCHAR(100)   NOT NULL,
    Email               NVARCHAR(200)   NOT NULL,
    Phone               NVARCHAR(30)        NULL,
    FacilityID          INT             NOT NULL,
    ManagerEmployeeID   INT                 NULL,
    JobTitle            NVARCHAR(100)   NOT NULL,
    HireDate            DATE            NOT NULL,
    TerminationDate     DATE                NULL,

    CreatedAt           DATETIME2(7)    NOT NULL    CONSTRAINT DF_Employees_CreatedAt  DEFAULT SYSUTCDATETIME(),
    CreatedBy           NVARCHAR(100)   NOT NULL    CONSTRAINT DF_Employees_CreatedBy  DEFAULT SYSTEM_USER,
    ModifiedAt          DATETIME2(7)    NOT NULL    CONSTRAINT DF_Employees_ModifiedAt DEFAULT SYSUTCDATETIME(),
    ModifiedBy          NVARCHAR(100)   NOT NULL    CONSTRAINT DF_Employees_ModifiedBy DEFAULT SYSTEM_USER,
    DeletedAt           DATETIME2(7)        NULL,

    CONSTRAINT PK_Employees
        PRIMARY KEY CLUSTERED (EmployeeID),
    CONSTRAINT UQ_Employees_Number
        UNIQUE (EmployeeNumber),
    CONSTRAINT UQ_Employees_Email
        UNIQUE (Email),
    CONSTRAINT FK_Employees_Facilities
        FOREIGN KEY (FacilityID) REFERENCES dbo.Facilities (FacilityID),
    CONSTRAINT CK_Employees_TerminationDate
        CHECK (TerminationDate IS NULL OR TerminationDate >= HireDate)
);
GO

ALTER TABLE dbo.Employees
    ADD CONSTRAINT FK_Employees_Manager
        FOREIGN KEY (ManagerEmployeeID) REFERENCES dbo.Employees (EmployeeID);
GO

ALTER TABLE dbo.TrackingEvents
    ADD CONSTRAINT FK_TrackingEvents_Employees
        FOREIGN KEY (OperatorEmployeeID) REFERENCES dbo.Employees (EmployeeID);
GO

CREATE TABLE dbo.Drivers (
    EmployeeID      INT             NOT NULL,
    LicenseClass    NVARCHAR(10)    NOT NULL,
    LicenseNumber   NVARCHAR(50)    NOT NULL,
    LicenseExpiry   DATE            NOT NULL,
    LicenseState    CHAR(2)         NOT NULL,

    CreatedAt       DATETIME2(7)    NOT NULL    CONSTRAINT DF_Drivers_CreatedAt  DEFAULT SYSUTCDATETIME(),
    CreatedBy       NVARCHAR(100)   NOT NULL    CONSTRAINT DF_Drivers_CreatedBy  DEFAULT SYSTEM_USER,
    ModifiedAt      DATETIME2(7)    NOT NULL    CONSTRAINT DF_Drivers_ModifiedAt DEFAULT SYSUTCDATETIME(),
    ModifiedBy      NVARCHAR(100)   NOT NULL    CONSTRAINT DF_Drivers_ModifiedBy DEFAULT SYSTEM_USER,
    DeletedAt       DATETIME2(7)        NULL,

    CONSTRAINT PK_Drivers
        PRIMARY KEY CLUSTERED (EmployeeID),
    CONSTRAINT FK_Drivers_Employees
        FOREIGN KEY (EmployeeID) REFERENCES dbo.Employees (EmployeeID)
);
GO

CREATE TABLE dbo.Vehicles (
    VehicleID               INT             NOT NULL    IDENTITY(1,1),
    LicensePlate            NVARCHAR(20)    NOT NULL,
    LicensePlateState       CHAR(2)         NOT NULL,
    VehicleType             NVARCHAR(30)    NOT NULL,
    CapacityClass           NVARCHAR(20)    NOT NULL,
    MaxPayloadKg            DECIMAL(10,2)   NOT NULL,
    HomeBaseFacilityID      INT             NOT NULL,
    VehicleStatus           NVARCHAR(20)    NOT NULL    CONSTRAINT DF_Vehicles_Status DEFAULT 'Available',
    Year                    SMALLINT            NULL,
    Make                    NVARCHAR(50)        NULL,
    Model                   NVARCHAR(50)        NULL,

    CreatedAt               DATETIME2(7)    NOT NULL    CONSTRAINT DF_Vehicles_CreatedAt  DEFAULT SYSUTCDATETIME(),
    CreatedBy               NVARCHAR(100)   NOT NULL    CONSTRAINT DF_Vehicles_CreatedBy  DEFAULT SYSTEM_USER,
    ModifiedAt              DATETIME2(7)    NOT NULL    CONSTRAINT DF_Vehicles_ModifiedAt DEFAULT SYSUTCDATETIME(),
    ModifiedBy              NVARCHAR(100)   NOT NULL    CONSTRAINT DF_Vehicles_ModifiedBy DEFAULT SYSTEM_USER,
    DeletedAt               DATETIME2(7)        NULL,

    CONSTRAINT PK_Vehicles
        PRIMARY KEY CLUSTERED (VehicleID),
    CONSTRAINT UQ_Vehicles_Plate
        UNIQUE (LicensePlate, LicensePlateState),
    CONSTRAINT FK_Vehicles_Facilities
        FOREIGN KEY (HomeBaseFacilityID) REFERENCES dbo.Facilities (FacilityID),
    CONSTRAINT CK_Vehicles_Type
        CHECK (VehicleType IN ('Cargo Van','Box Truck','Semi','Flatbed','Refrigerated')),
    CONSTRAINT CK_Vehicles_Capacity
        CHECK (CapacityClass IN ('Light','Medium','Heavy')),
    CONSTRAINT CK_Vehicles_Status
        CHECK (VehicleStatus IN ('Available','In Use','Maintenance','Retired')),
    CONSTRAINT CK_Vehicles_Payload
        CHECK (MaxPayloadKg > 0)
);
GO

CREATE TABLE dbo.Assignments (
    AssignmentID        INT             NOT NULL    IDENTITY(1,1),
    DriverID            INT             NOT NULL,
    VehicleID           INT             NOT NULL,
    RouteID             INT             NOT NULL,
    AssignmentDate      DATE            NOT NULL,
    ShiftStart          TIME(0)         NOT NULL,
    ShiftEnd            TIME(0)         NOT NULL,
    AssignmentStatus    NVARCHAR(20)    NOT NULL    CONSTRAINT DF_Assignments_Status DEFAULT 'Scheduled',
    Notes               NVARCHAR(500)       NULL,

    CreatedAt           DATETIME2(7)    NOT NULL    CONSTRAINT DF_Assignments_CreatedAt  DEFAULT SYSUTCDATETIME(),
    CreatedBy           NVARCHAR(100)   NOT NULL    CONSTRAINT DF_Assignments_CreatedBy  DEFAULT SYSTEM_USER,
    ModifiedAt          DATETIME2(7)    NOT NULL    CONSTRAINT DF_Assignments_ModifiedAt DEFAULT SYSUTCDATETIME(),
    ModifiedBy          NVARCHAR(100)   NOT NULL    CONSTRAINT DF_Assignments_ModifiedBy DEFAULT SYSTEM_USER,
    DeletedAt           DATETIME2(7)        NULL,

    CONSTRAINT PK_Assignments
        PRIMARY KEY CLUSTERED (AssignmentID),
    CONSTRAINT FK_Assignments_Drivers
        FOREIGN KEY (DriverID) REFERENCES dbo.Drivers (EmployeeID),
    CONSTRAINT FK_Assignments_Vehicles
        FOREIGN KEY (VehicleID) REFERENCES dbo.Vehicles (VehicleID),
    CONSTRAINT FK_Assignments_Routes
        FOREIGN KEY (RouteID) REFERENCES dbo.Routes (RouteID),
    CONSTRAINT CK_Assignments_Shift
        CHECK (ShiftEnd > ShiftStart),
    CONSTRAINT CK_Assignments_Status
        CHECK (AssignmentStatus IN ('Scheduled','Active','Completed','Cancelled'))
);
GO


-- =============================================================================
-- CLUSTER 5: COMMERCIAL
-- Tables: RateCards, Invoices, InvoiceLineItems, Payments
-- =============================================================================

CREATE TABLE dbo.RateCards (
    RateCardID          INT             NOT NULL    IDENTITY(1,1),
    ServiceTier         NVARCHAR(20)    NOT NULL,
    OriginZoneID        INT             NOT NULL,
    DestinationZoneID   INT             NOT NULL,
    MinWeightKg         DECIMAL(8,2)    NOT NULL,
    MaxWeightKg         DECIMAL(8,2)    NOT NULL,
    BaseRate            DECIMAL(10,2)   NOT NULL,
    RateCurrency        CHAR(3)         NOT NULL    CONSTRAINT DF_RC_Currency  DEFAULT 'USD',
    PerKgSurcharge      DECIMAL(8,4)    NOT NULL    CONSTRAINT DF_RC_Surcharge DEFAULT 0,
    EffectiveFrom       DATE            NOT NULL,
    EffectiveTo         DATE                NULL,

    CreatedAt           DATETIME2(7)    NOT NULL    CONSTRAINT DF_RC_CreatedAt  DEFAULT SYSUTCDATETIME(),
    CreatedBy           NVARCHAR(100)   NOT NULL    CONSTRAINT DF_RC_CreatedBy  DEFAULT SYSTEM_USER,
    ModifiedAt          DATETIME2(7)    NOT NULL    CONSTRAINT DF_RC_ModifiedAt DEFAULT SYSUTCDATETIME(),
    ModifiedBy          NVARCHAR(100)   NOT NULL    CONSTRAINT DF_RC_ModifiedBy DEFAULT SYSTEM_USER,
    DeletedAt           DATETIME2(7)        NULL,

    CONSTRAINT PK_RateCards
        PRIMARY KEY CLUSTERED (RateCardID),
    CONSTRAINT FK_RateCards_OriginZone
        FOREIGN KEY (OriginZoneID) REFERENCES dbo.ServiceZones (ServiceZoneID),
    CONSTRAINT FK_RateCards_DestinationZone
        FOREIGN KEY (DestinationZoneID) REFERENCES dbo.ServiceZones (ServiceZoneID),
    CONSTRAINT CK_RateCards_ServiceTier
        CHECK (ServiceTier IN ('Ground','Express','Freight')),
    CONSTRAINT CK_RateCards_WeightBand
        CHECK (MinWeightKg >= 0 AND MaxWeightKg > MinWeightKg),
    CONSTRAINT CK_RateCards_BaseRate
        CHECK (BaseRate >= 0),
    CONSTRAINT CK_RateCards_EffectiveDates
        CHECK (EffectiveTo IS NULL OR EffectiveTo >= EffectiveFrom)
);
GO

CREATE TABLE dbo.Invoices (
    InvoiceID           INT             NOT NULL    IDENTITY(1,1),
    InvoiceNumber       NVARCHAR(30)    NOT NULL,
    BusinessAccountID   INT             NOT NULL,
    InvoiceDate         DATE            NOT NULL,
    DueDate             DATE            NOT NULL,
    TotalAmount         DECIMAL(12,2)   NOT NULL,
    CurrencyCode        CHAR(3)         NOT NULL,
    ExchangeRateToUSD   DECIMAL(10,6)   NOT NULL    CONSTRAINT DF_Invoices_ExRate  DEFAULT 1.000000,
    InvoiceStatus       NVARCHAR(20)    NOT NULL    CONSTRAINT DF_Invoices_Status  DEFAULT 'Draft',
    Notes               NVARCHAR(1000)      NULL,

    CreatedAt           DATETIME2(7)    NOT NULL    CONSTRAINT DF_Invoices_CreatedAt  DEFAULT SYSUTCDATETIME(),
    CreatedBy           NVARCHAR(100)   NOT NULL    CONSTRAINT DF_Invoices_CreatedBy  DEFAULT SYSTEM_USER,
    ModifiedAt          DATETIME2(7)    NOT NULL    CONSTRAINT DF_Invoices_ModifiedAt DEFAULT SYSUTCDATETIME(),
    ModifiedBy          NVARCHAR(100)   NOT NULL    CONSTRAINT DF_Invoices_ModifiedBy DEFAULT SYSTEM_USER,
    DeletedAt           DATETIME2(7)        NULL,

    CONSTRAINT PK_Invoices
        PRIMARY KEY CLUSTERED (InvoiceID),
    CONSTRAINT UQ_Invoices_Number
        UNIQUE (InvoiceNumber),
    CONSTRAINT FK_Invoices_BusinessAccounts
        FOREIGN KEY (BusinessAccountID) REFERENCES dbo.BusinessAccounts (BusinessAccountID),
    CONSTRAINT CK_Invoices_DueDate
        CHECK (DueDate >= InvoiceDate),
    CONSTRAINT CK_Invoices_TotalAmount
        CHECK (TotalAmount >= 0),
    CONSTRAINT CK_Invoices_Status CHECK (InvoiceStatus IN (
        'Draft','Issued','PartiallyPaid','Paid','Overdue','Cancelled','Disputed'
    ))
);
GO

CREATE TABLE dbo.InvoiceLineItems (
    InvoiceLineItemID   INT             NOT NULL    IDENTITY(1,1),
    InvoiceID           INT             NOT NULL,
    ShipmentID          INT             NOT NULL,
    LineDescription     NVARCHAR(200)       NULL,
    LineAmount          DECIMAL(10,2)   NOT NULL,
    CurrencyCode        CHAR(3)         NOT NULL,

    CreatedAt           DATETIME2(7)    NOT NULL    CONSTRAINT DF_ILI_CreatedAt  DEFAULT SYSUTCDATETIME(),
    CreatedBy           NVARCHAR(100)   NOT NULL    CONSTRAINT DF_ILI_CreatedBy  DEFAULT SYSTEM_USER,
    ModifiedAt          DATETIME2(7)    NOT NULL    CONSTRAINT DF_ILI_ModifiedAt DEFAULT SYSUTCDATETIME(),
    ModifiedBy          NVARCHAR(100)   NOT NULL    CONSTRAINT DF_ILI_ModifiedBy DEFAULT SYSTEM_USER,

    CONSTRAINT PK_InvoiceLineItems
        PRIMARY KEY CLUSTERED (InvoiceLineItemID),
    CONSTRAINT FK_ILI_Invoices
        FOREIGN KEY (InvoiceID) REFERENCES dbo.Invoices (InvoiceID),
    CONSTRAINT FK_ILI_Shipments
        FOREIGN KEY (ShipmentID) REFERENCES dbo.Shipments (ShipmentID),
    CONSTRAINT UQ_ILI_ShipmentPerInvoice
        UNIQUE (InvoiceID, ShipmentID),
    CONSTRAINT CK_ILI_LineAmount
        CHECK (LineAmount >= 0)
);
GO

CREATE TABLE dbo.Payments (
    PaymentID           INT             NOT NULL    IDENTITY(1,1),
    InvoiceID           INT             NOT NULL,
    PaymentDate         DATE            NOT NULL,
    AmountPaid          DECIMAL(12,2)   NOT NULL,
    CurrencyCode        CHAR(3)         NOT NULL,
    ExchangeRateToUSD   DECIMAL(10,6)   NOT NULL    CONSTRAINT DF_Payments_ExRate DEFAULT 1.000000,
    PaymentMethod       NVARCHAR(50)    NOT NULL,
    PaymentReference    NVARCHAR(100)       NULL,
    Notes               NVARCHAR(500)       NULL,

    CreatedAt           DATETIME2(7)    NOT NULL    CONSTRAINT DF_Payments_CreatedAt  DEFAULT SYSUTCDATETIME(),
    CreatedBy           NVARCHAR(100)   NOT NULL    CONSTRAINT DF_Payments_CreatedBy  DEFAULT SYSTEM_USER,
    ModifiedAt          DATETIME2(7)    NOT NULL    CONSTRAINT DF_Payments_ModifiedAt DEFAULT SYSUTCDATETIME(),
    ModifiedBy          NVARCHAR(100)   NOT NULL    CONSTRAINT DF_Payments_ModifiedBy DEFAULT SYSTEM_USER,
    DeletedAt           DATETIME2(7)        NULL,

    CONSTRAINT PK_Payments
        PRIMARY KEY CLUSTERED (PaymentID),
    CONSTRAINT FK_Payments_Invoices
        FOREIGN KEY (InvoiceID) REFERENCES dbo.Invoices (InvoiceID),
    CONSTRAINT CK_Payments_Amount
        CHECK (AmountPaid > 0),
    CONSTRAINT CK_Payments_Method
        CHECK (PaymentMethod IN ('ACH','Wire','Check','Credit Card','Cash','EFT','Other'))
);
GO


-- =============================================================================
-- RECOMMENDED INDEXES
-- =============================================================================

CREATE NONCLUSTERED INDEX IX_Customers_Active_Name
    ON dbo.Customers (LastName, FirstName)
    WHERE DeletedAt IS NULL;

CREATE NONCLUSTERED INDEX IX_BusinessAccounts_Active_Name
    ON dbo.BusinessAccounts (AccountName)
    WHERE DeletedAt IS NULL;

CREATE NONCLUSTERED INDEX IX_ZonePostalCodes_Range
    ON dbo.ZonePostalCodes (ServiceZoneID, MinPostalCode, MaxPostalCode);

CREATE NONCLUSTERED INDEX IX_Facilities_Type_Active
    ON dbo.Facilities (FacilityType, FacilityCode)
    WHERE DeletedAt IS NULL;

CREATE NONCLUSTERED INDEX IX_Shipments_Status_Created
    ON dbo.Shipments (ShipmentStatus, CreatedAt DESC)
    INCLUDE (TrackingNumber, ServiceTier, SenderCustomerID, SenderBusinessAccountID)
    WHERE DeletedAt IS NULL;

CREATE NONCLUSTERED INDEX IX_Shipments_BusinessAccount_Date
    ON dbo.Shipments (SenderBusinessAccountID, CreatedAt DESC)
    WHERE SenderBusinessAccountID IS NOT NULL AND DeletedAt IS NULL;

CREATE NONCLUSTERED INDEX IX_TrackingEvents_Package_Time
    ON dbo.TrackingEvents (PackageID, EventTimestamp DESC)
    INCLUDE (EventCode, StatusDescription, FacilityID)
    WHERE PackageID IS NOT NULL;

CREATE NONCLUSTERED INDEX IX_TrackingEvents_Pallet_Time
    ON dbo.TrackingEvents (PalletID, EventTimestamp DESC)
    INCLUDE (EventCode, StatusDescription, FacilityID)
    WHERE PalletID IS NOT NULL;

CREATE NONCLUSTERED INDEX IX_TrackingEvents_Facility_Time
    ON dbo.TrackingEvents (FacilityID, EventTimestamp DESC)
    INCLUDE (EventCode, EntityType);

CREATE NONCLUSTERED INDEX IX_RateCards_Lookup
    ON dbo.RateCards (ServiceTier, OriginZoneID, DestinationZoneID, EffectiveFrom)
    INCLUDE (MinWeightKg, MaxWeightKg, BaseRate, PerKgSurcharge, RateCurrency)
    WHERE DeletedAt IS NULL;

CREATE NONCLUSTERED INDEX IX_Invoices_Account_Date
    ON dbo.Invoices (BusinessAccountID, InvoiceDate DESC)
    INCLUDE (InvoiceNumber, TotalAmount, CurrencyCode, InvoiceStatus)
    WHERE DeletedAt IS NULL;

CREATE NONCLUSTERED INDEX IX_Assignments_Date_Driver
    ON dbo.Assignments (AssignmentDate, DriverID)
    INCLUDE (VehicleID, RouteID, ShiftStart, ShiftEnd, AssignmentStatus)
    WHERE DeletedAt IS NULL;

GO

PRINT '=============================================================================';
PRINT 'TarLogistics DDL completed successfully.';
PRINT 'Objects created: 1 database, 1 sequence, 21 tables, 11 nonclustered indexes';
PRINT '=============================================================================';
GO
