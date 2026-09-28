# Power BI model and relationship guide

## Import and rename tables

In Power BI Desktop, use **Get Data → Text/CSV** and import every CSV in `powerbi/data/`. Rename the imported tables as follows; keep the snake_case column names so the supplied DAX can be pasted unchanged.

| CSV | Power BI table |
|---|---|
| `dim_date.csv` | `DimDate` |
| `dim_customer.csv` | `DimCustomer` |
| `dim_category.csv` | `DimCategory` |
| `dim_product.csv` | `DimProduct` |
| `dim_seller.csv` | `DimSeller` |
| `dim_geography.csv` | `DimGeography` |
| `fact_order.csv` | `FactOrder` |
| `fact_sales_item.csv` | `FactSalesItem` |
| `fact_category_economics.csv` | `FactCategoryEconomics` |
| `fact_seller_performance.csv` | `FactSellerPerformance` |
| `fact_cohort_retention.csv` | `FactCohortRetention` |
| `fact_order_category_delivery.csv` | `FactOrderCategoryDelivery` |

Set ID/state/category columns to Text; all date keys to Date; GMV/price to Fixed Decimal or Decimal Number; score and count fields to Whole Number; `retention_rate` and seller shares to Percentage. Mark `DimDate` as the date table using `DimDate[date]`. Sort `DimDate[month_name]` by `month_number`, `DimDate[year_month]` by `month_start`, and `FactOrder[delivery_time_bucket]` by `delivery_bucket_order`.

## Relationships

Create one-to-many relationships, with single-direction filtering from dimension to fact. Do not create relationships between fact tables.

| One side | Many side | Meaning |
|---|---|---|
| `DimDate[date]` | `FactOrder[purchase_date]` | Order purchase date |
| `DimDate[date]` | `FactSalesItem[purchase_date]` | Item's order purchase date |
| `DimDate[date]` | `FactCategoryEconomics[purchase_month]` | Monthly category summary |
| `DimDate[date]` | `FactOrderCategoryDelivery[purchase_date]` | Order-category purchase date |
| `DimCustomer[customer_unique_id]` | `FactOrder[customer_unique_id]` | Unique buyer at order grain |
| `DimCustomer[customer_unique_id]` | `FactSalesItem[customer_unique_id]` | Unique buyer at item grain |
| `DimCategory[category_key]` | `FactSalesItem[category_key]` | Product category on each item |
| `DimProduct[product_id]` | `FactSalesItem[product_id]` | Product on each item |
| `DimCategory[category_key]` | `FactCategoryEconomics[category_key]` | Category summary |
| `DimCategory[category_key]` | `FactOrderCategoryDelivery[category_key]` | Category/order delivery pairs |
| `DimSeller[seller_id]` | `FactSalesItem[seller_id]` | Seller on each item |
| `DimSeller[seller_id]` | `FactSellerPerformance[seller_id]` | One active seller summary row |
| `DimGeography[state_code]` | `FactOrder[state_code]` | Buyer state at order grain |
| `DimGeography[state_code]` | `FactSalesItem[state_code]` | Buyer state at item grain |
| `DimGeography[state_code]` | `FactOrderCategoryDelivery[state_code]` | Buyer state at order-category grain |
Keep `DimCustomer[cohort_month]` as a descriptive field and do not relate it to `DimDate`. Use `FactCohortRetention[cohort_month]` directly in the cohort matrix without a date-dimension relationship. This avoids a second path between date and order facts. RFM and purchase type describe the entire observed period; they are not recalculated by a purchase-date slicer. Avoid a synced purchase-date slicer on the Customer Intelligence page.

## Grain and measure cautions

- `FactOrder` has one row per delivered order and is the source for total GMV, delivered orders, AOV, active buyers, customer revenue, and overall delivery/review KPIs.
- `FactSalesItem` has one row per delivered item and is the source for category and seller item GMV. Use `DISTINCTCOUNT(FactSalesItem[order_id])` for category order volume.
- `DimProduct` has one row per catalog product and supplies product IDs for item-level drilldown; use `DimCategory` for category-level filtering.
- `FactCategoryEconomics` has one row per category/month. It carries monthly category GMV/order/item metrics and the Stage 4 full-period category quadrant for a date-responsive scatter visual. Quadrant labels stay fixed to the full-period median benchmark when a month is selected.
- `FactSellerPerformance` has one row per seller with delivered GMV; it supports seller concentration and the histogram. The detailed seller GMV chart may use `FactSalesItem`.
- `FactOrderCategoryDelivery` has one row per order/category pair, so an order with multiple categories appears more than once. Use distinct order counts and label the metrics as order-category performance.
- Never add `FactOrder[order_gmv]` to a visual grouped by category or seller. Use `FactSalesItem[item_price]` there. Never join payment rows into either GMV fact.
- `FactCohortRetention` is already aggregated by cohort and month index. Use its `retention_rate` at the cohort/month-index cell level; turn matrix totals off.
