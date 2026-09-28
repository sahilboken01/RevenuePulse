-- Category grain. Category AOV is category GMV / distinct orders containing it;
-- a multi-category order contributes its category item spend to each category's AOV.
WITH category_orders AS (
    SELECT COALESCE(ct.product_category_name_english, p.product_category_name, 'unknown') AS category,
           oi.order_id,
           SUM(oi.price) AS category_order_gmv
    FROM olist.orders AS o
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    JOIN olist.products AS p ON p.product_id = oi.product_id
    LEFT JOIN olist.category_translation AS ct
      ON ct.product_category_name = p.product_category_name
    WHERE o.order_status = 'delivered'
    GROUP BY 1, oi.order_id
)
SELECT category,
       SUM(category_order_gmv) AS category_gmv_brl,
       COUNT(*) AS orders_containing_category,
       SUM(category_order_gmv) / NULLIF(COUNT(*), 0) AS average_category_spend_per_order_brl,
       DENSE_RANK() OVER (ORDER BY SUM(category_order_gmv) DESC) AS gmv_rank,
       DENSE_RANK() OVER (ORDER BY COUNT(*) DESC) AS order_count_rank
FROM category_orders
GROUP BY category
ORDER BY category_gmv_brl DESC;
