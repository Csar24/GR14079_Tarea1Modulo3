USE [DWTailspin];
SET NOCOUNT ON;

PRINT '--- Resumen dimensiones ---';
SELECT 'dim_tiempo'      AS dim, COUNT(*) AS filas FROM dbo.dim_tiempo
UNION ALL
SELECT 'dim_producto'    AS dim, COUNT(*) FROM dbo.dim_producto    WHERE is_current = 1
UNION ALL
SELECT 'dim_estado'      AS dim, COUNT(*) FROM dbo.dim_estado      WHERE is_current = 1
UNION ALL
SELECT 'dim_venta_flags' AS dim, COUNT(*) FROM dbo.dim_venta_flags WHERE is_current = 1;
