-- Review/order-record grain. review_id is reused across orders in this source;
-- use each source row (review_id, order_id), never assume review_id is unique.
SELECT AVG(review_score::numeric) AS average_review_score,
       COUNT(*) AS review_records
FROM olist.order_reviews;

-- Review/order-record grain, joined to one order row. Buckets use elapsed days.
WITH review_delivery AS (
    SELECT r.review_id, r.review_score,
           EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_purchase_timestamp)) / 86400.0 AS delivery_days
    FROM olist.order_reviews AS r
    JOIN olist.orders AS o ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
), bucketed AS (
    SELECT *, CASE
        WHEN delivery_days < 0 THEN 'invalid_negative'
        WHEN delivery_days < 3 THEN 'under_3_days'
        WHEN delivery_days < 7 THEN '3_to_6_days'
        WHEN delivery_days < 14 THEN '7_to_13_days'
        ELSE '14_days_or_more'
    END AS delivery_bucket
    FROM review_delivery
)
SELECT delivery_bucket, COUNT(*) AS review_records,
       AVG(review_score::numeric) AS average_review_score
FROM bucketed
GROUP BY delivery_bucket
ORDER BY MIN(delivery_days);

-- Category-review grain: order-category pairs joined to review rows. A multi-category
-- order contributes its review score once to each category present in that order.
WITH order_categories AS (
    SELECT DISTINCT oi.order_id,
           COALESCE(ct.product_category_name_english, p.product_category_name, 'unknown') AS category
    FROM olist.order_items AS oi
    JOIN olist.products AS p ON p.product_id = oi.product_id
    LEFT JOIN olist.category_translation AS ct ON ct.product_category_name = p.product_category_name
)
SELECT oc.category, COUNT(*) AS review_records,
       AVG(r.review_score::numeric) AS average_review_score
FROM order_categories AS oc
JOIN olist.order_reviews AS r ON r.order_id = oc.order_id
GROUP BY oc.category
ORDER BY review_records DESC;
