-- mart_monthly_sales : CA mensuel + CA cumulé (window function)
-- Reproduit le calcul PySpark WindowSpec du pipeline
WITH monthly AS (
    SELECT
        year,
        month,
        COUNT(order_id)             AS nb_commandes,
        ROUND(SUM(total_amount), 2) AS ca_mensuel
    FROM {{ ref('stg_orders') }}
    WHERE status = 'COMPLETED'
    GROUP BY year, month
)

SELECT
    year,
    month,
    nb_commandes,
    ca_mensuel,
    ROUND(
        SUM(ca_mensuel) OVER (
            ORDER BY year, month
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ), 2
    ) AS ca_cumule
FROM monthly
ORDER BY year, month
