-- Revenue means merchandise GMV: SUM(order_items.price), excluding freight.
-- Scope: delivered orders only. Grain: one row per order in order_gmv.
WITH order_gmv AS (
    SELECT o.order_id,
           o.order_purchase_timestamp,
           SUM(oi.price) AS gmv
    FROM olist.orders AS o
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY o.order_id, o.order_purchase_timestamp
)
SELECT COUNT(*) AS delivered_orders,
       SUM(gmv) AS total_gmv_brl,
       AVG(gmv) AS average_order_value_brl
FROM order_gmv;

-- Monthly grain: one row per purchase month; revenue and AOV use delivered orders.
WITH order_gmv AS (
    SELECT o.order_id, o.order_purchase_timestamp, SUM(oi.price) AS gmv
    FROM olist.orders AS o
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY o.order_id, o.order_purchase_timestamp
)
SELECT date_trunc('month', order_purchase_timestamp)::date AS purchase_month,
       COUNT(*) AS delivered_orders,
       SUM(gmv) AS monthly_gmv_brl,
       AVG(gmv) AS average_order_value_brl
FROM order_gmv
GROUP BY 1
ORDER BY 1;
