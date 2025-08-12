USE DWTailspin;

SELECT 
    COUNT(*) AS total_filas,
    MIN([date]) AS fecha_min,
    MAX([date]) AS fecha_max
FROM dbo.dim_tiempo;

SELECT TOP (10) *
FROM dbo.dim_tiempo
ORDER BY [date] ASC;

SELECT TOP (10) [date], day_name, is_weekend
FROM dbo.dim_tiempo
WHERE is_weekend = 1
ORDER BY [date];


SELECT date_key, COUNT(*) AS repeticiones
FROM dbo.dim_tiempo
GROUP BY date_key
HAVING COUNT(*) > 1;
