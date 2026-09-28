-- Delivered customer orders: one row per order, linked to the stable unique customer key.
WITH delivered_order_gmv AS (
    SELECT o.order_id, o.order_purchase_timestamp, c.customer_unique_id,
           SUM(oi.price) AS gmv
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY o.order_id, o.order_purchase_timestamp, c.customer_unique_id
), ranked_orders AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY customer_unique_id ORDER BY order_purchase_timestamp, order_id) AS customer_order_number
    FROM delivered_order_gmv
)
-- New versus returning orders, monthly grain.
SELECT date_trunc('month', order_purchase_timestamp)::date AS purchase_month,
       CASE WHEN customer_order_number = 1 THEN 'new_customer_order' ELSE 'returning_customer_order' END AS customer_order_type,
       COUNT(*) AS order_count,
       COUNT(DISTINCT customer_unique_id) AS customers_with_order,
       SUM(gmv) AS gmv_brl
FROM ranked_orders
GROUP BY 1, 2
ORDER BY 1, 2;

-- Overall repeat purchase rate: distinct customers with 2+ delivered orders / all
-- customers with at least 1 delivered order observed in this dataset.
WITH customer_frequency AS (
    SELECT c.customer_unique_id, COUNT(*) AS delivered_orders
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT COUNT(*) FILTER (WHERE delivered_orders >= 2) AS repeat_customers,
       COUNT(*) AS observed_buyers,
       COUNT(*) FILTER (WHERE delivered_orders >= 2)::numeric / NULLIF(COUNT(*), 0) AS repeat_purchase_rate,
       AVG(delivered_orders::numeric) AS average_delivered_orders_per_customer
FROM customer_frequency;

-- Customer revenue distribution, one row per unique customer; NTILE gives quintiles.
WITH customer_value AS (
    SELECT c.customer_unique_id, COUNT(DISTINCT o.order_id) AS delivered_orders,
           SUM(oi.price) AS customer_gmv
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
), ranked_value AS (
    SELECT *, NTILE(5) OVER (ORDER BY customer_gmv) AS gmv_quintile
    FROM customer_value
)
SELECT gmv_quintile, COUNT(*) AS customers,
       MIN(customer_gmv) AS min_customer_gmv_brl,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY customer_gmv) AS median_customer_gmv_brl,
       MAX(customer_gmv) AS max_customer_gmv_brl,
       SUM(customer_gmv) AS quintile_gmv_brl
FROM ranked_value
GROUP BY gmv_quintile
ORDER BY gmv_quintile;
