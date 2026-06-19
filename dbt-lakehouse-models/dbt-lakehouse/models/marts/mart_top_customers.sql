-- mart_top_customers : clients les plus dépensiers (commandes complétées)
WITH completed AS (
    SELECT *
    FROM {{ ref('stg_orders') }}
    WHERE status = 'COMPLETED'
)

SELECT
    c.customer_id,
    c.full_name                             AS client,
    c.country,
    COUNT(o.order_id)                       AS nb_commandes,
    ROUND(SUM(o.total_amount), 2)           AS depenses_totales,
    ROUND(AVG(o.total_amount), 2)           AS panier_moyen
FROM completed o
JOIN {{ ref('stg_customers') }} c ON o.customer_id = c.customer_id
GROUP BY c.customer_id, c.full_name, c.country
ORDER BY depenses_totales DESC
