-- Optional PostgreSQL/psql export route for the same Power BI datasets.
-- Run after 01_powerbi_views.sql, from the RevenuePulse project directory.
\copy (SELECT * FROM analytics.pbi_dim_date ORDER BY date) TO 'powerbi/data/dim_date.csv' WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM analytics.pbi_dim_customer ORDER BY customer_unique_id) TO 'powerbi/data/dim_customer.csv' WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM analytics.pbi_dim_category ORDER BY category_key) TO 'powerbi/data/dim_category.csv' WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM analytics.pbi_dim_product ORDER BY product_id) TO 'powerbi/data/dim_product.csv' WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM analytics.pbi_dim_seller ORDER BY seller_id) TO 'powerbi/data/dim_seller.csv' WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM analytics.pbi_dim_geography ORDER BY state_code) TO 'powerbi/data/dim_geography.csv' WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM analytics.pbi_fact_order ORDER BY order_id) TO 'powerbi/data/fact_order.csv' WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM analytics.pbi_fact_sales_item ORDER BY order_id, order_item_id) TO 'powerbi/data/fact_sales_item.csv' WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM analytics.pbi_fact_category_economics ORDER BY category_key) TO 'powerbi/data/fact_category_economics.csv' WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM analytics.pbi_fact_seller_performance ORDER BY seller_position) TO 'powerbi/data/fact_seller_performance.csv' WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM analytics.pbi_fact_cohort_retention ORDER BY cohort_month, month_index) TO 'powerbi/data/fact_cohort_retention.csv' WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM analytics.pbi_fact_order_category_delivery ORDER BY order_id, category_key) TO 'powerbi/data/fact_order_category_delivery.csv' WITH (FORMAT csv, HEADER true)
