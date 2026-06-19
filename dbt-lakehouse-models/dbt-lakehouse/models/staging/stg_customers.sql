SELECT
    customer_id,
    TRIM(first_name)                            AS first_name,
    TRIM(last_name)                             AS last_name,
    TRIM(first_name) || ' ' || TRIM(last_name)  AS full_name,
    LOWER(TRIM(email))                          AS email,
    TRIM(country)                               AS country,
    city,
    created_at
FROM hive.ecommerce.customers
WHERE customer_id IS NOT NULL
