# DAX measure notes

Create the expressions from [`measures.dax`](measures.dax) as measures. Suggested display formats are BRL with two decimals for amounts, percentage for rates/shares, one decimal for review scores and delivery days, and whole numbers for counts.

## Executive and customers

- **Total GMV (BRL):** sums delivered order-level GMV from `FactOrder`; it is item price and excludes freight.
- **Delivered Orders:** distinct delivered order IDs at order grain.
- **Average Order Value (BRL):** Total GMV divided by delivered orders. It is an order average, not profit per order.
- **Active Buyers:** distinct customers with delivered orders in the current purchase-date/state context.
- **Observed Repeat Purchase Rate:** repeat buyers divided by all buyers across the full observed dataset. It intentionally ignores current customer-dimension selections and is not a month-specific retention rate.
- **One-time Buyers / Repeat Buyers:** customer counts from the full-period delivered-order frequency in `DimCustomer`.
- **New Customer Orders / Returning Customer Orders:** counts orders by first vs subsequent delivered order for each customer in observed purchase history.
- **Average Revenue per Customer (BRL):** GMV divided by distinct buyers in the current filter context; on Page 2 the purchase type field compares one-time and repeat buyers.
- **RFM Segment Customers / GMV by RFM Segment:** segment size comes from the customer dimension; segment GMV filters order GMV through the customer relationship. RFM labels are full-period snapshot labels.

## Product and seller

- **Category GMV (BRL):** sum of delivered item prices in `FactSalesItem`; category filtering comes from `DimCategory`.
- **Category Orders:** distinct order IDs containing that category; do not count item rows as orders.
- **Average Category Spend per Order:** category GMV divided by category order count. Multi-category orders can contribute to more than one category.
- **Average Item Value:** item GMV divided by item rows, which matches the line-item grain.
- **Economics measures:** use the monthly `FactCategoryEconomics` summary. Category quadrant labels use full-period medians, while the values respond to the purchase-month filter.
- **Top 10/Top 20 Seller GMV Shares:** `TOPN` ranks sellers by item GMV under the selected date/state/category context, then divides the leading sellers' GMV by total seller GMV in that context.
- **Active Sellers:** distinct sellers with delivered item GMV under the current context.

## Delivery and cohorts

- **Average Delivery Days:** average purchase-to-customer-delivery duration at order grain; missing delivery dates are naturally excluded by `AVERAGE`.
- **Late Delivery Rate:** late delivered orders divided by orders that have both actual and estimated dates. Missing dates are excluded, not classified as on-time.
- **Average Order Review Score:** average of review scores first averaged within order, avoiding multiple review records multiplying the order.
- **Average Delivery Days by Category / Late Delivery Rate by Category or State:** derived from one row per order/category pair. Distinct order counts are used because a multi-category order appears once in each of its categories.
- **Cohort Retention Rate:** maximum retention value at a single cohort-month/month-index matrix cell. Disable matrix totals; the stored value already divides active buyers by the cohort size.
