-- One row per seller with delivered item GMV and shares. Rank is deterministic.
WITH seller_gmv AS (
    SELECT oi.seller_id, SUM(oi.price) AS seller_gmv,
           COUNT(DISTINCT oi.order_id) AS delivered_orders
    FROM olist.orders AS o
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY oi.seller_id
), ranked_sellers AS (
    SELECT *, ROW_NUMBER() OVER (ORDER BY seller_gmv DESC, seller_id) AS seller_position,
           SUM(seller_gmv) OVER () AS total_seller_gmv,
           SUM(seller_gmv) OVER (ORDER BY seller_gmv DESC, seller_id) AS cumulative_gmv
    FROM seller_gmv
)
SELECT seller_id, seller_gmv AS seller_gmv_brl, delivered_orders,
       seller_gmv / NULLIF(total_seller_gmv, 0) AS seller_gmv_share,
       cumulative_gmv / NULLIF(total_seller_gmv, 0) AS cumulative_gmv_share,
       seller_position
FROM ranked_sellers
ORDER BY seller_position;

-- Aggregate contribution from the leading 10 and 20 active sellers.
WITH seller_gmv AS (
    SELECT oi.seller_id, SUM(oi.price) AS gmv
    FROM olist.orders AS o
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY oi.seller_id
), ranked AS (
    SELECT *, ROW_NUMBER() OVER (ORDER BY gmv DESC, seller_id) AS seller_position,
           SUM(gmv) OVER () AS all_seller_gmv
    FROM seller_gmv
)
SELECT SUM(gmv) FILTER (WHERE seller_position <= 10) AS top_10_gmv_brl,
       SUM(gmv) FILTER (WHERE seller_position <= 10) / NULLIF(MAX(all_seller_gmv), 0) AS top_10_share,
       SUM(gmv) FILTER (WHERE seller_position <= 20) AS top_20_gmv_brl,
       SUM(gmv) FILTER (WHERE seller_position <= 20) / NULLIF(MAX(all_seller_gmv), 0) AS top_20_share,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY gmv) AS median_seller_gmv_brl,
       percentile_cont(0.9) WITHIN GROUP (ORDER BY gmv) AS p90_seller_gmv_brl,
       MIN(gmv) AS minimum_seller_gmv_brl,
       MAX(gmv) AS maximum_seller_gmv_brl,
       COUNT(*) AS active_sellers
FROM ranked;
