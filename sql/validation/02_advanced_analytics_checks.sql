-- Run after the Stage 4 files create the analytics views.
-- Expected output: zero failed_checks.
WITH delivered_customer AS (
    SELECT c.customer_unique_id, SUM(oi.price) AS customer_gmv
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
), base_gmv AS (
    SELECT SUM(oi.price) AS gmv
    FROM olist.orders AS o
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
), rfm_checks AS (
    SELECT COUNT(*) AS rows,
           COUNT(DISTINCT customer_unique_id) AS customers,
           COUNT(*) FILTER (WHERE recency_score NOT BETWEEN 1 AND 5
                             OR frequency_score NOT BETWEEN 1 AND 5
                             OR monetary_score NOT BETWEEN 1 AND 5
                             OR customer_segment IS NULL) AS invalid_rows,
           SUM(monetary_gmv) AS rfm_gmv
    FROM analytics.rfm_customer_segments
), cohort_checks AS (
    SELECT COUNT(*) FILTER (WHERE month_index = 0 AND retention_rate <> 1) AS invalid_month_zero,
           COUNT(*) FILTER (WHERE retention_rate < 0 OR retention_rate > 1) AS invalid_rates
    FROM analytics.customer_cohort_retention
), customer_value_checks AS (
    SELECT SUM(customer_gmv) AS customer_gmv,
           COUNT(*) AS customer_count,
           COUNT(DISTINCT customer_unique_id) AS distinct_customers
    FROM delivered_customer
), delivery_counts AS (
    SELECT COUNT(*) AS expected_orders
    FROM olist.orders
    WHERE order_status = 'delivered'
      AND order_delivered_customer_date IS NOT NULL
      AND order_estimated_delivery_date IS NOT NULL
), seller_gmv AS (
    SELECT oi.seller_id, SUM(oi.price) AS gmv
    FROM olist.orders AS o
    JOIN olist.order_items AS oi USING (order_id)
    WHERE o.order_status = 'delivered'
    GROUP BY oi.seller_id
), ranked_sellers AS (
    SELECT *, ROW_NUMBER() OVER (ORDER BY gmv DESC, seller_id) AS seller_position,
           SUM(gmv) OVER () AS all_seller_gmv
    FROM seller_gmv
), seller_shares AS (
    SELECT SUM(gmv) FILTER (WHERE seller_position <= 10) / NULLIF(MAX(all_seller_gmv), 0) AS top_10_share,
           SUM(gmv) FILTER (WHERE seller_position <= 20) / NULLIF(MAX(all_seller_gmv), 0) AS top_20_share
    FROM ranked_sellers
), checks AS (
    SELECT 'rfm_one_row_per_customer' AS check_name,
           CASE WHEN rows = customers AND invalid_rows = 0 THEN 0 ELSE 1 END AS failed_checks
    FROM rfm_checks
    UNION ALL
    SELECT 'rfm_gmv_reconciles_to_delivered_gmv',
           CASE WHEN ABS(rfm_gmv - (SELECT gmv FROM base_gmv)) < 0.01 THEN 0 ELSE 1 END
    FROM rfm_checks
    UNION ALL
    SELECT 'cohort_month_zero_is_100_percent', invalid_month_zero FROM cohort_checks
    UNION ALL
    SELECT 'cohort_retention_between_zero_and_one', invalid_rates FROM cohort_checks
    UNION ALL
    SELECT 'customer_value_reconciles_to_delivered_gmv',
           CASE WHEN ABS(customer_gmv - (SELECT gmv FROM base_gmv)) < 0.01
                     AND customer_count = distinct_customers THEN 0 ELSE 1 END
    FROM customer_value_checks
    UNION ALL
    SELECT 'delivery_population_is_unique_by_order',
           CASE WHEN COUNT(*) = (SELECT expected_orders FROM delivery_counts) THEN 0 ELSE 1 END
    FROM (
        SELECT order_id
        FROM olist.orders
        WHERE order_status = 'delivered'
          AND order_delivered_customer_date IS NOT NULL
          AND order_estimated_delivery_date IS NOT NULL
        GROUP BY order_id
    ) delivered_with_estimate
    UNION ALL
    SELECT 'product_category_gmv_reconciles',
           CASE WHEN ABS((SELECT SUM(oi.price)
                          FROM olist.orders AS o
                          JOIN olist.order_items AS oi USING (order_id)
                          JOIN olist.products AS p USING (product_id)
                          WHERE o.order_status = 'delivered')
                     - (SELECT gmv FROM base_gmv)) < 0.01 THEN 0 ELSE 1 END
    UNION ALL
    SELECT 'seller_top20_share_ge_top10_and_le_one',
           CASE WHEN top_10_share <= top_20_share AND top_20_share <= 1 THEN 0 ELSE 1 END
    FROM seller_shares
)
SELECT check_name, failed_checks FROM checks ORDER BY check_name;
