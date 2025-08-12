/* 01_dim_time_build.sql
   Carga la dimensión tiempo con 5 años (ajustable).
*/
USE DWTailspin;
SET NOCOUNT ON;

-- RANGO AJUSTABLE
DECLARE @start_date DATE = '2018-01-01';
DECLARE @end_date   DATE = '2022-12-31';

-- Idempotente: borra rango si ya existe
DELETE FROM dbo.dim_tiempo
WHERE [date] BETWEEN @start_date AND @end_date;

;WITH d AS (
    SELECT @start_date AS [date]
    UNION ALL
    SELECT DATEADD(DAY, 1, [date]) FROM d
    WHERE [date] < @end_date
)
INSERT dbo.dim_tiempo (date_key, [date], [year], [quarter], [month], [day], month_name, day_name, week_of_year, is_weekend)
SELECT
    CONVERT(INT, FORMAT([date], 'yyyyMMdd')),
    [date],
    DATEPART(YEAR, [date]),
    DATEPART(QUARTER, [date]),
    DATEPART(MONTH, [date]),
    DATEPART(DAY, [date]),
    DATENAME(MONTH, [date]),
    DATENAME(WEEKDAY, [date]),
    DATEPART(WEEK, [date]),
    CASE WHEN DATEPART(WEEKDAY,[date]) IN (7,1) THEN 1 ELSE 0 END  -- domingo(1) y sábado(7) según @@DATEFIRST; ajustar si tu server difiere
FROM d
OPTION (MAXRECURSION 0);

PRINT 'OK: dim_tiempo cargada de ' + CONVERT(varchar(10), @start_date, 120) + ' a ' + CONVERT(varchar(10), @end_date, 120);
