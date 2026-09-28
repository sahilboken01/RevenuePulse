-- psql client script. Execute after 00_schema.sql, from the RevenuePulse root.
-- These are cleaned Stage 2 files; raw files are never loaded by this script.
\copy olist.customers FROM 'data/processed/olist_customers_dataset.csv' WITH (FORMAT csv, HEADER true, NULL '')
\copy olist.category_translation FROM 'data/processed/product_category_name_translation.csv' WITH (FORMAT csv, HEADER true, NULL '')
\copy olist.products FROM 'data/processed/olist_products_dataset.csv' WITH (FORMAT csv, HEADER true, NULL '')
\copy olist.sellers FROM 'data/processed/olist_sellers_dataset.csv' WITH (FORMAT csv, HEADER true, NULL '')
\copy olist.orders FROM 'data/processed/olist_orders_dataset.csv' WITH (FORMAT csv, HEADER true, NULL '')
\copy olist.order_items FROM 'data/processed/olist_order_items_dataset.csv' WITH (FORMAT csv, HEADER true, NULL '')
\copy olist.order_payments FROM 'data/processed/olist_order_payments_dataset.csv' WITH (FORMAT csv, HEADER true, NULL '')
\copy olist.order_reviews FROM 'data/processed/olist_order_reviews_dataset.csv' WITH (FORMAT csv, HEADER true, NULL '')
\copy olist.geolocation FROM 'data/processed/olist_geolocation_dataset.csv' WITH (FORMAT csv, HEADER true, NULL '')
