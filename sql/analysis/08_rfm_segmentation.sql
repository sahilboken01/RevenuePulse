-- One row per customer_unique_id. Snapshot is the day after the last delivered
-- purchase in the analysis data (never the machine's current date), so this model
-- does not use information after the observed Olist period.
CREATE OR REPLACE VIEW analytics.rfm_customer_segments AS
WITH delivered_order_gmv AS (
    SELECT o.order_id, o.customer_id, o.order_purchase_timestamp,
           SUM(oi.price) AS order_gmv
    FROM olist.orders AS o
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY o.order_id, o.customer_id, o.order_purchase_timestamp
), analysis_snapshot AS (
    SELECT MAX(order_purchase_timestamp)::date + 1 AS snapshot_date
    FROM delivered_order_gmv
), customer_rfm AS (
    SELECT c.customer_unique_id,
           s.snapshot_date,
           (s.snapshot_date - MAX(d.order_purchase_timestamp)::date) AS recency_days,
           COUNT(DISTINCT d.order_id) AS frequency_orders,
           SUM(d.order_gmv) AS monetary_gmv
    FROM delivered_order_gmv AS d
    JOIN olist.customers AS c ON c.customer_id = d.customer_id
    CROSS JOIN analysis_snapshot AS s
    GROUP BY c.customer_unique_id, s.snapshot_date
), scored AS (
    SELECT *,
           6 - NTILE(5) OVER (ORDER BY recency_days ASC, customer_unique_id) AS recency_score,
           NTILE(5) OVER (ORDER BY frequency_orders ASC, customer_unique_id) AS frequency_score,
           NTILE(5) OVER (ORDER BY monetary_gmv ASC, customer_unique_id) AS monetary_score
    FROM customer_rfm
)
SELECT customer_unique_id, snapshot_date, recency_days, frequency_orders,
       monetary_gmv, recency_score, frequency_score, monetary_score,
       CASE
           WHEN recency_score >= 4 AND frequency_score >= 4 AND monetary_score >= 4 THEN 'Champions'
           WHEN recency_score <= 2 AND frequency_score >= 4 THEN 'Cannot Lose Them'
           WHEN recency_score >= 3 AND frequency_score >= 4 THEN 'Loyal Customers'
           WHEN recency_score >= 4 AND frequency_score BETWEEN 2 AND 3 THEN 'Potential Loyalists'
           WHEN recency_score >= 4 AND frequency_score = 1 THEN 'New Customers'
           WHEN recency_score <= 2 AND frequency_score = 3 THEN 'At Risk'
           WHEN recency_score <= 2 AND frequency_score <= 2 THEN 'Hibernating'
           WHEN recency_score = 3 AND frequency_score >= 2 THEN 'Need Attention'
           ELSE 'Promising'
       END AS customer_segment
FROM scored;

-- Segment counts, share of observed customers, and GMV contribution.
SELECT customer_segment, COUNT(*) AS customers,
       COUNT(*)::numeric / SUM(COUNT(*)) OVER () AS customer_share,
       SUM(monetary_gmv) AS segment_gmv_brl,
       SUM(monetary_gmv) / NULLIF(SUM(SUM(monetary_gmv)) OVER (), 0) AS gmv_share
FROM analytics.rfm_customer_segments
GROUP BY customer_segment
ORDER BY segment_gmv_brl DESC;
