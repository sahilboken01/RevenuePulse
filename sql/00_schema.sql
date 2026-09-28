-- PostgreSQL landing schema for the cleaned Stage 2 CSVs.
-- Run from the RevenuePulse project directory in psql.
CREATE SCHEMA IF NOT EXISTS olist;
CREATE SCHEMA IF NOT EXISTS analytics;
SET search_path TO olist, public;

CREATE TABLE IF NOT EXISTS customers (
    customer_id text PRIMARY KEY,
    customer_unique_id text NOT NULL,
    customer_zip_code_prefix integer,
    customer_city text,
    customer_state char(2)
);
CREATE TABLE IF NOT EXISTS orders (
    order_id text PRIMARY KEY,
    customer_id text NOT NULL REFERENCES customers(customer_id),
    order_status text NOT NULL,
    order_purchase_timestamp timestamp NOT NULL,
    order_approved_at timestamp,
    order_delivered_carrier_date timestamp,
    order_delivered_customer_date timestamp,
    order_estimated_delivery_date timestamp
);
CREATE TABLE IF NOT EXISTS products (
    product_id text PRIMARY KEY,
    product_category_name text,
    product_name_lenght integer,
    product_description_lenght integer,
    product_photos_qty integer,
    product_weight_g numeric(12, 2),
    product_length_cm numeric(12, 2),
    product_height_cm numeric(12, 2),
    product_width_cm numeric(12, 2)
);
CREATE TABLE IF NOT EXISTS category_translation (
    product_category_name text PRIMARY KEY,
    product_category_name_english text NOT NULL
);
CREATE TABLE IF NOT EXISTS sellers (
    seller_id text PRIMARY KEY,
    seller_zip_code_prefix integer,
    seller_city text,
    seller_state char(2)
);
CREATE TABLE IF NOT EXISTS order_items (
    order_id text NOT NULL REFERENCES orders(order_id),
    order_item_id integer NOT NULL,
    product_id text NOT NULL REFERENCES products(product_id),
    seller_id text NOT NULL REFERENCES sellers(seller_id),
    shipping_limit_date timestamp,
    price numeric(12, 2),
    freight_value numeric(12, 2),
    PRIMARY KEY (order_id, order_item_id)
);
CREATE TABLE IF NOT EXISTS order_payments (
    order_id text NOT NULL REFERENCES orders(order_id),
    payment_sequential integer NOT NULL,
    payment_type text,
    payment_installments integer,
    payment_value numeric(12, 2),
    PRIMARY KEY (order_id, payment_sequential)
);
CREATE TABLE IF NOT EXISTS order_reviews (
    review_id text NOT NULL,
    order_id text NOT NULL REFERENCES orders(order_id),
    review_score smallint,
    review_comment_title text,
    review_comment_message text,
    review_creation_date timestamp,
    review_answer_timestamp timestamp,
    PRIMARY KEY (review_id, order_id)
);
-- Geolocation has repeated zip prefixes; no false uniqueness constraint is imposed.
CREATE TABLE IF NOT EXISTS geolocation (
    geolocation_zip_code_prefix integer,
    geolocation_lat numeric(10, 7),
    geolocation_lng numeric(10, 7),
    geolocation_city text,
    geolocation_state char(2)
);

CREATE INDEX IF NOT EXISTS idx_orders_purchase_ts ON orders(order_purchase_timestamp);
CREATE INDEX IF NOT EXISTS idx_orders_customer ON orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product ON order_items(product_id);
CREATE INDEX IF NOT EXISTS idx_order_items_seller ON order_items(seller_id);
CREATE INDEX IF NOT EXISTS idx_reviews_order ON order_reviews(order_id);
