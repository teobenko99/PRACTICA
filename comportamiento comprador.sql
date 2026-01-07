/* ============================================================
   CUSTOMER SHOPPING BEHAVIOR – SQL ANALYSIS
   Author: Teo Benko
   Database: SQL Server
   Table: dbo.customer_behavior_clean

   Description:
   Este script contiene:
   - Validaciones iniciales del dataset
   - Análisis de negocio (Q1 a Q10)
   - Segmentación de clientes
   - Métricas clave
   - Creación de una vista para Power BI
   ============================================================ 
============================================================
   VALIDACIÓN INICIAL DEL DATASET
   ============================================================*/

-- Ver una muestra de los datos
SELECT TOP 10 *
FROM dbo.customer_behavior_clean;

-- Ver cantidad total de registros
SELECT COUNT(*) AS total_filas
FROM dbo.customer_behavior_clean;


/* ============================================================
   Q1) ¿Cuánto revenue generan hombres vs mujeres?
   ============================================================ */

SELECT
    gender,
    ROUND(SUM(CAST(purchase_amount AS decimal(12,2))), 2) AS total_revenue
FROM dbo.customer_behavior_clean
GROUP BY gender;


/* ============================================================
   Q2) Clientes que usaron descuento y gastaron
       más que el promedio general
   ============================================================ */

SELECT
    c.customer_id,
    CAST(c.purchase_amount AS decimal(12,2)) AS purchase_amount,
    a.avg_purchase
FROM dbo.customer_behavior_clean c
CROSS JOIN (
    SELECT AVG(CAST(purchase_amount AS decimal(12,2))) AS avg_purchase
    FROM dbo.customer_behavior_clean
) a
WHERE c.discount_applied = 'Yes'
  AND CAST(c.purchase_amount AS decimal(12,2)) >= a.avg_purchase;


/* ============================================================
   Q3) Top 5 productos con mayor rating promedio
   ============================================================ */

SELECT TOP (5)
    item_purchased,
    ROUND(AVG(TRY_CONVERT(decimal(10,2), review_rating)), 2) AS avg_product_rating
FROM dbo.customer_behavior_clean
GROUP BY item_purchased
ORDER BY AVG(TRY_CONVERT(decimal(10,2), review_rating)) DESC;


/* ============================================================
   Q4) Comparación de ticket promedio por tipo de envío
   ============================================================ */

SELECT
    shipping_type,
    ROUND(AVG(CAST(purchase_amount AS decimal(12,2))), 2) AS avg_purchase_amount
FROM dbo.customer_behavior_clean
WHERE shipping_type IN ('Standard', 'Express')
GROUP BY shipping_type;


/* ============================================================
   Q5) ¿Los clientes suscriptos gastan más?
       Comparación entre suscriptos y no suscriptos
   ============================================================ */

SELECT
    subscription_status,
    COUNT(*) AS total_customers,
    ROUND(AVG(CAST(purchase_amount AS decimal(12,2))), 2) AS avg_spend,
    ROUND(SUM(CAST(purchase_amount AS decimal(12,2))), 2) AS total_revenue
FROM dbo.customer_behavior_clean
GROUP BY subscription_status
ORDER BY total_revenue DESC, avg_spend DESC;


/* ============================================================
   Q6) Top 5 productos con mayor porcentaje de compras
       con descuento aplicado
   ============================================================ */

SELECT TOP (5)
    item_purchased,
    ROUND(
        100.0 * SUM(CASE WHEN discount_applied = 'Yes' THEN 1 ELSE 0 END)
        / COUNT(*),
        2
    ) AS discount_rate_pct
FROM dbo.customer_behavior_clean
GROUP BY item_purchased
ORDER BY discount_rate_pct DESC;


/* ============================================================
   Q7) Segmentación de clientes según compras previas
       - New
       - Returning
       - Loyal
   ============================================================ */

WITH customer_segments AS (
    SELECT
        customer_id,
        previous_purchases,
        CASE
            WHEN ISNULL(previous_purchases, 0) <= 1 THEN 'New'
            WHEN previous_purchases BETWEEN 2 AND 10 THEN 'Returning'
            ELSE 'Loyal'
        END AS customer_segment
    FROM dbo.customer_behavior_clean
)
SELECT
    customer_segment,
    COUNT(*) AS number_of_customers
FROM customer_segments
GROUP BY customer_segment;


/* ============================================================
   Q8) Top 3 productos más comprados dentro de cada categoría
   ============================================================ */

WITH product_rank AS (
    SELECT
        category,
        item_purchased,
        COUNT(*) AS total_orders,
        ROW_NUMBER() OVER (
            PARTITION BY category
            ORDER BY COUNT(*) DESC
        ) AS product_rank
    FROM dbo.customer_behavior_clean
    GROUP BY category, item_purchased
)
SELECT
    category,
    product_rank,
    item_purchased,
    total_orders
FROM product_rank
WHERE product_rank <= 3
ORDER BY category, product_rank;


/* ============================================================
   Q9) ¿Los clientes con más de 5 compras previas
       tienden a suscribirse?
   ============================================================ */

WITH repeat_buyers AS (
    SELECT
        subscription_status,
        COUNT(*) AS repeat_buyers
    FROM dbo.customer_behavior_clean
    WHERE previous_purchases > 5
    GROUP BY subscription_status
),
total_customers AS (
    SELECT
        subscription_status,
        COUNT(*) AS total_customers
    FROM dbo.customer_behavior_clean
    GROUP BY subscription_status
)
SELECT
    t.subscription_status,
    t.total_customers,
    ISNULL(r.repeat_buyers, 0) AS repeat_buyers,
    ROUND(
        100.0 * ISNULL(r.repeat_buyers, 0) / t.total_customers,
        2
    ) AS repeat_buyer_rate_pct
FROM total_customers t
LEFT JOIN repeat_buyers r
    ON t.subscription_status = r.subscription_status;


/* ============================================================
   Q10) ¿Qué grupo etario aporta más revenue?
   ============================================================ */

SELECT
    age_group,
    ROUND(SUM(CAST(purchase_amount AS decimal(12,2))), 2) AS total_revenue
FROM dbo.customer_behavior_clean
GROUP BY age_group
ORDER BY total_revenue DESC;


/* ============================================================
   VISTA PARA POWER BI / DASHBOARDS
   ============================================================ */
   GO
CREATE VIEW dbo.v_kpi_by_segment AS
SELECT
    subscription_status,
    gender,
    age_group,
    COUNT(*) AS total_purchases,
    SUM(CAST(purchase_amount AS decimal(12,2))) AS total_revenue,
    AVG(CAST(purchase_amount AS decimal(12,2))) AS avg_ticket
FROM dbo.customer_behavior_clean
GROUP BY subscription_status, gender, age_group;


/* ============================================================
   CHECK FINAL DE TIPOS DE DATOS (DEBUG)
   ============================================================ */

SELECT TOP 5
    purchase_amount,
    SQL_VARIANT_PROPERTY(purchase_amount, 'BaseType') AS data_type
FROM dbo.customer_behavior_clean;