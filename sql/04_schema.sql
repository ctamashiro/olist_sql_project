-- 04_schema.sql: build star schema (dimensions + facts) from staging
USE WAREHOUSE olist_wh;
USE DATABASE olist;


CREATE OR REPLACE TABLE analytics.dim_customer AS
WITH customer_orders AS (
  SELECT c.customer_unique_id, c.zip_prefix, c.city, c.state,
         o.order_purchase_timestamp
  FROM staging.customers c
  JOIN staging.orders o ON c.customer_id = o.customer_id
)
SELECT
  co.customer_unique_id                                        AS customer_key,
  MAX_BY(co.zip_prefix, co.order_purchase_timestamp)           AS zip_prefix,
  MAX_BY(co.city, co.order_purchase_timestamp)                 AS city,
  MAX_BY(co.state, co.order_purchase_timestamp)                AS state,
  MIN(co.order_purchase_timestamp)::DATE                       AS first_order_date,
  MAX(co.order_purchase_timestamp)::DATE                       AS last_order_date,
  COUNT(*)                                                     AS lifetime_orders
FROM customer_orders co
GROUP BY co.customer_unique_id;

CREATE OR REPLACE TABLE analytics.dim_customer AS
SELECT d.*, g.lat, g.lng
FROM analytics.dim_customer d
LEFT JOIN staging.geolocation g ON d.zip_prefix = g.zip_prefix;

CREATE OR REPLACE TABLE analytics.dim_product AS
SELECT
  product_id AS product_key,
  category,
  photos_qty,
  weight_g,
  length_cm * height_cm * width_cm AS volume_cm3
FROM staging.products;

CREATE OR REPLACE TABLE analytics.dim_seller AS
SELECT
  s.seller_id AS seller_key,
  s.zip_prefix,
  s.city,
  s.state,
  g.lat,
  g.lng
FROM staging.sellers s
LEFT JOIN staging.geolocation g ON s.zip_prefix = g.zip_prefix;

CREATE OR REPLACE TABLE analytics.dim_date AS
WITH days AS (
  SELECT DATEADD(day, ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1, '2016-01-01'::DATE) AS date_day
  FROM TABLE(GENERATOR(ROWCOUNT => 1096))
)
SELECT
  date_day                        AS date_key,
  YEAR(date_day)                  AS year,
  QUARTER(date_day)               AS quarter,
  MONTH(date_day)                 AS month,
  MONTHNAME(date_day)             AS month_name,
  DATE_TRUNC('month', date_day)   AS month_start,
  WEEKOFYEAR(date_day)            AS week_of_year,
  DAYNAME(date_day)               AS day_name,
  DAYNAME(date_day) IN ('Sat', 'Sun') AS is_weekend
FROM days;


CREATE OR REPLACE TABLE analytics.fact_order_items AS
SELECT
  i.order_id,
  i.order_item_id,
  c.customer_unique_id                    AS customer_key,
  i.product_id                            AS product_key,
  i.seller_id                             AS seller_key,
  o.order_purchase_timestamp::DATE        AS date_key,
  o.order_status,
  i.price,
  i.freight_value,
  i.total_item_value
FROM staging.order_items i
JOIN staging.orders o    ON i.order_id = o.order_id
JOIN staging.customers c ON o.customer_id = c.customer_id;


CREATE OR REPLACE TABLE analytics.fact_orders AS
WITH items AS (
  SELECT order_id,
         COUNT(*)            AS item_count,
         SUM(price)          AS items_value,
         SUM(freight_value)  AS freight_value
  FROM staging.order_items
  GROUP BY order_id
),
payments AS (
  SELECT order_id,
         SUM(payment_value)                    AS payment_total,
         MAX_BY(payment_type, payment_value)   AS main_payment_type,
         MAX(payment_installments)             AS installments
  FROM staging.order_payments
  GROUP BY order_id
)
SELECT
  o.order_id,
  c.customer_unique_id                   AS customer_key,
  o.order_purchase_timestamp::DATE       AS date_key,
  o.order_purchase_timestamp,
  o.order_status,
  i.item_count,
  i.items_value,
  i.freight_value,
  p.payment_total,
  p.main_payment_type,
  p.installments,
  o.delivery_days,
  o.days_late,
  o.is_late,
  o.is_completed_delivery,
  r.review_score
FROM staging.orders o
JOIN staging.customers c        ON o.customer_id = c.customer_id
LEFT JOIN items i               ON o.order_id = i.order_id
LEFT JOIN payments p            ON o.order_id = p.order_id
LEFT JOIN staging.order_reviews r ON o.order_id = r.order_id;

SELECT 'fact_order_items' AS tbl, COUNT(*) AS n FROM analytics.fact_order_items
UNION ALL SELECT 'fact_orders', COUNT(*) FROM analytics.fact_orders
UNION ALL SELECT 'dim_customer', COUNT(*) FROM analytics.dim_customer
UNION ALL SELECT 'dim_product', COUNT(*) FROM analytics.dim_product
UNION ALL SELECT 'dim_seller', COUNT(*) FROM analytics.dim_seller
UNION ALL SELECT 'dim_date', COUNT(*) FROM analytics.dim_date;


SELECT
  (SELECT SUM(price) FROM staging.order_items)       AS staging_revenue,
  (SELECT SUM(price) FROM analytics.fact_order_items) AS fact_revenue;


SELECT
  COUNT_IF(c.customer_key IS NULL) AS missing_customers,
  COUNT_IF(p.product_key IS NULL)  AS missing_products,
  COUNT_IF(s.seller_key IS NULL)   AS missing_sellers,
  COUNT_IF(d.date_key IS NULL)     AS missing_dates
FROM analytics.fact_order_items f
LEFT JOIN analytics.dim_customer c ON f.customer_key = c.customer_key
LEFT JOIN analytics.dim_product p  ON f.product_key = p.product_key
LEFT JOIN analytics.dim_seller s   ON f.seller_key = s.seller_key
LEFT JOIN analytics.dim_date d     ON f.date_key = d.date_key;