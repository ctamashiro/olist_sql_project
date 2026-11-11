-- 02_load.sql: create raw tables and load from stage
USE WAREHOUSE olist_wh;
USE SCHEMA olist.raw;

CREATE OR REPLACE TABLE customers (
  customer_id STRING, customer_unique_id STRING,
  customer_zip_code_prefix STRING, customer_city STRING, customer_state STRING);

CREATE OR REPLACE TABLE geolocation (
  geolocation_zip_code_prefix STRING, geolocation_lat FLOAT, geolocation_lng FLOAT,
  geolocation_city STRING, geolocation_state STRING);

CREATE OR REPLACE TABLE orders (
  order_id STRING, customer_id STRING, order_status STRING,
  order_purchase_timestamp TIMESTAMP, order_approved_at TIMESTAMP,
  order_delivered_carrier_date TIMESTAMP, order_delivered_customer_date TIMESTAMP,
  order_estimated_delivery_date TIMESTAMP);

CREATE OR REPLACE TABLE order_items (
  order_id STRING, order_item_id INT, product_id STRING, seller_id STRING,
  shipping_limit_date TIMESTAMP, price NUMBER(10,2), freight_value NUMBER(10,2));

CREATE OR REPLACE TABLE order_payments (
  order_id STRING, payment_sequential INT, payment_type STRING,
  payment_installments INT, payment_value NUMBER(10,2));

CREATE OR REPLACE TABLE order_reviews (
  review_id STRING, order_id STRING, review_score INT,
  review_comment_title STRING, review_comment_message STRING,
  review_creation_date TIMESTAMP, review_answer_timestamp TIMESTAMP);

CREATE OR REPLACE TABLE products (
  product_id STRING, product_category_name STRING,
  product_name_lenght INT, product_description_lenght INT,   -- typo is in the source data
  product_photos_qty INT, product_weight_g INT,
  product_length_cm INT, product_height_cm INT, product_width_cm INT);

CREATE OR REPLACE TABLE sellers (
  seller_id STRING, seller_zip_code_prefix STRING, seller_city STRING, seller_state STRING);

CREATE OR REPLACE TABLE category_translation (
  product_category_name STRING, product_category_name_english STRING);

COPY INTO customers      FROM @olist_stage/olist_customers_dataset.csv;
COPY INTO geolocation    FROM @olist_stage/olist_geolocation_dataset.csv;
COPY INTO orders         FROM @olist_stage/olist_orders_dataset.csv;
COPY INTO order_items    FROM @olist_stage/olist_order_items_dataset.csv;
COPY INTO order_payments FROM @olist_stage/olist_order_payments_dataset.csv;
COPY INTO order_reviews  FROM @olist_stage/olist_order_reviews_dataset.csv;
COPY INTO products       FROM @olist_stage/olist_products_dataset.csv;
COPY INTO sellers        FROM @olist_stage/olist_sellers_dataset.csv;
COPY INTO category_translation FROM @olist_stage/product_category_name_translation.csv;

-- Sanity check: row counts
SELECT 'customers' AS tbl, COUNT(*) AS n FROM customers
UNION ALL SELECT 'geolocation', COUNT(*) FROM geolocation
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL SELECT 'order_payments', COUNT(*) FROM order_payments
UNION ALL SELECT 'order_reviews', COUNT(*) FROM order_reviews
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'sellers', COUNT(*) FROM sellers
UNION ALL SELECT 'category_translation', COUNT(*) FROM category_translation;