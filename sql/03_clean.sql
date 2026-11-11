-- 03_clean.sql: profile raw data, then build cleaned staging tables
USE WAREHOUSE olist_wh;
USE DATABASE olist;
CREATE SCHEMA IF NOT EXISTS olist.staging;

/* ============================================================
   PART A: PROFILING (run each query on its own and note findings)
   ============================================================ */

-- A1. Primary key checks: total rows vs distinct keys (should match)
SELECT 'orders' AS tbl, COUNT(*) AS total, COUNT(DISTINCT order_id) AS distinct_keys FROM raw.orders
UNION ALL SELECT 'customers', COUNT(*), COUNT(DISTINCT customer_id) FROM raw.customers
UNION ALL SELECT 'products', COUNT(*), COUNT(DISTINCT product_id) FROM raw.products
UNION ALL SELECT 'sellers', COUNT(*), COUNT(DISTINCT seller_id) FROM raw.sellers
UNION ALL SELECT 'order_reviews', COUNT(*), COUNT(DISTINCT review_id) FROM raw.order_reviews;

-- A2. The customer_id trap: customer_id is per ORDER, customer_unique_id is the real person
SELECT COUNT(DISTINCT customer_id)        AS customer_ids,
       COUNT(DISTINCT customer_unique_id) AS real_customers
FROM raw.customers;

-- A3. Orders by status, and how many are missing a delivery date
SELECT order_status,
       COUNT(*) AS orders,
       COUNT_IF(order_delivered_customer_date IS NULL) AS missing_delivery_date
FROM raw.orders
GROUP BY order_status
ORDER BY orders DESC;

-- A4. Date range of the data
SELECT MIN(order_purchase_timestamp) AS first_order,
       MAX(order_purchase_timestamp) AS last_order
FROM raw.orders;

-- A5. Orphans: order items whose order doesn't exist, orders whose customer doesn't exist
SELECT 'items without order' AS check_name, COUNT(*) AS n
FROM raw.order_items i LEFT JOIN raw.orders o ON i.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'orders without customer', COUNT(*)
FROM raw.orders o LEFT JOIN raw.customers c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

-- A6. Products missing a category, and categories missing an English translation
SELECT COUNT_IF(product_category_name IS NULL) AS products_no_category
FROM raw.products;

SELECT DISTINCT p.product_category_name
FROM raw.products p
LEFT JOIN raw.category_translation t ON p.product_category_name = t.product_category_name
WHERE p.product_category_name IS NOT NULL
  AND t.product_category_name IS NULL;

-- A7. Orders with more than one review
SELECT COUNT(*) AS orders_with_multiple_reviews
FROM (SELECT order_id FROM raw.order_reviews GROUP BY order_id HAVING COUNT(*) > 1);

-- A8. Geolocation duplicates: rows per zip prefix
SELECT COUNT(*) AS total_rows,
       COUNT(DISTINCT geolocation_zip_code_prefix) AS distinct_zips
FROM raw.geolocation;

-- A9. Weird payments
SELECT payment_type, COUNT(*) AS n, SUM(payment_value) AS total_value
FROM raw.order_payments
GROUP BY payment_type
ORDER BY n DESC;

/* ============================================================
   PART B: CLEANED STAGING TABLES
   ============================================================ */

-- Orders: add delivery metrics + flags
CREATE OR REPLACE TABLE staging.orders AS
SELECT
  order_id,
  customer_id,
  order_status,
  order_purchase_timestamp,
  order_approved_at,
  order_delivered_carrier_date,
  order_delivered_customer_date,
  order_estimated_delivery_date,
  DATEDIFF(day, order_purchase_timestamp, order_delivered_customer_date)      AS delivery_days,
  DATEDIFF(day, order_estimated_delivery_date, order_delivered_customer_date) AS days_late,
  (order_delivered_customer_date > order_estimated_delivery_date)             AS is_late,
  (order_status = 'delivered' AND order_delivered_customer_date IS NOT NULL)  AS is_completed_delivery
FROM raw.orders;

-- Customers: standardize zip + city formatting
CREATE OR REPLACE TABLE staging.customers AS
SELECT
  customer_id,
  customer_unique_id,
  LPAD(customer_zip_code_prefix, 5, '0') AS zip_prefix,
  INITCAP(TRIM(customer_city))           AS city,
  UPPER(customer_state)                  AS state
FROM raw.customers;

-- Sellers: same treatment
CREATE OR REPLACE TABLE staging.sellers AS
SELECT
  seller_id,
  LPAD(seller_zip_code_prefix, 5, '0') AS zip_prefix,
  INITCAP(TRIM(seller_city))           AS city,
  UPPER(seller_state)                  AS state
FROM raw.sellers;

-- Products: English category names, fix the source typos
CREATE OR REPLACE TABLE staging.products AS
SELECT
  p.product_id,
  COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category,
  p.product_name_lenght        AS name_length,
  p.product_description_lenght AS description_length,
  p.product_photos_qty         AS photos_qty,
  p.product_weight_g           AS weight_g,
  p.product_length_cm          AS length_cm,
  p.product_height_cm          AS height_cm,
  p.product_width_cm           AS width_cm
FROM raw.products p
LEFT JOIN raw.category_translation t
  ON p.product_category_name = t.product_category_name;

-- Order items: add total line value
CREATE OR REPLACE TABLE staging.order_items AS
SELECT
  order_id,
  order_item_id,
  product_id,
  seller_id,
  shipping_limit_date,
  price,
  freight_value,
  price + freight_value AS total_item_value
FROM raw.order_items;

-- Payments: drop the junk 'not_defined' rows
CREATE OR REPLACE TABLE staging.order_payments AS
SELECT *
FROM raw.order_payments
WHERE payment_type <> 'not_defined';

-- Reviews: keep only the most recent review per order
CREATE OR REPLACE TABLE staging.order_reviews AS
SELECT *
FROM raw.order_reviews
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY order_id
  ORDER BY review_answer_timestamp DESC
) = 1;

-- Geolocation: collapse to one row per zip, drop coordinates outside Brazil
CREATE OR REPLACE TABLE staging.geolocation AS
SELECT
  LPAD(geolocation_zip_code_prefix, 5, '0') AS zip_prefix,
  AVG(geolocation_lat)                      AS lat,
  AVG(geolocation_lng)                      AS lng,
  INITCAP(MODE(geolocation_city))           AS city,
  MODE(UPPER(geolocation_state))            AS state
FROM raw.geolocation
WHERE geolocation_lat BETWEEN -35 AND 5.5
  AND geolocation_lng BETWEEN -75 AND -33
GROUP BY 1;

-- Final check: row counts of cleaned tables
SELECT 'orders' AS tbl, COUNT(*) AS n FROM staging.orders
UNION ALL SELECT 'customers', COUNT(*) FROM staging.customers
UNION ALL SELECT 'sellers', COUNT(*) FROM staging.sellers
UNION ALL SELECT 'products', COUNT(*) FROM staging.products
UNION ALL SELECT 'order_items', COUNT(*) FROM staging.order_items
UNION ALL SELECT 'order_payments', COUNT(*) FROM staging.order_payments
UNION ALL SELECT 'order_reviews', COUNT(*) FROM staging.order_reviews
UNION ALL SELECT 'geolocation', COUNT(*) FROM staging.geolocation;