/* orquestador.sql
   Orquesta la carga inicial del DW: tiempo, dimensiones SCD2 y hechos.
   Requisitos previos:
   - Ejecutado 00_create_dw_db_and_synonyms.sql (BD DWTailspin + sinónimos a TailspinToys2020-US)
   - Estructura de tablas: dim_tiempo, dim_producto, dim_estado, dim_venta_flags, fact_ventas
*/

USE [DWTailspin];
GO
SET NOCOUNT ON;
GO

/* ============================================================
   SP: sp_cargar_dim_tiempo
   Regenera la dimensión calendario (5 años mínimos)
   ============================================================ */
CREATE OR ALTER PROCEDURE dbo.sp_cargar_dim_tiempo
AS
BEGIN
    SET NOCOUNT ON;

    -- Rango recomendado: +/−1 año del histórico (2018-2020) → 2018 a 2022
    DECLARE @start_date DATE = '2018-01-01';
    DECLARE @end_date   DATE = '2022-12-31';

    TRUNCATE TABLE dbo.dim_tiempo;

    DECLARE @d DATE = @start_date;
    WHILE @d <= @end_date
    BEGIN
        INSERT dbo.dim_tiempo (
            date_key, [date], [year], [quarter], [month], [day],
            month_name, day_name, week_of_year, is_weekend
        )
        VALUES (
            CONVERT(INT, FORMAT(@d,'yyyyMMdd')),
            @d,
            YEAR(@d),
            DATEPART(QUARTER, @d),
            MONTH(@d),
            DAY(@d),
            DATENAME(MONTH, @d),
            DATENAME(WEEKDAY, @d),
            DATEPART(WEEK, @d),
            CASE WHEN DATENAME(WEEKDAY, @d) IN ('Saturday','Sunday') THEN 1 ELSE 0 END
        );
        SET @d = DATEADD(DAY, 1, @d);
    END
END
GO

/* ============================================================
   SP: sp_cargar_dim_producto (SCD2)
   Fuente: dbo.synProduct
   ============================================================ */
CREATE OR ALTER PROCEDURE dbo.sp_cargar_dim_producto
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ts_now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @max_dt DATETIME2(0) = '9999-12-31';

    ;WITH src AS (
        SELECT
            p.ProductID                                        AS product_id_nk,
            p.ProductSKU        COLLATE DATABASE_DEFAULT        AS product_sku,
            p.ProductName       COLLATE DATABASE_DEFAULT        AS product_name,
            p.ProductCategory   COLLATE DATABASE_DEFAULT        AS product_category,
            p.ItemGroup         COLLATE DATABASE_DEFAULT        AS item_group,
            p.KitType           COLLATE DATABASE_DEFAULT        AS kit_type,
            p.Channels,
            p.Demographic       COLLATE DATABASE_DEFAULT        AS demographic,
            p.RetailPrice,
            CAST(HASHBYTES('MD5',
                CONCAT(
                    N'|', p.ProductSKU       COLLATE DATABASE_DEFAULT,
                    N'|', p.ProductName      COLLATE DATABASE_DEFAULT,
                    N'|', p.ProductCategory  COLLATE DATABASE_DEFAULT,
                    N'|', p.ItemGroup        COLLATE DATABASE_DEFAULT,
                    N'|', p.KitType          COLLATE DATABASE_DEFAULT,
                    N'|', CONVERT(NVARCHAR(10), p.Channels),
                    N'|', p.Demographic      COLLATE DATABASE_DEFAULT,
                    N'|', CONVERT(NVARCHAR(32), p.RetailPrice)
                )
            ) AS VARBINARY(16)) AS hash_diff
        FROM dbo.synProduct p
    )
    -- Expira current si cambió
    UPDATE d
      SET d.end_date = @ts_now,
          d.is_current = 0
    FROM dbo.dim_producto d
    JOIN src s
      ON s.product_id_nk = d.product_id_nk
    WHERE d.is_current = 1
      AND d.hash_diff <> s.hash_diff;

    -- Inserta nuevas (nuevas NK o expiradas)
    INSERT dbo.dim_producto (
        product_id_nk, product_sku, product_name, product_category,
        item_group, kit_type, channels, demographic, retail_price,
        start_date, end_date, is_current, hash_diff
    )
    SELECT
        s.product_id_nk, s.product_sku, s.product_name, s.product_category,
        s.item_group, s.kit_type, s.Channels, s.demographic, s.RetailPrice,
        @ts_now, @max_dt, 1, s.hash_diff
    FROM src s
    LEFT JOIN dbo.dim_producto d
      ON d.product_id_nk = s.product_id_nk
     AND d.is_current = 1
    WHERE d.product_id_nk IS NULL;
END
GO

/* ============================================================
   SP: sp_cargar_dim_estado (SCD2)
   Fuente: dbo.synState + dbo.synRegion
   ============================================================ */
CREATE OR ALTER PROCEDURE dbo.sp_cargar_dim_estado
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ts_now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @max_dt DATETIME2(0) = '9999-12-31';

    ;WITH src AS (
        SELECT
            st.StateID                         AS state_id_nk,
            st.StateCode   COLLATE DATABASE_DEFAULT AS state_code,
            st.StateName   COLLATE DATABASE_DEFAULT AS state_name,
            st.TimeZone    COLLATE DATABASE_DEFAULT AS time_zone,
            r.RegionID,
            r.RegionName  COLLATE DATABASE_DEFAULT AS region_name,
            CAST(HASHBYTES('MD5',
                CONCAT(
                    N'|', st.StateCode   COLLATE DATABASE_DEFAULT,
                    N'|', st.StateName   COLLATE DATABASE_DEFAULT,
                    N'|', st.TimeZone    COLLATE DATABASE_DEFAULT,
                    N'|', CONVERT(NVARCHAR(10), r.RegionID),
                    N'|', r.RegionName   COLLATE DATABASE_DEFAULT
                )
            ) AS VARBINARY(16)) AS hash_diff
        FROM dbo.synState  st
        JOIN dbo.synRegion r
          ON r.RegionID = st.RegionID
    )
    -- Expira current si cambió
    UPDATE d
      SET d.end_date = @ts_now,
          d.is_current = 0
    FROM dbo.dim_estado d
    JOIN src s
      ON s.state_id_nk = d.state_id_nk
    WHERE d.is_current = 1
      AND d.hash_diff <> s.hash_diff;

    -- Inserta nuevas (nuevas NK o expiradas)
    INSERT dbo.dim_estado (
        state_id_nk, state_code, state_name, time_zone, region_id, region_name,
        start_date, end_date, is_current, hash_diff
    )
    SELECT
        s.state_id_nk, s.state_code, s.state_name, s.time_zone, s.RegionID, s.region_name,
        @ts_now, @max_dt, 1, s.hash_diff
    FROM src s
    LEFT JOIN dbo.dim_estado d
      ON d.state_id_nk = s.state_id_nk
     AND d.is_current = 1
    WHERE d.state_id_nk IS NULL;
END
GO

/* ============================================================
   SP: sp_cargar_dim_venta_flags (JUNK, combos actuales)
   Fuente: dbo.synSales
   ============================================================ */
CREATE OR ALTER PROCEDURE dbo.sp_cargar_dim_venta_flags
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ts_now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @max_dt DATETIME2(0) = '9999-12-31';

    ;WITH src AS (
        SELECT
            CASE WHEN s.PromotionCode IS NULL THEN NULL
                 ELSE s.PromotionCode COLLATE DATABASE_DEFAULT
            END AS promotion_code,
            CAST(CASE WHEN s.DiscountAmount > 0 THEN 1 ELSE 0 END AS BIT) AS has_discount,
            CAST(CASE WHEN s.PromotionCode IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS is_promo
        FROM dbo.synSales s
        GROUP BY
            CASE WHEN s.PromotionCode IS NULL THEN NULL
                 ELSE s.PromotionCode COLLATE DATABASE_DEFAULT
            END,
            CAST(CASE WHEN s.DiscountAmount > 0 THEN 1 ELSE 0 END AS BIT),
            CAST(CASE WHEN s.PromotionCode IS NOT NULL THEN 1 ELSE 0 END AS BIT)
    )
    INSERT dbo.dim_venta_flags (
        promotion_code, has_discount, is_promo,
        start_date, end_date, is_current, hash_diff
    )
    SELECT
        s.promotion_code, s.has_discount, s.is_promo,
        @ts_now, @max_dt, 1,
        CAST(HASHBYTES('MD5',
            CONCAT(
                N'|', COALESCE(s.promotion_code, N'<NULL>') COLLATE DATABASE_DEFAULT,
                N'|', CONVERT(NVARCHAR(1), s.has_discount),
                N'|', CONVERT(NVARCHAR(1), s.is_promo)
            )
        ) AS VARBINARY(16)) AS hash_diff
    FROM src s
    LEFT JOIN dbo.dim_venta_flags d
      ON ISNULL(d.promotion_code, N'<NULL>') = ISNULL(s.promotion_code, N'<NULL>')
     AND d.has_discount = s.has_discount
     AND d.is_promo     = s.is_promo
     AND d.is_current   = 1
    WHERE d.flags_key IS NULL;
END
GO

/* ============================================================
   SP: sp_cargar_fact_ventas (Carga inicial)
   Fuente: dbo.synVSalesExtract
   - Usa filas CURRENT de dimensiones
   - Recalcula claves de fecha
   ============================================================ */
CREATE OR ALTER PROCEDURE dbo.sp_cargar_fact_ventas
AS
BEGIN
    SET NOCOUNT ON;

    -- Estrategia: carga inicial → limpiar hechos
    TRUNCATE TABLE dbo.fact_ventas;

    INSERT dbo.fact_ventas (
        order_number, order_date_key, ship_date_key,
        product_key, state_key, flags_key,
        quantity, unit_price, discount_amount,
        gross_amount, net_amount
    )
    SELECT
        v.OrderNumber,
        CONVERT(INT, FORMAT(v.OrderDate,'yyyyMMdd')) AS order_date_key,
        CASE WHEN v.ShipDate IS NULL THEN NULL
             ELSE CONVERT(INT, FORMAT(v.ShipDate,'yyyyMMdd'))
        END AS ship_date_key,
        dp.product_key,
        de.state_key,
        dvf.flags_key,
        v.Quantity,
        v.UnitPrice,
        v.DiscountAmount,
        CAST(v.Quantity * v.UnitPrice AS DECIMAL(18,2))                      AS gross_amount,
        CAST(v.Quantity * v.UnitPrice - v.DiscountAmount AS DECIMAL(18,2))   AS net_amount
    FROM dbo.synVSalesExtract v
    -- Producto (CURRENT)
    JOIN dbo.dim_producto dp
      ON dp.product_id_nk = v.ProductID
     AND dp.is_current = 1
    -- Estado/Región (CURRENT)
    JOIN dbo.dim_estado de
      ON de.state_id_nk = v.StateID
     AND de.is_current = 1
    -- Flags (CURRENT) por combinación
    JOIN dbo.dim_venta_flags dvf
      ON ISNULL(dvf.promotion_code, N'<NULL>') = ISNULL(v.PromotionCode COLLATE DATABASE_DEFAULT, N'<NULL>')
     AND dvf.has_discount = CASE WHEN v.DiscountAmount > 0 THEN 1 ELSE 0 END
     AND dvf.is_promo     = CASE WHEN v.PromotionCode IS NOT NULL THEN 1 ELSE 0 END
     AND dvf.is_current   = 1
    -- Fechas deben existir en dim_tiempo
    JOIN dbo.dim_tiempo dt_o
      ON dt_o.date_key = CONVERT(INT, FORMAT(v.OrderDate,'yyyyMMdd'))
    LEFT JOIN dbo.dim_tiempo dt_s
      ON dt_s.date_key = CASE WHEN v.ShipDate IS NULL THEN NULL
                              ELSE CONVERT(INT, FORMAT(v.ShipDate,'yyyyMMdd'))
                         END;
END
GO

/* ============================================================
   SP MAESTRO: sp_etl_carga_inicial
   Ejecuta todos los pasos en orden
   ============================================================ */
CREATE OR ALTER PROCEDURE dbo.sp_etl_carga_inicial
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @t0 DATETIME2(0) = SYSDATETIME();
    PRINT '=== INICIO CARGA INICIAL DW === ' + CONVERT(VARCHAR(19), @t0, 120);

    EXEC dbo.sp_cargar_dim_tiempo;        PRINT 'OK: dim_tiempo';
    EXEC dbo.sp_cargar_dim_producto;      PRINT 'OK: dim_producto';
    EXEC dbo.sp_cargar_dim_estado;        PRINT 'OK: dim_estado';
    EXEC dbo.sp_cargar_dim_venta_flags;   PRINT 'OK: dim_venta_flags';
    EXEC dbo.sp_cargar_fact_ventas;       PRINT 'OK: fact_ventas';

    DECLARE @t1 DATETIME2(0) = SYSDATETIME();
    PRINT '=== FIN CARGA INICIAL DW === ' + CONVERT(VARCHAR(19), @t1, 120);
    PRINT 'Duración (seg): ' + CAST(DATEDIFF(SECOND, @t0, @t1) AS VARCHAR(20));
END
GO

