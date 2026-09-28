-- Every check should return zero violations. Queries use the delivered-order scope
-- and merchandise GMV (item price only) used by the analysis files.
WITH checks AS (
    SELECT 'duplicate_order_id' AS check_name, COUNT(*) AS violations
    FROM (SELECT order_id FROM olist.orders GROUP BY order_id HAVING COUNT(*) > 1) d
    UNION ALL
    SELECT 'duplicate_order_item_key', COUNT(*)
    FROM (SELECT order_id, order_item_id FROM olist.order_items GROUP BY 1, 2 HAVING COUNT(*) > 1) d
    UNION ALL
    SELECT 'duplicate_review_order_key', COUNT(*)
    FROM (SELECT review_id, order_id FROM olist.order_reviews GROUP BY 1, 2 HAVING COUNT(*) > 1) d
    UNION ALL
    SELECT 'orphan_item_order', COUNT(*)
    FROM olist.order_items AS oi LEFT JOIN olist.orders AS o USING (order_id)
    WHERE o.order_id IS NULL
    UNION ALL
    SELECT 'orphan_item_product', COUNT(*)
    FROM olist.order_items AS oi LEFT JOIN olist.products AS p USING (product_id)
    WHERE p.product_id IS NULL
    UNION ALL
    SELECT 'negative_item_price', COUNT(*) FROM olist.order_items WHERE price < 0
    UNION ALL
    SELECT 'negative_freight', COUNT(*) FROM olist.order_items WHERE freight_value < 0
)
SELECT check_name, violations FROM checks ORDER BY check_name;

-- Revenue reconciliation: both paths should match exactly (to stored cents).
WITH order_gmv AS (
    SELECT o.order_id, SUM(oi.price) AS gmv
    FROM olist.orders AS o
    JOIN olist.order_items AS oi USING (order_id)
    WHERE o.order_status = 'delivered'
    GROUP BY o.order_id
), total_gmv AS (
    SELECT SUM(gmv) AS total FROM order_gmv
), monthly_gmv AS (
    SELECT date_trunc('month', o.order_purchase_timestamp) AS month,
           SUM(oi.price) AS gmv
    FROM olist.orders AS o
    JOIN olist.order_items AS oi USING (order_id)
    WHERE o.order_status = 'delivered'
    GROUP BY 1
)
SELECT (SELECT total FROM total_gmv) AS order_level_gmv_brl,
       (SELECT SUM(gmv) FROM monthly_gmv) AS monthly_gmv_brl,
       (SELECT total FROM total_gmv) - (SELECT SUM(gmv) FROM monthly_gmv) AS difference_brl;

-- Category and seller totals should reconcile to total delivered merchandise GMV.
WITH overall AS (
    SELECT SUM(oi.price) AS gmv
    FROM olist.orders AS o JOIN olist.order_items AS oi USING (order_id)
    WHERE o.order_status = 'delivered'
), category_totals AS (
    SELECT SUM(oi.price) AS gmv
    FROM olist.orders AS o JOIN olist.order_items AS oi USING (order_id)
    JOIN olist.products AS p USING (product_id)
    WHERE o.order_status = 'delivered'
), seller_totals AS (
    SELECT SUM(oi.price) AS gmv
    FROM olist.orders AS o JOIN olist.order_items AS oi USING (order_id)
    JOIN olist.sellers AS s USING (seller_id)
    WHERE o.order_status = 'delivered'
)
SELECT overall.gmv AS overall_gmv_brl,
       category_totals.gmv AS product_category_gmv_brl,
       seller_totals.gmv AS seller_gmv_brl,
       overall.gmv - category_totals.gmv AS category_difference_brl,
       overall.gmv - seller_totals.gmv AS seller_difference_brl
FROM overall CROSS JOIN category_totals CROSS JOIN seller_totals;
