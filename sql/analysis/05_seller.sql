-- Seller grain. Each item belongs to one seller; GMV is item price, freight excluded.
WITH seller_metrics AS (
    SELECT s.seller_id, s.seller_state,
           SUM(oi.price) AS seller_gmv,
           COUNT(DISTINCT oi.order_id) AS seller_orders
    FROM olist.orders AS o
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    JOIN olist.sellers AS s ON s.seller_id = oi.seller_id
    WHERE o.order_status = 'delivered'
    GROUP BY s.seller_id, s.seller_state
), concentration AS (
    SELECT *,
           SUM(seller_gmv) OVER (ORDER BY seller_gmv DESC, seller_id) AS cumulative_gmv,
           SUM(seller_gmv) OVER () AS total_gmv,
           DENSE_RANK() OVER (ORDER BY seller_gmv DESC) AS seller_rank
    FROM seller_metrics
)
SELECT seller_id, seller_state, seller_gmv AS seller_gmv_brl, seller_orders,
       seller_rank,
       cumulative_gmv / NULLIF(total_gmv, 0) AS cumulative_gmv_share
FROM concentration
ORDER BY seller_rank, seller_id;

-- Top-10 seller share: seller grain -> one summary row.
WITH seller_gmv AS (
    SELECT oi.seller_id, SUM(oi.price) AS gmv
    FROM olist.orders AS o
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY oi.seller_id
), ranked AS (
    SELECT *, ROW_NUMBER() OVER (ORDER BY gmv DESC, seller_id) AS seller_number,
           SUM(gmv) OVER () AS all_seller_gmv
    FROM seller_gmv
)
SELECT SUM(gmv) FILTER (WHERE seller_number <= 10) AS top_10_seller_gmv_brl,
       MAX(all_seller_gmv) AS total_seller_gmv_brl,
       SUM(gmv) FILTER (WHERE seller_number <= 10) / NULLIF(MAX(all_seller_gmv), 0) AS top_10_gmv_share
FROM ranked;
