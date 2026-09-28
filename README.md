# RevenuePulse

E-commerce business intelligence project focused on the question: **We are selling more, but are we actually making more money?**

The project uses Python, PostgreSQL, SQL, Power BI, and Excel to analyze sales performance and customer behavior using a realistic, multi-table public dataset. Work will be built in stages so that each transformation and metric is understandable and reviewable.

## Stage 1: Dataset selection

### Selected dataset

[Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)

Olist is a Brazilian online marketplace. The public dataset contains approximately 100,000 orders from 2016–2018, represented by linked CSV tables. It is a good foundation for SQL practice because orders, line items, customers, products, sellers, payments, and reviews are separate entities that can be joined at their proper grain.

### Why it fits

- Multiple related tables support realistic relational modeling and SQL joins.
- Order and item timestamps allow monthly and category trend analysis.
- Customer identifiers and order histories support first-time/returning customer analysis and repeat purchase measurement.
- Item prices and freight values support sales and order-value analysis.
- Product categories and payment details enable useful business breakdowns.
- Its size is substantial enough to expose data-quality and aggregation-grain issues without requiring a large infrastructure setup.

### Data limitations to keep visible

The source has **no product cost / cost of goods sold (COGS)**, so revenue minus cost, gross profit, and profit margin cannot be calculated as factual results from Olist alone. It also has no dedicated discount or returns table. A payment value is not a discount field, and an order cancellation/status is not a complete returns record. We will not label revenue as profit or invent these fields. Before building profitability or discount-impact metrics in a later stage, we must either find a compatible cost/discount source or use an explicitly documented assumption-based scenario.

The source also has no customer names or detailed demographics; the customer attributes are primarily location fields. Product category names are available through a translation table.

## Source tables and key columns

The download is a collection of CSVs rather than a ready-made PostgreSQL database. Column names below are the source field names.

| Source table | Grain / role | Important columns |
|---|---|---|
| `olist_customers_dataset` | One customer record per order-facing customer ID | `customer_id`, `customer_unique_id`, `customer_zip_code_prefix`, `customer_city`, `customer_state` |
| `olist_orders_dataset` | One row per order | `order_id`, `customer_id`, `order_status`, `order_purchase_timestamp`, `order_approved_at`, `order_delivered_customer_date`, `order_estimated_delivery_date` |
| `olist_order_items_dataset` | One row per item/seller within an order | `order_id`, `order_item_id`, `product_id`, `seller_id`, `shipping_limit_date`, `price`, `freight_value` |
| `olist_products_dataset` | One row per product | `product_id`, `product_category_name`, `product_name_lenght`, `product_weight_g`, `product_length_cm`, `product_height_cm`, `product_width_cm` |
| `product_category_name_translation` | One row per Portuguese/English category mapping | `product_category_name`, `product_category_name_english` |
| `olist_order_payments_dataset` | One row per payment installment/payment method per order | `order_id`, `payment_sequential`, `payment_type`, `payment_installments`, `payment_value` |
| `olist_order_reviews_dataset` | One row per review record | `review_id`, `order_id`, `review_score`, `review_creation_date`, `review_answer_timestamp` |
| `olist_sellers_dataset` | One row per seller | `seller_id`, `seller_zip_code_prefix`, `seller_city`, `seller_state` |
| `olist_geolocation_dataset` | Many location rows per zip-code prefix | `geolocation_zip_code_prefix`, `geolocation_lat`, `geolocation_lng`, `geolocation_city`, `geolocation_state` |

Join paths and grain cautions to carry into the SQL stage:

- `orders.customer_id` → `customers.customer_id`; use `customer_unique_id` to recognize the same customer across order-facing IDs.
- `order_items.order_id` → `orders.order_id`; then `order_items.product_id` → `products.product_id`.
- `products.product_category_name` → `product_category_name_translation.product_category_name`.
- `order_payments.order_id` → `orders.order_id`, but an order can have multiple payment rows.
- `order_items` can have multiple rows per order; do not join item rows to payment rows and sum both without pre-aggregating to avoid duplicated totals.
- Geolocation may contain multiple rows for one zip prefix; it is optional for the business questions in this project.

## Business questions

The analysis will answer these questions when the relevant fields and definitions are available:

1. How are order value, item sales, freight, order count, and trend changing month to month?
2. Which products and product categories contribute the most item sales, and how concentrated are sales among them?
3. How do customer purchase patterns vary by geography and order history, within the limits of the available customer attributes?
4. What share of customers and orders are first-time versus repeat, and how does the repeat purchase rate change over time?
5. How do RFM segments compare by recency, purchase frequency, and monetary value?
6. Are sales increasing while validated profit or margin falls? This requires product cost/COGS data, which Olist does not provide.
7. What is the relationship between discounts and profit? This requires discount data and product cost/COGS; Olist does not provide either as dedicated fields.
8. How do payment methods, order status, reviews, and delivery outcomes relate to customer/order patterns?

The questions about actual profit and discount impact remain explicitly dependent on sourcing additional data; they are not answerable as factual Olist-only metrics.

## Planned project structure

```text
RevenuePulse/
├── data/
│   ├── raw/                 # Original downloaded source files (not committed)
│   └── processed/           # Cleaned/intermediate exports (not committed)
├── docs/                    # Data dictionary, metric definitions, decisions
├── excel/                   # Excel analysis artifacts (later stage)
├── powerbi/                 # Power BI model and report files (later stage)
├── sql/                     # PostgreSQL schema, cleaning, and analysis queries
├── src/                     # Small Python ingestion/validation utilities
├── .gitignore
└── README.md
```

## Dataset acquisition

Download the CSV archive from the [Olist Kaggle dataset page](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) and place the extracted original CSVs in `data/raw/`. Dataset access may require a Kaggle account and acceptance of the dataset terms. The raw files should remain unchanged; later stages can create processed copies and document cleaning decisions.

## Stage plan

- **Stage 1 — Dataset and project setup:** dataset selection, business scope, and folder scaffold. *(Complete.)*
- **Stage 2 — Data acquisition and cleaning:** download and preserve raw inputs, create standardized processed CSVs, and document quality checks. See [Stage 2 findings](docs/02_DATA_QUALITY_FINDINGS.md). *(Complete.)*
- **Stage 3 — SQL business analysis:** create PostgreSQL model/load scripts, grain-aware analysis by business area, and validation queries. See [Stage 3 SQL analysis](docs/03_SQL_ANALYSIS.md). *(Complete.)*
- **Stage 4 — Advanced business analytics:** add RFM segmentation, cohorts, customer value, product economics, seller concentration, and delivery/review association analysis. See [Stage 4 advanced analytics](docs/04_ADVANCED_ANALYTICS.md). *(Current stage.)*
- **Stage 5 — Power BI dashboard design:** prepare Power BI-ready CSVs and equivalent PostgreSQL views, a star-schema relationship guide, DAX measures, and four-page dashboard specification. See [Power BI handoff](powerbi/README.md). *(Complete; report assembly remains a Power BI Desktop step.)*
- **Stage 4 — Power BI and Excel:** build the agreed business-facing outputs from validated definitions.

No dashboard or machine-learning work is included in Stage 1.

### Rerun Stage 2 cleaning

From the project directory, install the dependency in `requirements.txt`, then run:

```powershell
python src/clean_data.py
python -m unittest discover -s tests -v
```
