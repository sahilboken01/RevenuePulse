-- Power BI semantic-layer views built only from the cleaned Stage 2 tables and
-- existing Stage 4 RFM/cohort views. Run Stage 4 files 08 and 09 first.
CREATE SCHEMA IF NOT EXISTS analytics;

CREATE OR REPLACE VIEW analytics.pbi_dim_date AS
WITH bounds AS (
    SELECT date_trunc('month', MIN(order_purchase_timestamp))::date AS first_date,
           (date_trunc('month', MAX(order_purchase_timestamp)) + interval '1 month' - interval '1 day')::date AS last_date
    FROM olist.orders
    WHERE order_status = 'delivered'
)
SELECT d::date AS date,
       EXTRACT(YEAR FROM d)::integer AS year,
       'Q' || EXTRACT(QUARTER FROM d)::integer::text AS quarter,
       EXTRACT(MONTH FROM d)::integer AS month_number,
       to_char(d, 'FMMonth') AS month_name,
       date_trunc('month', d)::date AS month_start,
       to_char(d, 'YYYY-MM') AS year_month,
       date_trunc('week', d)::date AS week_start
FROM bounds
CROSS JOIN LATERAL generate_series(first_date, last_date, interval '1 day') AS dates(d);

CREATE OR REPLACE VIEW analytics.pbi_dim_customer AS
WITH cohort AS (
    SELECT c.customer_unique_id,
           MIN(date_trunc('month', o.order_purchase_timestamp)::date) AS cohort_month
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT r.customer_unique_id, r.snapshot_date, r.recency_days, r.frequency_orders,
       r.monetary_gmv, r.recency_score, r.frequency_score, r.monetary_score,
       r.customer_segment,
       CASE WHEN r.frequency_orders = 1 THEN 'one-time' ELSE 'repeat' END AS purchase_type,
       c.cohort_month
FROM analytics.rfm_customer_segments AS r
JOIN cohort AS c USING (customer_unique_id);

CREATE OR REPLACE VIEW analytics.pbi_dim_category AS
SELECT DISTINCT COALESCE(ct.product_category_name_english, p.product_category_name, 'unknown') AS category_key
FROM olist.products AS p
LEFT JOIN olist.category_translation AS ct
  ON ct.product_category_name = p.product_category_name;

CREATE OR REPLACE VIEW analytics.pbi_dim_product AS
SELECT p.product_id,
       COALESCE(ct.product_category_name_english, p.product_category_name, 'unknown') AS category_key
FROM olist.products AS p
LEFT JOIN olist.category_translation AS ct
  ON ct.product_category_name = p.product_category_name;

CREATE OR REPLACE VIEW analytics.pbi_dim_seller AS
SELECT DISTINCT s.seller_id, s.seller_state AS seller_state_code, s.seller_city
FROM olist.sellers AS s
JOIN olist.order_items AS oi ON oi.seller_id = s.seller_id
JOIN olist.orders AS o ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered';

CREATE OR REPLACE VIEW analytics.pbi_dim_geography AS
SELECT DISTINCT c.customer_state AS state_code
FROM olist.orders AS o
JOIN olist.customers AS c ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered';

CREATE OR REPLACE VIEW analytics.pbi_fact_order AS
WITH order_gmv AS (
    SELECT o.order_id, o.customer_id, o.order_purchase_timestamp,
           o.order_delivered_customer_date, o.order_estimated_delivery_date,
           SUM(oi.price) AS order_gmv
    FROM olist.orders AS o
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY o.order_id, o.customer_id, o.order_purchase_timestamp,
             o.order_delivered_customer_date, o.order_estimated_delivery_date
), customer_order_type AS (
    SELECT g.*, c.customer_unique_id, c.customer_state AS state_code,
           ROW_NUMBER() OVER (
               PARTITION BY c.customer_unique_id
               ORDER BY g.order_purchase_timestamp, g.order_id
           ) AS customer_order_number
    FROM order_gmv AS g
    JOIN olist.customers AS c ON c.customer_id = g.customer_id
), review_by_order AS (
    SELECT order_id, AVG(review_score::numeric) AS order_average_review_score,
           COUNT(*) AS review_order_records
    FROM olist.order_reviews
    GROUP BY order_id
)
SELECT g.order_id, g.order_purchase_timestamp::date AS purchase_date,
       g.customer_unique_id, g.state_code, g.order_gmv,
       g.customer_order_number,
       CASE WHEN g.customer_order_number = 1 THEN 'new customer order'
            ELSE 'returning customer order' END AS customer_order_type,
       EXTRACT(EPOCH FROM (g.order_delivered_customer_date - g.order_purchase_timestamp)) / 86400.0 AS delivery_days,
       CASE WHEN g.order_delivered_customer_date IS NULL OR g.order_estimated_delivery_date IS NULL THEN NULL
            WHEN g.order_delivered_customer_date > g.order_estimated_delivery_date THEN 1 ELSE 0 END AS late_flag,
       CASE WHEN g.order_delivered_customer_date IS NULL THEN 'missing delivery date'
            WHEN g.order_estimated_delivery_date IS NULL THEN 'missing estimate'
            WHEN g.order_delivered_customer_date > g.order_estimated_delivery_date THEN 'late'
            ELSE 'on time' END AS delivery_status,
       CASE WHEN g.order_delivered_customer_date IS NULL THEN NULL
            WHEN EXTRACT(EPOCH FROM (g.order_delivered_customer_date - g.order_purchase_timestamp)) / 86400.0 < 3 THEN 'under_3_days'
            WHEN EXTRACT(EPOCH FROM (g.order_delivered_customer_date - g.order_purchase_timestamp)) / 86400.0 < 7 THEN '3_to_6_days'
            WHEN EXTRACT(EPOCH FROM (g.order_delivered_customer_date - g.order_purchase_timestamp)) / 86400.0 < 14 THEN '7_to_13_days'
            ELSE '14_days_or_more' END AS delivery_time_bucket,
       CASE WHEN g.order_delivered_customer_date IS NULL THEN NULL
            WHEN EXTRACT(EPOCH FROM (g.order_delivered_customer_date - g.order_purchase_timestamp)) / 86400.0 < 3 THEN 1
            WHEN EXTRACT(EPOCH FROM (g.order_delivered_customer_date - g.order_purchase_timestamp)) / 86400.0 < 7 THEN 2
            WHEN EXTRACT(EPOCH FROM (g.order_delivered_customer_date - g.order_purchase_timestamp)) / 86400.0 < 14 THEN 3
            ELSE 4 END AS delivery_bucket_order,
       r.order_average_review_score, r.review_order_records
FROM customer_order_type AS g
LEFT JOIN review_by_order AS r USING (order_id);

CREATE OR REPLACE VIEW analytics.pbi_fact_sales_item AS
WITH customer_order_type AS (
    SELECT o.order_id, o.order_purchase_timestamp, c.customer_unique_id,
           c.customer_state AS state_code,
           ROW_NUMBER() OVER (
               PARTITION BY c.customer_unique_id
               ORDER BY o.order_purchase_timestamp, o.order_id
           ) AS customer_order_number
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
)
SELECT oi.order_id, oi.order_item_id,
       cot.order_purchase_timestamp::date AS purchase_date,
       cot.customer_unique_id, cot.state_code,
       oi.product_id,
       COALESCE(ct.product_category_name_english, p.product_category_name, 'unknown') AS category_key,
       oi.seller_id,
       CASE WHEN cot.customer_order_number = 1 THEN 'new customer order'
            ELSE 'returning customer order' END AS customer_order_type,
       oi.price AS item_price
FROM customer_order_type AS cot
JOIN olist.order_items AS oi ON oi.order_id = cot.order_id
JOIN olist.products AS p ON p.product_id = oi.product_id
LEFT JOIN olist.category_translation AS ct
  ON ct.product_category_name = p.product_category_name;

CREATE OR REPLACE VIEW analytics.pbi_fact_category_economics AS
WITH full_period_metrics AS (
    SELECT category_key,
           SUM(item_price) AS category_gmv,
           COUNT(DISTINCT order_id) AS category_orders,
           COUNT(*) AS item_count
    FROM analytics.pbi_fact_sales_item
    GROUP BY category_key
), benchmarks AS (
    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY category_orders) AS median_category_orders,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY category_gmv / NULLIF(category_orders, 0)) AS median_category_order_value
    FROM full_period_metrics
), category_classification AS (
    SELECT f.category_key,
           CASE WHEN f.category_orders >= b.median_category_orders
                  AND f.category_gmv / NULLIF(f.category_orders, 0) >= b.median_category_order_value THEN 'high-volume / high-value'
                WHEN f.category_orders >= b.median_category_orders THEN 'high-volume / lower-value'
                WHEN f.category_gmv / NULLIF(f.category_orders, 0) >= b.median_category_order_value THEN 'lower-volume / high-value'
                ELSE 'lower-volume / lower-value' END AS category_quadrant
    FROM full_period_metrics AS f CROSS JOIN benchmarks AS b
), monthly_metrics AS (
    SELECT date_trunc('month', purchase_date)::date AS purchase_month,
           category_key,
           SUM(item_price) AS category_gmv,
           COUNT(DISTINCT order_id) AS category_orders,
           COUNT(*) AS item_count
    FROM analytics.pbi_fact_sales_item
    GROUP BY 1, category_key
)
SELECT m.purchase_month, m.category_key, m.category_gmv, m.category_orders, m.item_count,
       m.category_gmv / NULLIF(m.item_count, 0) AS average_item_value,
       m.category_gmv / NULLIF(m.category_orders, 0) AS average_category_order_value,
       c.category_quadrant
FROM monthly_metrics AS m
JOIN category_classification AS c USING (category_key);

CREATE OR REPLACE VIEW analytics.pbi_fact_seller_performance AS
WITH seller_metrics AS (
    SELECT seller_id, SUM(item_price) AS seller_gmv,
           COUNT(DISTINCT order_id) AS delivered_orders
    FROM analytics.pbi_fact_sales_item
    GROUP BY seller_id
), ranked AS (
    SELECT *, ROW_NUMBER() OVER (ORDER BY seller_gmv DESC, seller_id) AS seller_position,
           SUM(seller_gmv) OVER () AS total_seller_gmv,
           SUM(seller_gmv) OVER (ORDER BY seller_gmv DESC, seller_id) AS cumulative_gmv
    FROM seller_metrics
)
SELECT seller_id, seller_gmv, delivered_orders,
       seller_gmv / NULLIF(total_seller_gmv, 0) AS seller_gmv_share,
       cumulative_gmv / NULLIF(total_seller_gmv, 0) AS cumulative_gmv_share,
       seller_position
FROM ranked;

CREATE OR REPLACE VIEW analytics.pbi_fact_cohort_retention AS
SELECT cohort_month, month_index, cohort_size, active_customers, retention_rate
FROM analytics.customer_cohort_retention;

CREATE OR REPLACE VIEW analytics.pbi_fact_order_category_delivery AS
SELECT DISTINCT si.order_id, si.purchase_date, si.state_code, si.category_key,
       fo.delivery_days, fo.late_flag, fo.order_average_review_score
FROM analytics.pbi_fact_sales_item AS si
JOIN analytics.pbi_fact_order AS fo USING (order_id)
WHERE fo.delivery_days IS NOT NULL;
