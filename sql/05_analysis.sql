USE WAREHOUSE olist_wh;
USE SCHEMA olist.analytics;

WITH monthly AS (
  SELECT DATE_TRUNC('month', date_key) AS month,
         COUNT(*)                      AS orders,
         SUM(items_value)              AS revenue
  FROM fact_orders
  WHERE order_status NOT IN ('canceled', 'unavailable')
    AND date_key BETWEEN '2017-01-01' AND '2018-08-31'
  GROUP BY 1
)
SELECT
  month,
  orders,
  ROUND(revenue, 2)                                         AS revenue,
  ROUND(revenue / orders, 2)                                AS avg_order_value,
  ROUND(100 * (revenue - LAG(revenue) OVER (ORDER BY month))
            / LAG(revenue) OVER (ORDER BY month), 1)        AS mom_growth_pct,
  ROUND(SUM(revenue) OVER (PARTITION BY YEAR(month) ORDER BY month), 2) AS ytd_revenue
FROM monthly
ORDER BY month;

SELECT
  p.category,
  ROUND(SUM(f.price), 2)                                   AS revenue,
  COUNT(DISTINCT f.order_id)                               AS orders,
  ROUND(100 * RATIO_TO_REPORT(SUM(f.price)) OVER (), 2)    AS pct_of_total_revenue
FROM fact_order_items f
JOIN dim_product p ON f.product_key = p.product_key
WHERE f.order_status NOT IN ('canceled', 'unavailable')
GROUP BY p.category
ORDER BY revenue DESC
LIMIT 10;

SELECT
  c.state,
  p.category,
  ROUND(SUM(f.price), 2) AS revenue,
  RANK() OVER (PARTITION BY c.state ORDER BY SUM(f.price) DESC) AS rnk
FROM fact_order_items f
JOIN dim_customer c ON f.customer_key = c.customer_key
JOIN dim_product p  ON f.product_key = p.product_key
WHERE f.order_status NOT IN ('canceled', 'unavailable')
GROUP BY c.state, p.category
QUALIFY rnk <= 3
ORDER BY c.state, rnk;

WITH cust AS (
  SELECT customer_key, COUNT(*) AS orders
  FROM fact_orders
  WHERE order_status NOT IN ('canceled', 'unavailable')
  GROUP BY customer_key
)
SELECT
  COUNT(*)                                           AS customers,
  COUNT_IF(orders > 1)                               AS repeat_customers,
  ROUND(100 * COUNT_IF(orders > 1) / COUNT(*), 2)    AS repeat_rate_pct
FROM cust;

WITH orders AS (
  SELECT customer_key, DATE_TRUNC('month', date_key) AS order_month
  FROM fact_orders
  WHERE order_status NOT IN ('canceled', 'unavailable')
),
first_order AS (
  SELECT customer_key, MIN(order_month) AS cohort_month
  FROM orders
  GROUP BY customer_key
),
activity AS (
  SELECT
    f.cohort_month,
    DATEDIFF(month, f.cohort_month, o.order_month) AS month_number,
    COUNT(DISTINCT o.customer_key)                 AS active_customers
  FROM orders o
  JOIN first_order f ON o.customer_key = f.customer_key
  GROUP BY 1, 2
),
cohort_size AS (
  SELECT cohort_month, active_customers AS cohort_size
  FROM activity
  WHERE month_number = 0
)
SELECT
  a.cohort_month,
  s.cohort_size,
  a.month_number,
  a.active_customers,
  ROUND(100 * a.active_customers / s.cohort_size, 2) AS retention_pct
FROM activity a
JOIN cohort_size s ON a.cohort_month = s.cohort_month
WHERE a.cohort_month BETWEEN '2017-01-01' AND '2018-08-01'
ORDER BY a.cohort_month, a.month_number;

WITH max_date AS (
  SELECT MAX(date_key) AS last_date FROM fact_orders
),
base AS (
  SELECT
    o.customer_key,
    DATEDIFF(day, MAX(o.date_key), MAX(m.last_date)) AS recency_days,
    COUNT(*)                                         AS frequency,
    SUM(o.payment_total)                             AS monetary
  FROM fact_orders o
  CROSS JOIN max_date m
  WHERE o.order_status NOT IN ('canceled', 'unavailable')
  GROUP BY o.customer_key
),
scored AS (
  SELECT *,
    NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,   -- 5 = most recent
    NTILE(5) OVER (ORDER BY monetary)          AS m_score    -- 5 = highest spend
  FROM base
)
SELECT
  CASE
    WHEN r_score >= 4 AND m_score >= 4 THEN '1. Champions'
    WHEN r_score >= 4                  THEN '2. Recent, lower spend'
    WHEN r_score <= 2 AND m_score >= 4 THEN '4. At-risk high value'
    WHEN r_score <= 2                  THEN '5. Lost / low value'
    ELSE                                    '3. Middle'
  END                         AS segment,
  COUNT(*)                    AS customers,
  ROUND(AVG(monetary), 2)     AS avg_spend,
  ROUND(AVG(recency_days))    AS avg_days_since_order
FROM scored
GROUP BY 1
ORDER BY 1;

SELECT
  c.state,
  COUNT(*)                                     AS delivered_orders,
  ROUND(AVG(o.delivery_days), 1)               AS avg_delivery_days,
  ROUND(100 * AVG(IFF(o.is_late, 1, 0)), 1)    AS pct_late
FROM fact_orders o
JOIN dim_customer c ON o.customer_key = c.customer_key
WHERE o.is_completed_delivery
GROUP BY c.state
HAVING COUNT(*) >= 100
ORDER BY avg_delivery_days DESC;

SELECT
  CASE
    WHEN days_late <= -7 THEN '1. 7+ days early'
    WHEN days_late <= 0  THEN '2. On time'
    WHEN days_late <= 7  THEN '3. 1-7 days late'
    ELSE                      '4. 7+ days late'
  END                                                 AS delivery_bucket,
  COUNT(*)                                            AS orders,
  ROUND(AVG(review_score), 2)                         AS avg_review,
  ROUND(100 * AVG(IFF(review_score <= 2, 1, 0)), 1)   AS pct_bad_reviews
FROM fact_orders
WHERE is_completed_delivery
  AND review_score IS NOT NULL
GROUP BY 1
ORDER BY 1;

WITH seller_rev AS (
  SELECT seller_key, SUM(price) AS revenue
  FROM fact_order_items
  WHERE order_status NOT IN ('canceled', 'unavailable')
  GROUP BY seller_key
),
ranked AS (
  SELECT
    seller_key,
    revenue,
    SUM(revenue) OVER (ORDER BY revenue DESC ROWS UNBOUNDED PRECEDING)
      / SUM(revenue) OVER ()                       AS cumulative_share
  FROM seller_rev
)
SELECT
  COUNT(*)                                                  AS total_sellers,
  COUNT_IF(cumulative_share <= 0.80)                        AS sellers_making_80pct,
  ROUND(100 * COUNT_IF(cumulative_share <= 0.80) / COUNT(*), 1) AS pct_of_sellers
FROM ranked;

SELECT
  main_payment_type,
  COUNT(*)                                          AS orders,
  ROUND(100 * RATIO_TO_REPORT(COUNT(*)) OVER (), 1) AS pct_of_orders,
  ROUND(AVG(payment_total), 2)                      AS avg_order_value,
  ROUND(AVG(installments), 1)                       AS avg_installments
FROM fact_orders
WHERE order_status NOT IN ('canceled', 'unavailable')
  AND main_payment_type IS NOT NULL
GROUP BY main_payment_type
ORDER BY orders DESC;

SELECT
  d.day_name,
  HOUR(o.order_purchase_timestamp) AS hour_of_day,
  COUNT(*)                         AS orders
FROM fact_orders o
JOIN dim_date d ON o.date_key = d.date_key
WHERE o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY 1, 2
ORDER BY orders DESC
LIMIT 20;

SELECT
  c.state,
  ROUND(AVG(f.freight_value), 2)                     AS avg_freight,
  ROUND(100 * SUM(f.freight_value) / SUM(f.price), 1) AS freight_pct_of_price
FROM fact_order_items f
JOIN dim_customer c ON f.customer_key = c.customer_key
WHERE f.order_status NOT IN ('canceled', 'unavailable')
GROUP BY c.state
ORDER BY freight_pct_of_price DESC;
