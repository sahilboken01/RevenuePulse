-- Category/order grain avoids counting an order more than once in order volume.
WITH category_order AS (
    SELECT COALESCE(ct.product_category_name_english, p.product_category_name, 'unknown') AS category,
           oi.order_id, SUM(oi.price) AS category_order_gmv,
           COUNT(*) AS items_in_category_order
    FROM olist.orders AS o
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    JOIN olist.products AS p ON p.product_id = oi.product_id
    LEFT JOIN olist.category_translation AS ct
      ON ct.product_category_name = p.product_category_name
    WHERE o.order_status = 'delivered'
    GROUP BY 1, oi.order_id
), category_metrics AS (
    SELECT category,
           SUM(category_order_gmv) AS category_gmv,
           COUNT(*) AS orders_containing_category,
           SUM(items_in_category_order) AS item_count,
           SUM(category_order_gmv) / NULLIF(SUM(items_in_category_order), 0) AS average_item_value,
           AVG(category_order_gmv) AS average_category_spend_per_order
    FROM category_order
    GROUP BY category
), category_benchmarks AS (
    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY orders_containing_category) AS median_category_orders,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY average_category_spend_per_order) AS median_category_order_value
    FROM category_metrics
)
SELECT m.category, m.category_gmv AS category_gmv_brl,
       m.orders_containing_category, m.item_count,
       m.average_item_value AS average_item_value_brl,
       m.average_category_spend_per_order AS average_category_order_value_brl,
       CASE WHEN m.orders_containing_category >= b.median_category_orders
             AND m.average_category_spend_per_order >= b.median_category_order_value THEN 'high-volume / high-value'
            WHEN m.orders_containing_category >= b.median_category_orders THEN 'high-volume / lower-value'
            WHEN m.average_category_spend_per_order >= b.median_category_order_value THEN 'lower-volume / high-value'
            ELSE 'lower-volume / lower-value' END AS category_quadrant
FROM category_metrics AS m
CROSS JOIN category_benchmarks AS b
ORDER BY m.category_gmv DESC;
