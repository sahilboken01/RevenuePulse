# Stage 3: SQL business analysis

## Model and safe grains

The SQL targets the cleaned Stage 2 CSVs loaded into a PostgreSQL `olist` schema. Table definitions preserve source field names. `orders` is one row per order; `order_items` is one row per item in an order; payments are one or more rows per order; reviews are one row per `(review_id, order_id)` pair. `review_id` alone is not unique: 789 review IDs are associated with multiple orders. Geolocation has multiple rows for a zip prefix and is not joined into the business queries.

Revenue is defined as **merchandise GMV = SUM(order_items.price)**, excluding freight. Sales and AOV queries include delivered orders only. Order items are first summed to order grain before order-level counts, customer/state rollups, or monthly AOVs. Payments are deliberately not joined to items: multiple payment rows and multiple item rows would multiply values. Seller and category metrics use line-item value because every item has one seller and one product. These are GMV/order-value metrics, not profit.

Other definitions:

- **AOV:** delivered item GMV divided by delivered order count.
- **New/returning orders:** first vs later delivered order for a `customer_unique_id`, ordered by purchase timestamp and then order ID. This is first observed delivered order in this dataset.
- **Repeat purchase rate:** observed buyers with at least two delivered orders divided by all observed buyers. It is not a future-retention or customer-lifetime rate.
- **Category AOV:** category item GMV divided by distinct delivered orders containing that category. A multi-category order contributes separate category spend to each category.
- **Late delivery rate:** delivered orders with delivery and estimated-delivery dates, where actual delivery is later than estimated; missing estimates are excluded from the denominator.
- **Category review score:** each review/order record contributes once for each category in that order.

## Reference results from the cleaned data

These numbers were calculated independently from the Stage 2 processed CSVs using the definitions above. They are reference values for comparison after loading and running the PostgreSQL queries.

- Delivered orders: **96,478**; merchandise GMV: **BRL 13,221,498.11**; AOV: **BRL 137.04**.
- The data covers purchase dates from **September 2016 through August 2018**. November 2017 is the highest-GMV month at **BRL 987,765.37**. The first and last months are partial coverage and should not be compared as full months.
- Highest GMV categories: health/beauty (**BRL 1,233,131.72**), watches/gifts (**BRL 1,166,176.98**), and bed/bath/table (**BRL 1,023,434.76**). Bed/bath/table has the most delivered orders containing the category (**9,272**).
- Observed delivered buyers: **93,358**; repeat buyers: **2,801**; repeat purchase rate: **3.00%**; mean delivered orders per buyer: **1.033**. Customer GMV median is **BRL 89.73**, versus **BRL 279.99** at the 90th percentile.
- São Paulo leads buyer-state GMV (**BRL 5,067,633.16** across **40,501** delivered orders), followed by Rio de Janeiro and Minas Gerais.
- The ten largest sellers account for **13.27%** of seller GMV. The largest seller has **BRL 226,987.93** GMV.
- Average elapsed delivery time is **12.56 days**. There are **7,826** late orders among **96,470** delivered orders with both actual and estimated delivery dates (**8.11%**).
- Average source review score is **4.09 / 5** across **99,224 review/order records**.

These are descriptive results from historical data, not causal conclusions. In particular, they do not show whether revenue growth created profit.

## Run in PostgreSQL

From the RevenuePulse project directory, create/connect to a PostgreSQL database, then run:

```powershell
psql -d revenuepulse -f sql/00_schema.sql
psql -d revenuepulse -f sql/01_load_cleaned.sql
psql -d revenuepulse -f sql/validation/01_metric_checks.sql
```

Then run each SQL file in `sql/analysis/` for its business area. The load script uses psql `\copy` and reads only `data/processed/`.

## Query guide

| File | Main outputs | Main grain |
|---|---|---|
| `analysis/01_revenue.sql` | Delivered GMV, AOV, monthly GMV and orders | Order, then month |
| `analysis/02_product.sql` | Category GMV, distinct category orders, category AOV and ranks | Category/order, then category |
| `analysis/03_customer.sql` | New/returning order cohorts, repeat rate, orders/customer, GMV quintiles | Order, then unique customer |
| `analysis/04_geography.sql` | Buyer state GMV, orders, AOV | Order, then buyer state |
| `analysis/05_seller.sql` | Seller GMV/orders and cumulative / top-10 concentration | Seller item contributions, then seller |
| `analysis/06_delivery.sql` | Delivery days and late rates overall, by category, and by buyer state | Order or order/category, then segment |
| `analysis/07_customer_experience.sql` | Average review score, score by delivery-time bucket and category | Review/order record; category/review |

## Validation and execution status

`sql/validation/01_metric_checks.sql` checks unique order and order-item keys, review/order key uniqueness, orphan item relationships, negative item values, and GMV reconciliation between order, month, category, and seller aggregations. Each check should return zero violations or zero reconciliation difference.

The cleaned-data formulas were cross-checked for GMV/AOV, monthly GMV, repeat-buyer counts, seller concentration, and late-delivery denominator. The local workspace has no `psql` client or PostgreSQL server, so PostgreSQL loading and execution of the SQL files could not be run here. The scripts are ready to run against a local PostgreSQL instance using the commands above.

## Limitations

- No cost/COGS, dedicated discount, or returns fields are present; no profit, margin, discount impact, or return rate can be calculated.
- Customer identifiers and attributes are limited; `customer_unique_id` is the best available stable grouping key.
- Results describe observed 2016–2018 records only. Repeat rate is limited by this observation window.
- Delivery quality is measured only for delivered orders with the needed dates. Rows with chronology anomalies retained in Stage 2 are not silently removed.
- Product categories use the provided English mapping when available; two source category labels remain untranslated and are shown using their source names.
