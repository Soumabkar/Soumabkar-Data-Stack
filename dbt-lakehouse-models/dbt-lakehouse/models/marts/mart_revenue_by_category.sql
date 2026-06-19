-- mart_revenue_by_category : KPI revenu par catégorie de produit
-- Reproduit le calcul PySpark du pipeline (revenu_total, panier_moyen)
WITH orders_completed AS (
    SELECT *
    FROM {{ ref('stg_orders') }}
    WHERE status = 'COMPLETED'
),

joined AS (
    SELECT
        p.category,
        o.order_id,
        o.total_amount
    FROM orders_completed o
    JOIN {{ ref('stg_products') }} p ON o.product_id = p.product_id
)

SELECT
    category,
    COUNT(order_id)                             AS nb_commandes,
    ROUND(SUM(total_amount), 2)                 AS revenu_total,
    ROUND(AVG(total_amount), 2)                 AS panier_moyen
FROM joined
GROUP BY category
ORDER BY revenu_total DESC
