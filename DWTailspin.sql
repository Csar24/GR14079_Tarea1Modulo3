/* 00_create_dw_db_and_synonyms.sql
   Crea la BD del DW, tablas base y sinónimos hacia la fuente.
   Requisitos: Base origen instalada como [TailspinToys2020-US] con tablas dbo.Product, dbo.State, dbo.Region, dbo.Sales y vista dbo.vSalesExtract
*/

-- === PARAMETROS (ajusta el nombre si tu base origen se llama distinto) ===
DECLARE @SRC_DB SYSNAME = N'TailspinToys2020-US';
DECLARE @DW_DB  SYSNAME = N'DWTailspin';

-- === CREA BD DW SI NO EXISTE ===
IF DB_ID(@DW_DB) IS NULL
BEGIN
    DECLARE @sql NVARCHAR(MAX) = N'CREATE DATABASE [' + @DW_DB + N'];';
    EXEC sys.sp_executesql @sql;
END;
PRINT 'OK: BD ' + @DW_DB + ' lista.';

-- === CONTEXTO DW ===
DECLARE @sqlUse NVARCHAR(MAX) = N'USE [' + @DW_DB + N'];';
EXEC sys.sp_executesql @sqlUse;

-- === LIMPIEZA PREVIA (OPCIONAL) ===
IF OBJECT_ID('dbo.fact_ventas') IS NOT NULL DROP TABLE dbo.fact_ventas;
IF OBJECT_ID('dbo.dim_venta_flags') IS NOT NULL DROP TABLE dbo.dim_venta_flags;
IF OBJECT_ID('dbo.dim_estado') IS NOT NULL DROP TABLE dbo.dim_estado;
IF OBJECT_ID('dbo.dim_producto') IS NOT NULL DROP TABLE dbo.dim_producto;
IF OBJECT_ID('dbo.dim_tiempo') IS NOT NULL DROP TABLE dbo.dim_tiempo;

-- Elimina sinónimos si existen
IF OBJECT_ID('dbo.synProduct', 'SN') IS NOT NULL DROP SYNONYM dbo.synProduct;
IF OBJECT_ID('dbo.synState',   'SN') IS NOT NULL DROP SYNONYM dbo.synState;
IF OBJECT_ID('dbo.synRegion',  'SN') IS NOT NULL DROP SYNONYM dbo.synRegion;
IF OBJECT_ID('dbo.synSales',   'SN') IS NOT NULL DROP SYNONYM dbo.synSales;
IF OBJECT_ID('dbo.synVSalesExtract','SN') IS NOT NULL DROP SYNONYM dbo.synVSalesExtract;

-- === CREA TABLAS DEL DW ===
-- Dimensión Tiempo
CREATE TABLE dbo.dim_tiempo (
    date_key       INT            NOT NULL PRIMARY KEY, -- YYYYMMDD
    [date]         DATE           NOT NULL,
    [year]         INT            NOT NULL,
    [quarter]      TINYINT        NOT NULL,
    [month]        TINYINT        NOT NULL,
    [day]          TINYINT        NOT NULL,
    month_name     NVARCHAR(20)   NOT NULL,
    day_name       NVARCHAR(20)   NOT NULL,
    week_of_year   TINYINT        NOT NULL,
    is_weekend     BIT            NOT NULL
);

-- Dimensión Producto (SCD2)
CREATE TABLE dbo.dim_producto (
    product_key        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dim_producto PRIMARY KEY,
    product_id_nk      INT         NOT NULL,  -- NK desde origen (ProductID)
    product_sku        NVARCHAR(50) NOT NULL,
    product_name       NVARCHAR(50) NOT NULL,
    product_category   NVARCHAR(50) NOT NULL,
    item_group         NVARCHAR(50) NOT NULL,
    kit_type           NCHAR(3)     NOT NULL,
    channels           TINYINT      NOT NULL,
    demographic        NVARCHAR(50) NOT NULL,
    retail_price       MONEY        NOT NULL,
    -- SCD2
    start_date         DATETIME2(0) NOT NULL,
    end_date           DATETIME2(0) NOT NULL,
    is_current         BIT          NOT NULL,
    hash_diff          VARBINARY(16) NOT NULL
);
-- índice filtrado para 1 fila current por NK
CREATE UNIQUE INDEX UX_dim_producto_current
ON dbo.dim_producto(product_id_nk)
WHERE is_current = 1;

-- Dimensión Estado/Región (SCD2)
CREATE TABLE dbo.dim_estado (
    state_key      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dim_estado PRIMARY KEY,
    state_id_nk    INT           NOT NULL, -- NK desde origen (StateID)
    state_code     NVARCHAR(2)   NOT NULL,
    state_name     NVARCHAR(50)  NOT NULL,
    time_zone      NVARCHAR(10)  NOT NULL,
    region_id      INT           NOT NULL,
    region_name    NVARCHAR(50)  NOT NULL,
    -- SCD2
    start_date     DATETIME2(0)  NOT NULL,
    end_date       DATETIME2(0)  NOT NULL,
    is_current     BIT           NOT NULL,
    hash_diff      VARBINARY(16) NOT NULL
);
CREATE UNIQUE INDEX UX_dim_estado_current
ON dbo.dim_estado(state_id_nk)
WHERE is_current = 1;

-- Dimensión Junk (promos/descuentos) (SCD2)
CREATE TABLE dbo.dim_venta_flags (
    flags_key       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dim_venta_flags PRIMARY KEY,
    promotion_code  NVARCHAR(20) NULL,
    has_discount    BIT          NOT NULL, -- DiscountAmount > 0
    is_promo        BIT          NOT NULL, -- PromotionCode NOT NULL
    -- SCD2
    start_date      DATETIME2(0) NOT NULL,
    end_date        DATETIME2(0) NOT NULL,
    is_current      BIT          NOT NULL,
    hash_diff       VARBINARY(16) NOT NULL
);
-- Para esta junk permitimos múltiples combos actuales, no unique por NK

-- Tabla de Hechos Ventas
CREATE TABLE dbo.fact_ventas (
    fact_id           BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_fact_ventas PRIMARY KEY,
    order_number      NCHAR(10) NOT NULL,               -- Degenerate Dimension (DD)
    order_date_key    INT       NOT NULL,               -- FK a dim_tiempo
    ship_date_key     INT       NULL,                   -- FK a dim_tiempo (nullable)
    product_key       INT       NOT NULL,               -- FK a dim_producto (current)
    state_key         INT       NOT NULL,               -- FK a dim_estado (current)
    flags_key         INT       NOT NULL,               -- FK a dim_venta_flags (current)
    quantity          INT       NOT NULL,
    unit_price        DECIMAL(9,2) NOT NULL,
    discount_amount   DECIMAL(9,2) NOT NULL,
    gross_amount      DECIMAL(18,2) NOT NULL,
    net_amount        DECIMAL(18,2) NOT NULL
);
CREATE INDEX IX_fact_ventas_dates   ON dbo.fact_ventas(order_date_key, ship_date_key);
CREATE INDEX IX_fact_ventas_prod    ON dbo.fact_ventas(product_key);
CREATE INDEX IX_fact_ventas_state   ON dbo.fact_ventas(state_key);

ALTER TABLE dbo.fact_ventas WITH CHECK
ADD CONSTRAINT FK_fact_tiempo_order FOREIGN KEY(order_date_key) REFERENCES dbo.dim_tiempo(date_key);
ALTER TABLE dbo.fact_ventas WITH CHECK
ADD CONSTRAINT FK_fact_tiempo_ship  FOREIGN KEY(ship_date_key) REFERENCES dbo.dim_tiempo(date_key);
ALTER TABLE dbo.fact_ventas WITH CHECK
ADD CONSTRAINT FK_fact_producto     FOREIGN KEY(product_key)   REFERENCES dbo.dim_producto(product_key);
ALTER TABLE dbo.fact_ventas WITH CHECK
ADD CONSTRAINT FK_fact_estado       FOREIGN KEY(state_key)     REFERENCES dbo.dim_estado(state_key);
ALTER TABLE dbo.fact_ventas WITH CHECK
ADD CONSTRAINT FK_fact_flags        FOREIGN KEY(flags_key)     REFERENCES dbo.dim_venta_flags(flags_key);

-- === CREA SINONIMOS A ORIGEN  ===
DECLARE @syn NVARCHAR(MAX);

SET @syn = N'CREATE SYNONYM dbo.synProduct FOR [' + @SRC_DB + N'].[dbo].[Product];';   EXEC (@syn);
SET @syn = N'CREATE SYNONYM dbo.synState   FOR [' + @SRC_DB + N'].[dbo].[State];';     EXEC (@syn);
SET @syn = N'CREATE SYNONYM dbo.synRegion  FOR [' + @SRC_DB + N'].[dbo].[Region];';    EXEC (@syn);
SET @syn = N'CREATE SYNONYM dbo.synSales   FOR [' + @SRC_DB + N'].[dbo].[Sales];';     EXEC (@syn);
SET @syn = N'CREATE SYNONYM dbo.synVSalesExtract FOR [' + @SRC_DB + N'].[dbo].[vSalesExtract];'; EXEC (@syn);

PRINT 'OK: Estructura DW + sinónimos creados.';
