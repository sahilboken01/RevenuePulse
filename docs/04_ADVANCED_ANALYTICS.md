# Stage 4: Advanced business analytics

## Scope and assumptions

All SQL uses cleaned Stage 2 tables in `olist` and the delivered-order GMV definition from Stage 3: `SUM(order_items.price)`, excluding freight. No cost, profit, discount, or return values are introduced. The SQL transformations live in PostgreSQL; Python is used only for independent reference checks over cleaned CSVs because this workspace has no PostgreSQL client/server.

### RFM methodology

- **Analysis population:** customers with at least one delivered order.
- **Snapshot date:** one day after the latest delivered purchase timestamp in the data. For this extract, the snapshot is **2018-08-30**. It is derived from the dataset, not the machine's current date.
- **Recency:** days between the snapshot and the customer's latest delivered purchase.
- **Frequency:** distinct delivered orders for `customer_unique_id` through the snapshot.
- **Monetary:** sum of delivered item prices (GMV) for that customer through the snapshot.
- Each R, F, and M dimension receives a 1–5 quintile score. Low recency maps to a high R score; high frequency and GMV map to high F/M scores. Quintiles are recalculated for this dataset. Ties use `customer_unique_id` as a stable sort key and can be split across adjacent quintiles.
- Segment rules are evaluated in this order: Champions (R/F/M all at least 4); Cannot Lose Them (R 1–2, F 4–5); Loyal Customers (R 3–5, F 4–5); Potential Loyalists (R 4–5, F 2–3); New Customers (R 4–5, F 1); At Risk (R 1–2, F 3); Hibernating (R 1–2, F 1–2); Need Attention (R 3, F 2–5); Promising (remaining R 3/F 1 customers).

This is a retrospective segment snapshot at the end of the observed period. It must not be applied to an earlier date or interpreted as a prediction. Segment labels are business-friendly rules, not empirically validated treatment groups.

### Cohorts, value, and grain

- Cohorts are based on each stable customer ID's first **delivered** purchase month. A cohort-month cell counts customers with at least one delivered order in that month. The SQL generates zero-activity months as 0% rather than omitting them.
- Retention age 0 is 100% by definition. Later-month weighted retention includes only cohorts with that much follow-up before the dataset's last observed purchase month.
- One-time/repeat and average customer revenue use customer-level sums of order-level GMV. Repeat means two or more delivered orders in the observed period.
- Product quadrants compare category orders and average category spend per order against the medians across categories. This makes high volume distinct from high order value; category spend excludes other categories in the same order.
- Seller shares use active sellers with delivered GMV. Top 10/20 are deterministic ranks, with seller ID breaking exact GMV ties.
- Delivery/review analysis first averages source review records at order grain, then joins one row per order. The review comparison is **association, not causation**.

## Reference findings

The values below are reference calculations from the cleaned CSVs using the documented SQL definitions. RFM scores and segments were independently reproduced with the same quintile ordering/tie-break.

### RFM segment sizes

There are **93,358** delivered buyers at the 2018-08-30 snapshot.

| Segment | Customers | Customer share | GMV share |
|---|---:|---:|---:|
| Loyal Customers | 15,982 | 17.12% | 11.48% |
| Hibernating | 15,004 | 16.07% | 15.98% |
| Cannot Lose Them | 14,870 | 15.93% | 16.42% |
| Potential Loyalists | 14,956 | 16.02% | 15.94% |
| Champions | 6,490 | 6.95% | 13.46% |
| New Customers | 7,481 | 8.01% | 7.89% |
| At Risk | 7,468 | 8.00% | 7.86% |
| Need Attention | 7,389 | 7.91% | 7.27% |
| Promising | 3,718 | 3.98% | 3.72% |

### Cohort retention

The delivered-purchase cohorts cover **23 months**, September 2016–August 2018, and contain 93,358 customers. Weighted retention is:

| Months since first delivered purchase | Cohorts with full follow-up | Weighted retention |
|---:|---:|---:|
| 0 | 23 | 100.00% |
| 1 | 22 | 0.48% |
| 2 | 21 | 0.34% |
| 3 | 20 | 0.25% |
| 6 | 17 | 0.23% |
| 12 | 11 | 0.17% |

The denominator shrinks at longer ages because newer cohorts do not have a full year of follow-up. Retention is based on any delivered order during the age month, not continuous activity.

### Customer value

- One-time buyers: **90,557**; repeat buyers: **2,801**.
- Repeat buyers are **3.00%** of observed delivered buyers and contributed **5.51%** of delivered GMV.
- Average delivered GMV per buyer is **BRL 141.62** overall; **BRL 137.96** for one-time buyers and **BRL 260.05** for repeat buyers.

### Product economics

Across **74** categories, the median category order count is **241.5** and median category spend per order is **BRL 126.62**. The SQL classifies 20 categories as high-volume/high-value, 17 high-volume/lower-value, 17 lower-volume/high-value, and 20 lower-volume/lower-value.

Health/beauty and watches/gifts rank among the high-volume/high-value categories. Bed/bath/table has high order volume but category spend per order below the median (9,272 category orders; about BRL 110.38 per category order). Computers is lower-volume/high-value (177 category orders; about BRL 1,235.50 per category order), so the high average is based on much lower volume.

### Seller concentration

There are **2,970 active sellers** in delivered orders. The top 10 sellers contribute **13.27%** of GMV; top 20 contribute **21.28%**. Median seller GMV is **BRL 846.18**, compared with **BRL 9,494.31** at the 90th percentile, indicating a long right tail in seller GMV.

### Delivery and review association

Among **95,824** eligible delivered orders with review data, the order-level average review score is **4.29/5** for on-time deliveries and **2.57/5** for late deliveries. The delivery-days/review-score Pearson correlation is **−0.3343**. Average score also declines across delivery-time buckets: 4.48 for under 3 days, 4.40 for 3–6 days, 4.31 for 7–13 days, and 3.72 for 14+ days.

These are associations in observational data. The analysis does not isolate delivery as a cause; product issues, seller behavior, location, or customer mix may also affect both delivery time and reviews.

## Files and execution

Advanced queries are in `sql/analysis/08_rfm_segmentation.sql` through `13_delivery_review_impact.sql`. RFM and cohort outputs are reusable views under `analytics`; other files return analysis result sets. Run the Stage 4 analysis files after creating/loading the Stage 3 `olist` tables:

```powershell
psql -d revenuepulse -f sql/analysis/08_rfm_segmentation.sql
psql -d revenuepulse -f sql/analysis/09_customer_cohorts.sql
psql -d revenuepulse -f sql/analysis/10_customer_value.sql
psql -d revenuepulse -f sql/analysis/11_product_economics.sql
psql -d revenuepulse -f sql/analysis/12_seller_concentration.sql
psql -d revenuepulse -f sql/analysis/13_delivery_review_impact.sql
psql -d revenuepulse -f sql/validation/02_advanced_analytics_checks.sql
```

`sql/validation/02_advanced_analytics_checks.sql` checks one RFM row per customer, score ranges, GMV reconciliation, month-zero cohort retention and retention bounds, delivery population grain, product GMV reconciliation, and top-10/top-20 seller share ordering. `tests/test_stage4_reference_checks.py` independently checks reference customer counts, RFM segment sizes, customer/cohort behavior, GMV reconciliation, seller concentration, and the delivery/review join over cleaned CSVs.

## Limitations

- PostgreSQL was unavailable in the local workspace; the SQL views and SQL validation file have not been executed against a PostgreSQL server here. Run them in PostgreSQL to validate database-side execution.
- Olist has no cost/COGS, discount, or return fields, so actual profit, discount impact, and return rate remain out of scope.
- Repeat purchase, RFM, and cohorts are constrained by this short observed window. Recent cohorts are right-censored.
- Segment cutoffs are relative quintiles. Scores can shift when the dataset or snapshot changes.
- Some product categories are untranslated; the SQL keeps the source category label.
- Review scores and delivery times are associated, not causal.
