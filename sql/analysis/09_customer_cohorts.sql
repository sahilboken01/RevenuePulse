-- Retention view grain: one row per cohort month and month index.
-- Cohort = month of first delivered purchase per customer_unique_id.
-- Active = at least one delivered order in that cohort-age month.
CREATE OR REPLACE VIEW analytics.customer_cohort_retention AS
WITH delivered_orders AS (
    SELECT o.order_id, c.customer_unique_id,
           date_trunc('month', o.order_purchase_timestamp)::date AS purchase_month
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
), first_purchase AS (
    SELECT customer_unique_id, MIN(purchase_month) AS cohort_month
    FROM delivered_orders
    GROUP BY customer_unique_id
), customer_activity AS (
    SELECT f.cohort_month, d.purchase_month, d.customer_unique_id,
           ((EXTRACT(YEAR FROM d.purchase_month) - EXTRACT(YEAR FROM f.cohort_month)) * 12
             + EXTRACT(MONTH FROM d.purchase_month) - EXTRACT(MONTH FROM f.cohort_month))::integer AS month_index
    FROM delivered_orders AS d
    JOIN first_purchase AS f USING (customer_unique_id)
    WHERE d.purchase_month >= f.cohort_month
), cohort_sizes AS (
    SELECT cohort_month, COUNT(*) AS cohort_size
    FROM first_purchase
    GROUP BY cohort_month
), period_end AS (
    SELECT MAX(purchase_month) AS last_month FROM delivered_orders
), active_by_age AS (
    SELECT cohort_month, month_index, COUNT(DISTINCT customer_unique_id) AS active_customers
    FROM customer_activity
    GROUP BY cohort_month, month_index
), cohort_age_grid AS (
    SELECT s.cohort_month, s.cohort_size, ages.month_index
    FROM cohort_sizes AS s
    CROSS JOIN period_end AS p
    CROSS JOIN LATERAL generate_series(
        0,
        ((EXTRACT(YEAR FROM p.last_month) - EXTRACT(YEAR FROM s.cohort_month)) * 12
          + EXTRACT(MONTH FROM p.last_month) - EXTRACT(MONTH FROM s.cohort_month))::integer
    ) AS ages(month_index)
)
SELECT g.cohort_month, g.month_index, g.cohort_size,
       COALESCE(a.active_customers, 0) AS active_customers,
       COALESCE(a.active_customers, 0)::numeric / NULLIF(g.cohort_size, 0) AS retention_rate
FROM cohort_age_grid AS g
LEFT JOIN active_by_age AS a USING (cohort_month, month_index);

SELECT cohort_month, month_index, cohort_size, active_customers,
       ROUND(retention_rate * 100, 2) AS retention_pct
FROM analytics.customer_cohort_retention
ORDER BY cohort_month, month_index;

-- Weighted retention by cohort age. Each age naturally includes only cohorts with
-- enough observed follow-up through the dataset's final purchase month.
SELECT month_index, COUNT(*) AS eligible_cohorts,
       SUM(active_customers) AS active_customers,
       SUM(cohort_size) AS cohort_customers,
       ROUND(100.0 * SUM(active_customers) / NULLIF(SUM(cohort_size), 0), 2) AS weighted_retention_pct
FROM analytics.customer_cohort_retention
GROUP BY month_index
ORDER BY month_index;
