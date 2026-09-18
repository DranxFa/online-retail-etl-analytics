-- =========================================================================
-- PROYECTO: Online Retail Analytics (Data Mart Kimball)
-- SCRIPT: 02_rfm_segmentation.sql
-- DESCRIPCIÓN: Segmentación RFM (Recency, Frequency, Monetary) de clientes
--              utilizando CTEs, Window Functions (NTILE) y CASE WHEN.
-- =========================================================================

USE OnlineRetailDW;
GO

-- Creamos una VISTA para que Power BI pueda consumirla directamente
CREATE OR ALTER VIEW vw_segmentacion_rfm AS
WITH 
-- CTE 1: Extraer métricas base por cliente (excluyendo cancelaciones para métricas puras)
metricas_cliente AS (
    SELECT 
        c.sk_cliente,
        c.customer_id,
        c.country,
        MAX(t.fecha) AS ultima_compra,
        -- Días de recencia respecto a la última fecha registrada en todo el dataset
        DATEDIFF(day, MAX(t.fecha), (SELECT MAX(fecha) FROM dim_tiempo t2 JOIN fact_ventas f2 ON t2.sk_fecha = f2.sk_fecha)) AS dias_recencia,
        COUNT(DISTINCT f.invoice_no) AS frecuencia_pedidos,
        ROUND(SUM(f.total_amount), 2) AS gasto_total
    FROM fact_ventas f
    INNER JOIN dim_cliente c ON f.sk_cliente = c.sk_cliente
    INNER JOIN dim_tiempo t ON f.sk_fecha = t.sk_fecha
    WHERE f.is_cancellation = 0  -- Solo compras reales efectivas
      AND f.total_amount > 0
    GROUP BY 
        c.sk_cliente,
        c.customer_id,
        c.country
),

-- CTE 2: Asignar puntajes de 1 a 5 usando NTILE(5)
-- Nota de diseño:
-- - Para Recencia: mayor fecha de compra = menor días de inactividad = Puntuación 5 (Mejor)
-- - Para Frecuencia y Monetario: mayores valores = Puntuación 5 (Mejor)
rfm_scores AS (
    SELECT 
        sk_cliente,
        customer_id,
        country,
        ultima_compra,
        dias_recencia,
        frecuencia_pedidos,
        gasto_total,
        NTILE(5) OVER (ORDER BY ultima_compra ASC) AS r_score,
        NTILE(5) OVER (ORDER BY frecuencia_pedidos ASC) AS f_score,
        NTILE(5) OVER (ORDER BY gasto_total ASC) AS m_score
    FROM metricas_cliente
),

-- CTE 3: Segmentación de Negocio mediante reglas combinadas
rfm_segmentado AS (
    SELECT 
        sk_cliente,
        customer_id,
        country,
        ultima_compra,
        dias_recencia,
        frecuencia_pedidos,
        gasto_total,
        r_score,
        f_score,
        m_score,
        CONCAT(r_score, f_score, m_score) AS rfm_score_codigo,
        CASE 
            -- Campeones: Compraron recientemente, compran muy seguido y gastan mucho
            WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Campeones'
            
            -- Clientes Leales: Compran con alta frecuencia y buen gasto, aunque su última compra no sea de ayer
            WHEN f_score >= 4 THEN 'Clientes Leales'
            
            -- Clientes Potenciales / Prometedores: Recientes pero con pocas compras aún
            WHEN r_score >= 4 AND f_score <= 2 THEN 'Prometedores'
            
            -- Clientes que Necesitan Atención: Buen gasto o frecuencia pero no compran hace tiempo
            WHEN r_score = 3 AND f_score >= 3 THEN 'Necesitan Atención'
            
            -- En Riesgo: Solían comprar mucho pero hace mucho que no vuelven
            WHEN r_score <= 2 AND f_score >= 3 THEN 'En Riesgo'
            
            -- Hibernando: Baja recencia, baja frecuencia y bajo ticket
            WHEN r_score = 2 AND f_score <= 2 THEN 'Hibernando'
            
            -- Clientes Perdidos: Los más antiguos e inactivos
            WHEN r_score = 1 AND f_score <= 2 THEN 'Perdidos'
            
            ELSE 'Otros'
        END AS segmento_cliente
    FROM rfm_scores
)
SELECT * FROM rfm_segmentado;
GO

-- =========================================================================
-- CONSULTA DE RESUMEN EJECUTIVO: Distribución de Clientes por Segmento
-- =========================================================================
SELECT 
    segmento_cliente,
    COUNT(*) AS total_clientes,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pct_clientes,
    ROUND(AVG(dias_recencia), 0) AS avg_dias_inactividad,
    ROUND(AVG(frecuencia_pedidos), 1) AS avg_pedidos,
    ROUND(SUM(gasto_total), 2) AS facturacion_total,
    ROUND(SUM(gasto_total) * 100.0 / SUM(SUM(gasto_total)) OVER(), 2) AS pct_facturacion
FROM vw_segmentacion_rfm
GROUP BY segmento_cliente
ORDER BY facturacion_total DESC;
GO
