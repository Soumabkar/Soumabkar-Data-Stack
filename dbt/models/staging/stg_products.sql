SELECT
    product_id,
    TRIM(name)                AS product_name,
    TRIM(category)            AS category,
    CAST(price AS DOUBLE)     AS unit_price,
    stock
FROM hive.ecommerce.products
WHERE product_id IS NOT NULL
  AND price > 0