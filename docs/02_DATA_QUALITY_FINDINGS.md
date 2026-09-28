# Stage 2: Data acquisition and cleaning findings

## Acquisition

Downloaded the public [Olist Brazilian E-Commerce dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) archive. The original ZIP and its nine original CSVs are stored in `data/raw/`. Cleaning reads the CSVs and writes separate outputs to `data/processed/`; it does not edit the raw files.

## Source and cleaned row counts

| Table | Source rows | Cleaned rows | Exact duplicates removed |
|---|---:|---:|---:|
| customers | 99,441 | 99,441 | 0 |
| geolocation | 1,000,163 | 738,332 | 261,831 |
| order_items | 112,650 | 112,650 | 0 |
| order_payments | 103,886 | 103,886 | 0 |
| order_reviews | 99,224 | 99,224 | 0 |
| orders | 99,441 | 99,441 | 0 |
| products | 32,951 | 32,951 | 0 |
| sellers | 3,095 | 3,095 | 0 |
| category_translation | 71 | 71 | 0 |

The complete inspected schema (column names and cleaned pandas data types) and field-level quality counts are recorded in [`data_quality_report.json`](data_quality_report.json).

## Important findings

- **Missing values:** orders has 160 missing approval timestamps, 1,783 missing carrier-delivery timestamps, and 2,965 missing customer-delivery timestamps. Reviews has 87,656 missing review titles and 58,247 missing review messages. Products has 610 missing category/name-length/description-length/photo-count values and 2 missing values in each of weight, length, height, and width. These are retained as nulls.
- **Duplicates:** geolocation contains 261,831 exact duplicate rows. Those duplicates were removed from the processed copy. Other tables had no exact duplicate rows.
- **Date parsing:** no non-null date strings failed parsing. Chronology checks found 166 rows with carrier-delivery timestamps earlier than purchase and 23 rows with customer-delivery timestamps earlier than carrier delivery. These records are retained and flagged in the JSON report. The delivered-vs-estimated date can be late and is not treated as an invalid date.
- **Prices/freight/payments:** no invalid numeric strings or negative values were found in item price, freight, or payment value. The cleaner will set negative values to null if encountered on a future rerun, while retaining the row.
- **Foreign keys:** no orphan rows were found for order/customer, item/order, item/product, item/seller, payment/order, or review/order links. Thirteen product rows use two category labels without a translation entry (`pc_gamer`, `portateis_cozinha_e_preparadores_de_alimentos`). These categories are retained without an invented translation.
- **Statuses and categories:** eight distinct order statuses and five payment types occur in the source. Status and payment labels, and category mapping labels, are trimmed and lowercased. The observed values are listed in the JSON report for review; source statuses are kept rather than collapsed.
- **Business metric limitation:** there are no product cost, dedicated discount, or returns fields. No profit, discount, or return facts have been fabricated.

## Cleaning decisions

1. Remove exact duplicate rows in processed data only.
2. Parse known timestamp columns as datetimes; unparseable non-null strings become null and are counted.
3. Parse currency-like values as numeric; invalid or negative values become null and are counted. No data is imputed.
4. Trim and lowercase selected category/status/payment text fields.
5. Retain rows with missing keys or orphan foreign keys and report them, rather than silently deleting records.
6. Keep the original columns and use the original table filenames in processed CSVs.

## Reproduce

From the `RevenuePulse` project directory, with Python and pandas installed:

```powershell
python src/clean_data.py
python -m unittest discover -s tests -v
```

The script overwrites the processed CSV copies and refreshes `docs/data_quality_report.json` from the raw inputs.
