# RevenuePulse Power BI dashboard specification

## Global presentation

- 16:9 report canvas, clean white/light background, navy text, teal for GMV/customer metrics, amber for late delivery, muted gray for context.
- Page titles include **Brazilian E-commerce | Olist | Sep 2016–Aug 2018**. Add a note that September 2016 and August 2018 are partial purchase months.
- Currency is BRL. Use **GMV** in every revenue title/measure; do not label it profit or net revenue.
- Keep each page to its requested visuals, align cards and charts to a grid, and use concise subtitles to explain metric grain.
- Use the supplied measures in [`measures.dax`](measures.dax) and relationships in [`model_relationships.md`](model_relationships.md).

## Page 1 — Executive Overview

**Slicers:** purchase year-month (`DimDate[year_month]`) and buyer state (`DimGeography[state_code]`). Apply them to this page only.

| Visual type | Fields / measure | Purpose |
|---|---|---|
| Four KPI cards | Total GMV (BRL), Delivered Orders, Average Order Value (BRL), Active Buyers | Immediate scale and order economics |
| Line chart | X: `DimDate[month_start]`; Y: Total GMV (BRL) | Monthly delivered GMV trend |
| Horizontal bar chart | Category; Category GMV (BRL); Top N 10 | Main product-category contributors |
| Horizontal bar chart | Buyer state; Total GMV (BRL); Top N 10 | Geographic GMV concentration |
| Text insight card | Peak month and values sourced from the analysis; explicit “GMV is not profit” note | Business context without adding a new metric |

Suggested text insight: “November 2017 was the highest-GMV month in the observed period. Olist provides no product cost data, so GMV does not establish profitability.”

## Page 2 — Customer Intelligence

**Slicers:** RFM segment and cohort month. Do not sync the purchase-date slicer here: RFM and one-time/repeat classifications are full-period observed values, while the cohort matrix uses cohort month and cohort age.

| Visual type | Fields / measure | Purpose |
|---|---|---|
| KPI cards | Observed Repeat Purchase Rate, One-time Buyers, Repeat Buyers | Customer mix and repeat rate over the full observed period |
| Donut chart | `DimCustomer[purchase_type]`; distinct customers | One-time vs repeat customer mix |
| Horizontal bar chart | RFM segment; RFM Segment Customers | Segment distribution |
| Horizontal bar chart | RFM segment; GMV by RFM Segment (BRL) | Full-period customer GMV contribution by segment |
| Matrix heatmap | Rows: `FactCohortRetention[cohort_month]`; columns: `month_index`; value: Cohort Retention Rate | Retention by cohort age; disable row/column totals |
| Clustered column chart | `DimCustomer[purchase_type]`; Average Revenue per Customer (BRL) | One-time vs repeat customer value comparison |

Add a subtitle to RFM visuals showing the snapshot date (2018-08-30). Cohort retention cells are distinct active buyers divided by cohort size; later ages have fewer eligible cohorts.

## Page 3 — Product & Seller Performance

**Slicers:** purchase year-month, category, seller state.

| Visual type | Fields / measure | Purpose |
|---|---|---|
| Scatter chart | X: Category Orders (Economics); Y: Category GMV (Economics, BRL); size: Average Category Order Value (Economics, BRL); details: category; legend: category quadrant | Existing Stage 4 volume/value quadrants; quadrant labels use full-period medians |
| Horizontal bar chart | Category; Category GMV (BRL); Top N 10 | Category GMV ranking |
| Horizontal bar chart | Seller; Item GMV (BRL); Top N 10 | Leading sellers |
| Column histogram | `FactSellerPerformance[seller_gmv]` grouped into Power BI bins; count sellers | Distribution of active-seller GMV |
| KPI cards | Top 10 Seller GMV Share, Top 20 Seller GMV Share, Active Sellers | Seller concentration |

Scatter subtitle: category orders are distinct orders containing the category; category order value is that category's GMV divided by those orders. Quadrant labels are fixed from full-period medians; plotted values respond to the selected period. Seller GMV is item price and excludes freight. Label the seller histogram as full-period because its bins show the Stage 4 full-period active-seller distribution.

## Page 4 — Delivery & Customer Experience

**Slicers:** purchase year-month and buyer state. If adding category, set its visual interaction to the category/state matrix only; the order-level delivery cards and on-time/late score comparison do not have category grain.

| Visual type | Fields / measure | Purpose |
|---|---|---|
| KPI cards | Average Delivery Days, Late Delivery Rate | Delivery baseline; late-rate denominator includes orders with both actual and estimated delivery dates |
| Clustered column chart | `FactOrder[delivery_status]` (on time/late); Average Order Review Score | Compare order-level average review scores |
| Line chart | `FactOrder[delivery_time_bucket]` sorted by bucket order; Average Review Score by Delivery Bucket | Score pattern across delivery-time groups |
| Matrix heatmap | Rows: category; columns: buyer state; value: Late Delivery Rate by Category or State (or Average Delivery Days by Category) | Delivery performance across category/state order-category pairs |

Place “Association only; this view does not establish that delivery time causes review scores” directly below the line chart. Missing estimate/delivery-date records should not be shown as on-time or late.
