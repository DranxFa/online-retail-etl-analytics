-- =========================================================================
-- PROYECTO: Online Retail Analytics (Data Mart Kimball)
-- SCRIPT: 03_cohort_retention.sql
-- DESCRIPCIÓN: Análisis de Cohortes de Retención Mensual
--              Calcula la tasa de retención de clientes mes a mes (M+0 a M+12)
--              utilizando CTEs, Window Functions y agregación condicional.
-- =========================================================================

USE OnlineRetailDW;
GO

-- 1. Creamos una VISTA granular para que Power BI pueda graficar matrices o mapas de calor
CREATE OR ALTER VIEW vw_retencion_cohortes AS
WITH 
-- Paso 1: Encontrar la fecha de la primera compra de cada cliente (su Cohorte de inicio)
primera_compra AS (
    SELECT 
        f.sk_cliente,
        DATEFROMPARTS(YEAR(MIN(t.fecha)), MONTH(MIN(t.fecha)), 1) AS cohorte_mes
    FROM fact_ventas f
    INNER JOIN dim_tiempo t ON f.sk_fecha = t.sk_fecha
    WHERE f.is_cancellation = 0
      AND f.total_amount > 0
    GROUP BY f.sk_cliente
),

-- Paso 2: Extraer todos los meses en los que cada cliente realizó compras reales
compras_cliente AS (
    SELECT DISTINCT
        f.sk_cliente,
        DATEFROMPARTS(YEAR(t.fecha), MONTH(t.fecha), 1) AS compra_mes
    FROM fact_ventas f
    INNER JOIN dim_tiempo t ON f.sk_fecha = t.sk_fecha
    WHERE f.is_cancellation = 0
      AND f.total_amount > 0
),

-- Paso 3: Calcular el índice del periodo (M+0, M+1, M+2...)
periodos_cohorte AS (
    SELECT 
        c.sk_cliente,
        p.cohorte_mes,
        c.compra_mes,
        DATEDIFF(month, p.cohorte_mes, c.compra_mes) AS periodo_mes
    FROM compras_cliente c
    INNER JOIN primera_compra p ON c.sk_cliente = p.sk_cliente
),

-- Paso 4: Contar clientes únicos por cohorte y periodo
clientes_por_periodo AS (
    SELECT 
        cohorte_mes,
        periodo_mes,
        COUNT(DISTINCT sk_cliente) AS clientes_activos
    FROM periodos_cohorte
    GROUP BY cohorte_mes, periodo_mes
),

-- Paso 5: Obtener el tamaño inicial de la cohorte (Periodo 0) y calcular el % de retención
tamano_cohorte AS (
    SELECT 
        cohorte_mes,
        clientes_activos AS clientes_iniciales
    FROM clientes_por_periodo
    WHERE periodo_mes = 0
)
SELECT 
    cp.cohorte_mes,
    FORMAT(cp.cohorte_mes, 'yyyy-MM') AS cohorte_nombre,
    tc.clientes_iniciales,
    cp.periodo_mes,
    cp.clientes_activos,
    ROUND((cp.clientes_activos * 100.0) / tc.clientes_iniciales, 2) AS tasa_retencion_pct
FROM clientes_por_periodo cp
INNER JOIN tamano_cohorte tc ON cp.cohorte_mes = tc.cohorte_mes;
GO

-- =========================================================================
-- CONSULTA DE MATRIZ DE RETENCIÓN (Estilo Heatmap Clásico en SQL)
-- Muestra el % de retención desde el Mes 0 hasta el Mes 12 en columnas
-- =========================================================================
SELECT 
    cohorte_nombre,
    clientes_iniciales AS [M+0 (100%)],
    ISNULL(CAST(ROUND(MAX(CASE WHEN periodo_mes = 1 THEN tasa_retencion_pct END), 1) AS VARCHAR) + '%', '-') AS [M+1],
    ISNULL(CAST(ROUND(MAX(CASE WHEN periodo_mes = 2 THEN tasa_retencion_pct END), 1) AS VARCHAR) + '%', '-') AS [M+2],
    ISNULL(CAST(ROUND(MAX(CASE WHEN periodo_mes = 3 THEN tasa_retencion_pct END), 1) AS VARCHAR) + '%', '-') AS [M+3],
    ISNULL(CAST(ROUND(MAX(CASE WHEN periodo_mes = 4 THEN tasa_retencion_pct END), 1) AS VARCHAR) + '%', '-') AS [M+4],
    ISNULL(CAST(ROUND(MAX(CASE WHEN periodo_mes = 5 THEN tasa_retencion_pct END), 1) AS VARCHAR) + '%', '-') AS [M+5],
    ISNULL(CAST(ROUND(MAX(CASE WHEN periodo_mes = 6 THEN tasa_retencion_pct END), 1) AS VARCHAR) + '%', '-') AS [M+6],
    ISNULL(CAST(ROUND(MAX(CASE WHEN periodo_mes = 7 THEN tasa_retencion_pct END), 1) AS VARCHAR) + '%', '-') AS [M+7],
    ISNULL(CAST(ROUND(MAX(CASE WHEN periodo_mes = 8 THEN tasa_retencion_pct END), 1) AS VARCHAR) + '%', '-') AS [M+8],
    ISNULL(CAST(ROUND(MAX(CASE WHEN periodo_mes = 9 THEN tasa_retencion_pct END), 1) AS VARCHAR) + '%', '-') AS [M+9],
    ISNULL(CAST(ROUND(MAX(CASE WHEN periodo_mes = 10 THEN tasa_retencion_pct END), 1) AS VARCHAR) + '%', '-') AS [M+10],
    ISNULL(CAST(ROUND(MAX(CASE WHEN periodo_mes = 11 THEN tasa_retencion_pct END), 1) AS VARCHAR) + '%', '-') AS [M+11],
    ISNULL(CAST(ROUND(MAX(CASE WHEN periodo_mes = 12 THEN tasa_retencion_pct END), 1) AS VARCHAR) + '%', '-') AS [M+12]
FROM vw_retencion_cohortes
GROUP BY cohorte_nombre, clientes_iniciales
ORDER BY cohorte_nombre;
GO
