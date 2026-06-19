-- mart_cancellation_rate : taux d'annulation par pays (pays avec >10 commandes)
WITH by_country AS (
    SELECT
        c.country,
        COUNT(o.order_id)                                           AS total_commandes,
        COUNT(CASE WHEN o.status = 'CANCELLED' THEN 1 END)         AS annulations
    FROM {{ ref('stg_orders') }} o
    JOIN {{ ref('stg_customers') }} c ON o.customer_id = c.customer_id
    GROUP BY c.country
)

SELECT
    country,
    total_commandes,
    annulations,
    ROUND(CAST(annulations AS DOUBLE) / total_commandes * 100, 1)  AS taux_annulation_pct
FROM by_country
WHERE total_commandes > 10
ORDER BY taux_annulation_pct DESC
