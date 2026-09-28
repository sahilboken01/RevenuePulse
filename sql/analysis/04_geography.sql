-- State grain. First aggregate line items to one order, then attach its customer state.
WITH order_gmv AS (
    SELECT o.order_id, o.customer_id, SUM(oi.price) AS gmv
    FROM olist.orders AS o
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY o.order_id, o.customer_id
)
SELECT c.customer_state AS state,
       COUNT(*) AS delivered_orders,
       SUM(og.gmv) AS gmv_brl,
       AVG(og.gmv) AS average_order_value_brl
FROM order_gmv AS og
JOIN olist.customers AS c ON c.customer_id = og.customer_id
GROUP BY c.customer_state
ORDER BY gmv_brl DESC;
