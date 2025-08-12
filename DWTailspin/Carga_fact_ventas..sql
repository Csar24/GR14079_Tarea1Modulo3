USE [DWTailspin];
SET NOCOUNT ON;

-- Carga inicial: limpiamos fact_ventas
TRUNCATE TABLE dbo.fact_ventas;

IF OBJECT_ID('tempdb..#src') IS NOT NULL DROP TABLE #src;

-- Extraemos y transformamos para unir con claves surrogate de dimensiones
SELECT
    s.OrderNumber,
    CONVERT(INT, FORMAT(s.OrderDate, 'yyyyMMdd')) AS order_date_key,
    CONVERT(INT, FORMAT(s.ShipDate, 'yyyyMMdd'))  AS ship_date_key,
    dp.product_key,
    de.state_key,
    dvf.flags_key,
    s.Quantity,
    s.UnitPrice,
    s.DiscountAmount,
    CAST(s.Quantity * s.UnitPrice AS DECIMAL(18,2))                  AS gross_amount,
    CAST((s.Quantity * s.UnitPrice) - s.DiscountAmount AS DECIMAL(18,2)) AS net_amount
INTO #src
FROM dbo.synSales s
JOIN dbo.dim_producto dp
  ON dp.product_id_nk = s.ProductID
 AND dp.is_current    = 1
JOIN dbo.dim_estado de
  ON de.state_id_nk = s.CustomerStateID
 AND de.is_current  = 1
JOIN dbo.dim_venta_flags dvf
  ON ISNULL(dvf.promotion_code, N'<NULL>') COLLATE DATABASE_DEFAULT
     = ISNULL(s.PromotionCode, N'<NULL>') COLLATE DATABASE_DEFAULT
 AND dvf.has_discount = CASE WHEN s.DiscountAmount > 0 THEN 1 ELSE 0 END
 AND dvf.is_promo     = CASE WHEN s.PromotionCode IS NOT NULL THEN 1 ELSE 0 END
 AND dvf.is_current   = 1;

-- Cargamos en fact_ventas
INSERT dbo.fact_ventas (
    order_number, order_date_key, ship_date_key,
    product_key, state_key, flags_key,
    quantity, unit_price, discount_amount, gross_amount, net_amount
)
SELECT
    OrderNumber, order_date_key, ship_date_key,
    product_key, state_key, flags_key,
    Quantity, UnitPrice, DiscountAmount, gross_amount, net_amount
FROM #src;

DROP TABLE #src;

PRINT 'Carga de fact_ventas completada.';
