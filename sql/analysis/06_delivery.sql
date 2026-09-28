-- Order grain. Only delivered orders with both timestamps are included in duration.
WITH delivered_orders AS (
    SELECT o.order_id, o.customer_id, o.order_purchase_timestamp,
           o.order_delivered_customer_date, o.order_estimated_delivery_date,
           EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_purchase_timestamp)) / 86400.0 AS delivery_days,
           (o.order_delivered_customer_date > o.order_estimated_delivery_date) AS is_late
    FROM olist.orders AS o
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
)
SELECT COUNT(*) AS delivered_orders_with_delivery_date,
       AVG(delivery_days) AS average_delivery_days,
       COUNT(*) FILTER (WHERE is_late) AS late_orders,
       COUNT(*) FILTER (WHERE is_late)::numeric /
           NULLIF(COUNT(*) FILTER (WHERE order_estimated_delivery_date IS NOT NULL), 0) AS late_delivery_rate
FROM delivered_orders;

-- Order-category grain: same order can appear once in each category it contains.
WITH delivered_orders AS (
    SELECT order_id, order_purchase_timestamp, order_delivered_customer_date,
           order_estimated_delivery_date,
           EXTRACT(EPOCH FROM (order_delivered_customer_date - order_purchase_timestamp)) / 86400.0 AS delivery_days,
           (order_delivered_customer_date > order_estimated_delivery_date) AS is_late
    FROM olist.orders
    WHERE order_status = 'delivered' AND order_delivered_customer_date IS NOT NULL
), order_category AS (
    SELECT DISTINCT oi.order_id,
           COALESCE(ct.product_category_name_english, p.product_category_name, 'unknown') AS category
    FROM olist.order_items AS oi
    JOIN olist.products AS p ON p.product_id = oi.product_id
    LEFT JOIN olist.category_translation AS ct ON ct.product_category_name = p.product_category_name
)
SELECT oc.category, COUNT(*) AS delivered_orders_containing_category,
       AVG(d.delivery_days) AS average_delivery_days,
       COUNT(*) FILTER (WHERE d.is_late)::numeric /
           NULLIF(COUNT(*) FILTER (WHERE d.order_estimated_delivery_date IS NOT NULL), 0) AS late_delivery_rate
FROM order_category AS oc
JOIN delivered_orders AS d ON d.order_id = oc.order_id
GROUP BY oc.category
ORDER BY delivered_orders_containing_category DESC;

-- Customer state grain. One delivered order maps to one customer state.
WITH delivered_orders AS (
    SELECT o.order_id, o.customer_id,
           EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_purchase_timestamp)) / 86400.0 AS delivery_days,
           (o.order_delivered_customer_date > o.order_estimated_delivery_date) AS is_late
    FROM olist.orders AS o
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
)
SELECT c.customer_state AS state, COUNT(*) AS delivered_orders,
       AVG(d.delivery_days) AS average_delivery_days,
       COUNT(*) FILTER (WHERE d.is_late)::numeric /
           NULLIF(COUNT(*) FILTER (WHERE d.is_late IS NOT NULL), 0) AS late_delivery_rate
FROM delivered_orders AS d
JOIN olist.customers AS c ON c.customer_id = d.customer_id
GROUP BY c.customer_state
ORDER BY delivered_orders DESC;
