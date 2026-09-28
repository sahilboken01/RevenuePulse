-- Review/order rows can be multiple per order. Collapse review scores to order grain
-- before joining to one delivered order, so delivery rows are not multiplied.
WITH order_review AS (
    SELECT order_id, AVG(review_score::numeric) AS order_average_review_score,
           COUNT(*) AS review_order_records
    FROM olist.order_reviews
    GROUP BY order_id
), delivered_order AS (
    SELECT o.order_id,
           EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_purchase_timestamp)) / 86400.0 AS delivery_days,
           (o.order_delivered_customer_date > o.order_estimated_delivery_date) AS is_late
    FROM olist.orders AS o
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
)
SELECT CASE WHEN d.is_late THEN 'late' ELSE 'on_time' END AS delivery_status,
       COUNT(*) AS delivered_orders,
       COUNT(*) FILTER (WHERE r.order_average_review_score IS NOT NULL) AS orders_with_reviews,
       AVG(r.order_average_review_score) AS average_order_review_score,
       AVG(d.delivery_days) AS average_delivery_days
FROM delivered_order AS d
LEFT JOIN order_review AS r USING (order_id)
GROUP BY delivery_status
ORDER BY delivery_status;

-- Delivery duration buckets plus Pearson correlation. This describes association,
-- not a causal effect; product, seller, location, and customer factors can confound it.
WITH order_review AS (
    SELECT order_id, AVG(review_score::numeric) AS order_average_review_score
    FROM olist.order_reviews
    GROUP BY order_id
), delivered_order AS (
    SELECT o.order_id,
           EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_purchase_timestamp)) / 86400.0 AS delivery_days
    FROM olist.orders AS o
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
)
SELECT CASE
           WHEN d.delivery_days < 3 THEN 'under_3_days'
           WHEN d.delivery_days < 7 THEN '3_to_6_days'
           WHEN d.delivery_days < 14 THEN '7_to_13_days'
           ELSE '14_days_or_more'
       END AS delivery_time_bucket,
       COUNT(*) AS delivered_orders,
       COUNT(r.order_average_review_score) AS orders_with_reviews,
       AVG(r.order_average_review_score) AS average_order_review_score,
       CORR(d.delivery_days, r.order_average_review_score) AS delivery_days_review_score_correlation
FROM delivered_order AS d
LEFT JOIN order_review AS r USING (order_id)
GROUP BY delivery_time_bucket
ORDER BY MIN(d.delivery_days);

-- Overall order-grain association across all eligible delivered orders.
WITH order_review AS (
    SELECT order_id, AVG(review_score::numeric) AS order_average_review_score
    FROM olist.order_reviews
    GROUP BY order_id
), delivered_order AS (
    SELECT o.order_id,
           EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_purchase_timestamp)) / 86400.0 AS delivery_days
    FROM olist.orders AS o
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
)
SELECT COUNT(*) AS matched_orders,
       CORR(d.delivery_days, r.order_average_review_score) AS pearson_correlation,
       AVG(d.delivery_days) AS average_delivery_days,
       AVG(r.order_average_review_score) AS average_order_review_score
FROM delivered_order AS d
JOIN order_review AS r USING (order_id);
