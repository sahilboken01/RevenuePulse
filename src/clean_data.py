"""Reproducible, conservative cleaning for the Olist source CSVs."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import pandas as pd


TABLE_FILES = {
    "customers": "olist_customers_dataset.csv",
    "geolocation": "olist_geolocation_dataset.csv",
    "order_items": "olist_order_items_dataset.csv",
    "order_payments": "olist_order_payments_dataset.csv",
    "order_reviews": "olist_order_reviews_dataset.csv",
    "orders": "olist_orders_dataset.csv",
    "products": "olist_products_dataset.csv",
    "sellers": "olist_sellers_dataset.csv",
    "category_translation": "product_category_name_translation.csv",
}

DATE_COLUMNS = {
    "orders": ["order_purchase_timestamp", "order_approved_at", "order_delivered_carrier_date",
               "order_delivered_customer_date", "order_estimated_delivery_date"],
    "order_items": ["shipping_limit_date"],
    "order_reviews": ["review_creation_date", "review_answer_timestamp"],
}
CURRENCY_COLUMNS = {
    "order_items": ["price", "freight_value"],
    "order_payments": ["payment_value"],
}
TEXT_NORMALIZE = {
    "orders": ["order_status"],
    "order_payments": ["payment_type"],
    "products": ["product_category_name"],
    "category_translation": ["product_category_name", "product_category_name_english"],
}
FOREIGN_KEYS = {
    "orders.customer_id": ("orders", "customer_id", "customers", "customer_id"),
    "order_items.order_id": ("order_items", "order_id", "orders", "order_id"),
    "order_items.product_id": ("order_items", "product_id", "products", "product_id"),
    "order_items.seller_id": ("order_items", "seller_id", "sellers", "seller_id"),
    "order_payments.order_id": ("order_payments", "order_id", "orders", "order_id"),
    "order_reviews.order_id": ("order_reviews", "order_id", "orders", "order_id"),
    "products.product_category_name": ("products", "product_category_name", "category_translation", "product_category_name"),
}


def clean_table(name: str, frame: pd.DataFrame) -> tuple[pd.DataFrame, dict[str, Any]]:
    """Clean one table without inventing values or discarding orphan records."""
    result = frame.copy()
    result.columns = [column.strip().lower() for column in result.columns]
    before_rows = len(result)
    exact_duplicates = int(result.duplicated().sum())
    result = result.drop_duplicates().copy()

    missing_before = {column: int(count) for column, count in result.isna().sum().items() if count}
    invalid_dates: dict[str, int] = {}
    for column in DATE_COLUMNS.get(name, []):
        if column in result:
            parsed = pd.to_datetime(result[column], errors="coerce")
            invalid_dates[column] = int((result[column].notna() & parsed.isna()).sum())
            result[column] = parsed

    invalid_numeric: dict[str, int] = {}
    negative_currency: dict[str, int] = {}
    for column in CURRENCY_COLUMNS.get(name, []):
        if column in result:
            numeric = pd.to_numeric(result[column], errors="coerce")
            invalid_numeric[column] = int((result[column].notna() & numeric.isna()).sum())
            negative_currency[column] = int((numeric < 0).sum())
            result[column] = numeric.mask(numeric < 0)

    normalized_text: dict[str, int] = {}
    for column in TEXT_NORMALIZE.get(name, []):
        if column in result:
            normalized = result[column].map(
                lambda value: value.strip().lower() if isinstance(value, str) else value
            )
            normalized_text[column] = int((result[column].fillna("\0") != normalized.fillna("\0")).sum())
            result[column] = normalized

    report: dict[str, Any] = {
        "source_file": TABLE_FILES[name],
        "rows_before": before_rows,
        "rows_after": len(result),
        "exact_duplicate_rows_removed": exact_duplicates,
        "columns": {column: str(dtype) for column, dtype in result.dtypes.items()},
        "missing_values_after_deduplication": missing_before,
        "invalid_dates_set_null": invalid_dates,
        "invalid_numeric_values_set_null": invalid_numeric,
        "negative_currency_values_set_null": negative_currency,
        "text_values_normalized": normalized_text,
    }
    return result, report


def load_source_tables(raw_dir: Path) -> dict[str, pd.DataFrame]:
    return {name: pd.read_csv(raw_dir / filename) for name, filename in TABLE_FILES.items()}


def build_report(tables: dict[str, pd.DataFrame], reports: dict[str, dict[str, Any]]) -> dict[str, Any]:
    orphan_counts: dict[str, int] = {}
    for label, (child_table, child_col, parent_table, parent_col) in FOREIGN_KEYS.items():
        child = tables[child_table][child_col]
        parent_keys = set(tables[parent_table][parent_col].dropna())
        orphan_counts[label] = int((child.notna() & ~child.isin(parent_keys)).sum())

    statuses = sorted(tables["orders"]["order_status"].dropna().unique().tolist())
    payment_types = sorted(tables["order_payments"]["payment_type"].dropna().unique().tolist())
    categories = tables["products"]["product_category_name"]
    translated = set(tables["category_translation"]["product_category_name"].dropna())
    unmapped_categories = sorted(set(categories.dropna()) - translated)
    orders = tables["orders"]
    chronology_checks = {
        "approval_before_purchase": ("order_approved_at", "order_purchase_timestamp"),
        "carrier_delivery_before_purchase": ("order_delivered_carrier_date", "order_purchase_timestamp"),
        "customer_delivery_before_carrier_delivery": ("order_delivered_customer_date", "order_delivered_carrier_date"),
        "customer_delivery_before_purchase": ("order_delivered_customer_date", "order_purchase_timestamp"),
    }
    chronology_violations = {}
    for label, (earlier_col, later_col) in chronology_checks.items():
        earlier = pd.to_datetime(orders[earlier_col], errors="coerce")
        later = pd.to_datetime(orders[later_col], errors="coerce")
        chronology_violations[label] = int((earlier.notna() & later.notna() & (earlier < later)).sum())
    return {
        "dataset": "Brazilian E-Commerce Public Dataset by Olist",
        "table_reports": reports,
        "foreign_key_orphan_rows": orphan_counts,
        "distinct_order_statuses": statuses,
        "distinct_payment_types": payment_types,
        "product_categories_without_translation": unmapped_categories,
        "order_date_chronology_violations": chronology_violations,
        "notes": [
            "Missing values are reported, not imputed.",
            "Orphan foreign keys are reported; rows are retained.",
            "Negative item price/freight/payment values are set to null; rows are retained.",
            "No profit, cost, discount, or return values are created.",
        ],
    }


def clean_dataset(raw_dir: Path, processed_dir: Path, report_path: Path) -> dict[str, Any]:
    raw_tables = load_source_tables(raw_dir)
    cleaned_tables: dict[str, pd.DataFrame] = {}
    table_reports: dict[str, dict[str, Any]] = {}
    for name, frame in raw_tables.items():
        cleaned, table_report = clean_table(name, frame)
        cleaned_tables[name] = cleaned
        table_reports[name] = table_report
        cleaned.to_csv(processed_dir / TABLE_FILES[name], index=False)

    quality_report = build_report(cleaned_tables, table_reports)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(quality_report, indent=2, default=str), encoding="utf-8")
    return quality_report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw-dir", type=Path, default=Path("data/raw"))
    parser.add_argument("--processed-dir", type=Path, default=Path("data/processed"))
    parser.add_argument("--report", type=Path, default=Path("docs/data_quality_report.json"))
    args = parser.parse_args()
    report = clean_dataset(args.raw_dir, args.processed_dir, args.report)
    for name, details in report["table_reports"].items():
        print(f"{name}: {details['rows_before']:,} source rows -> {details['rows_after']:,} cleaned rows")
    print(f"Quality report: {args.report}")


if __name__ == "__main__":
    main()
