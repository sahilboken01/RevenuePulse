-- One row per delivered order before customer classification.
WITH order_gmv AS (
    SELECT o.order_id, o.customer_id, SUM(oi.price) AS order_gmv
    FROM olist.orders AS o
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY o.order_id, o.customer_id
), customer_value AS (
    SELECT c.customer_unique_id, COUNT(*) AS delivered_orders,
           SUM(og.order_gmv) AS customer_gmv,
           CASE WHEN COUNT(*) = 1 THEN 'one-time' ELSE 'repeat' END AS purchase_type
    FROM order_gmv AS og
    JOIN olist.customers AS c ON c.customer_id = og.customer_id
    GROUP BY c.customer_unique_id
)
SELECT purchase_type, COUNT(*) AS customers,
       AVG(customer_gmv) AS average_revenue_per_customer_brl,
       SUM(customer_gmv) AS revenue_brl,
       SUM(customer_gmv) / NULLIF(SUM(SUM(customer_gmv)) OVER (), 0) AS revenue_share,
       AVG(delivered_orders::numeric) AS average_delivered_orders
FROM customer_value
GROUP BY purchase_type
ORDER BY purchase_type;
