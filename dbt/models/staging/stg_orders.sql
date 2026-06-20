SELECT
    order_id,
    customer_id,
    product_id,
    CAST(quantity     AS INTEGER) AS quantity,
    CAST(unit_price   AS DOUBLE)  AS unit_price,
    CAST(total_amount AS DOUBLE)  AS total_amount,
    UPPER(TRIM(status))           AS status,
    CAST(order_date   AS TIMESTAMP) AS order_date,
    CAST(year  AS INTEGER)        AS year,
    CAST(month AS INTEGER)        AS month
FROM hive.ecommerce.orders
WHERE order_id IS NOT NULL
  AND status IN ('COMPLETED', 'PENDING', 'CANCELLED', 'SHIPPED')
  AND total_amount > 0
