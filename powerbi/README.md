# Power BI handoff

The provided import files, semantic model instructions, DAX, and page specification form the Power BI handoff. Power BI Desktop is not part of this workspace workflow, so no `.pbix` file is included.

## Rebuild the CSVs

From the RevenuePulse project directory, after Stage 2 cleaning has populated `data/processed/`:

```powershell
python src/export_powerbi_data.py
```

This writes twelve Power BI-ready CSVs under `powerbi/data/`. It reads only cleaned Stage 2 files, includes delivered GMV, and creates no profit/cost/discount/return fields. The script is deterministic and uses merge validation for key joins.

The PostgreSQL alternative creates equivalent views and exports them with psql:

```powershell
psql -d revenuepulse -f sql/analysis/08_rfm_segmentation.sql
psql -d revenuepulse -f sql/analysis/09_customer_cohorts.sql
psql -d revenuepulse -f sql/powerbi/01_powerbi_views.sql
psql -d revenuepulse -f sql/powerbi/02_export_csvs.sql
```

## Build the report

1. Import every CSV from `powerbi/data/` and rename tables per [model_relationships.md](model_relationships.md).
2. Set the column data types and create only the single-direction, one-to-many relationships listed there.
3. Mark `DimDate` as the date table and set sort-by columns for month and delivery bucket labels.
4. Create the measures in [measures.dax](measures.dax), using the [measure guide](dax_measure_guide.md) for interpretation and formatting.
5. Build the four pages using the exact visuals and filter guidance in [dashboard_specification.md](dashboard_specification.md).
6. Add a report subtitle/footer stating **Olist purchase period: Sep 2016–Aug 2018 (boundary months partial)**.

## Export grain

| CSV | Rows | Grain |
|---|---:|---|
| `dim_date.csv` | 730 | Calendar day across period boundary months |
| `dim_customer.csv` | 93,358 | One observed delivered buyer (`customer_unique_id`) |
| `dim_category.csv` | 74 | One category label |
| `dim_product.csv` | 32,951 | One catalog product ID with category key |
| `dim_seller.csv` | 2,970 | One seller with delivered GMV |
| `dim_geography.csv` | 27 | One buyer state code |
| `fact_order.csv` | 96,478 | One delivered order |
| `fact_sales_item.csv` | 110,197 | One delivered order item |
| `fact_category_economics.csv` | 1,273 | One category and purchase month summary; quadrant is classified using full-period medians |
| `fact_seller_performance.csv` | 2,970 | One active seller summary (Stage 4 concentration metrics) |
| `fact_cohort_retention.csv` | 278 | One cohort month and month age; includes 0-activity cells |
| `fact_order_category_delivery.csv` | 97,268 | One delivered order/category pair with a delivery date |

The order, item, seller, and category facts are separate on purpose. Use order GMV for executive/customer/delivery totals and item price for category/seller totals; never sum order GMV after joining it to item or category rows.
