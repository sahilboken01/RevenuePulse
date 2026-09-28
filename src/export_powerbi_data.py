"""Build Power BI star-schema CSVs from Stage 2 cleaned Olist CSVs only."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data" / "processed"
OUTPUT = ROOT / "powerbi" / "data"
CSV_DATE_FORMAT = "%Y-%m-%d %H:%M:%S"


def read_sources() -> dict[str, pd.DataFrame]:
    return {
        "orders": pd.read_csv(
            SOURCE / "olist_orders_dataset.csv",
            parse_dates=[
                "order_purchase_timestamp", "order_delivered_customer_date",
                "order_estimated_delivery_date",
            ],
        ),
        "items": pd.read_csv(SOURCE / "olist_order_items_dataset.csv"),
        "customers": pd.read_csv(SOURCE / "olist_customers_dataset.csv"),
        "products": pd.read_csv(SOURCE / "olist_products_dataset.csv"),
        "translations": pd.read_csv(SOURCE / "product_category_name_translation.csv"),
        "sellers": pd.read_csv(SOURCE / "olist_sellers_dataset.csv"),
        "reviews": pd.read_csv(SOURCE / "olist_order_reviews_dataset.csv"),
    }


def ntile_scores(frame: pd.DataFrame, value_column: str, *, reverse: bool = False) -> pd.Series:
    """Match PostgreSQL NTILE(5), with customer ID as deterministic tie-breaker."""
    count = len(frame)
    quotient, remainder = divmod(count, 5)
    first_bucket_rows = (quotient + 1) * remainder
    ordered = frame.sort_values([value_column, "customer_unique_id"], kind="mergesort")
    row_number = np.arange(1, count + 1)
    tiles = np.where(
        row_number <= first_bucket_rows,
        np.ceil(row_number / (quotient + 1)),
        remainder + np.ceil((row_number - first_bucket_rows) / quotient),
    ).astype(int)
    scores = pd.Series(tiles, index=ordered.index).reindex(frame.index)
    return 6 - scores if reverse else scores


def rfm_segment(recency: int, frequency: int, monetary: int) -> str:
    if recency >= 4 and frequency >= 4 and monetary >= 4:
        return "Champions"
    if recency <= 2 and frequency >= 4:
        return "Cannot Lose Them"
    if recency >= 3 and frequency >= 4:
        return "Loyal Customers"
    if recency >= 4 and frequency in (2, 3):
        return "Potential Loyalists"
    if recency >= 4 and frequency == 1:
        return "New Customers"
    if recency <= 2 and frequency == 3:
        return "At Risk"
    if recency <= 2 and frequency <= 2:
        return "Hibernating"
    if recency == 3 and frequency >= 2:
        return "Need Attention"
    return "Promising"


def create_exports(tables: dict[str, pd.DataFrame]) -> dict[str, pd.DataFrame]:
    orders = tables["orders"].loc[tables["orders"].order_status.eq("delivered")].copy()
    customers = tables["customers"]
    customer_lookup = customers[["customer_id", "customer_unique_id", "customer_state"]]
    items = tables["items"]
    products = tables["products"]
    translations = tables["translations"]

    order_gmv = (
        orders[["order_id", "customer_id", "order_purchase_timestamp"]]
        .merge(items[["order_id", "price"]], on="order_id", validate="one_to_many")
        .groupby(["order_id", "customer_id", "order_purchase_timestamp"], as_index=False)
        .price.sum()
        .rename(columns={"price": "order_gmv"})
    )
    customer_orders = order_gmv.merge(
        customer_lookup, on="customer_id", validate="many_to_one"
    )
    customer_orders["purchase_month"] = (
        customer_orders.order_purchase_timestamp.dt.to_period("M").dt.to_timestamp()
    )

    snapshot_date = order_gmv.order_purchase_timestamp.max().normalize() + pd.Timedelta(days=1)
    rfm = customer_orders.groupby("customer_unique_id").agg(
        last_purchase=("order_purchase_timestamp", "max"),
        frequency_orders=("order_id", "nunique"),
        monetary_gmv=("order_gmv", "sum"),
    ).reset_index()
    rfm["snapshot_date"] = snapshot_date
    rfm["recency_days"] = (snapshot_date - rfm.last_purchase.dt.normalize()).dt.days
    rfm["recency_score"] = ntile_scores(rfm, "recency_days", reverse=True)
    rfm["frequency_score"] = ntile_scores(rfm, "frequency_orders")
    rfm["monetary_score"] = ntile_scores(rfm, "monetary_gmv")
    rfm["customer_segment"] = [
        rfm_segment(r, f, m)
        for r, f, m in zip(rfm.recency_score, rfm.frequency_score, rfm.monetary_score)
    ]
    first_purchase = customer_orders.groupby("customer_unique_id").purchase_month.min()
    rfm["cohort_month"] = rfm.customer_unique_id.map(first_purchase)
    rfm["purchase_type"] = np.where(rfm.frequency_orders.eq(1), "one-time", "repeat")
    dim_customer = rfm.drop(columns="last_purchase")

    ranked_orders = customer_orders.sort_values(
        ["customer_unique_id", "order_purchase_timestamp", "order_id"], kind="mergesort"
    ).copy()
    ranked_orders["customer_order_number"] = ranked_orders.groupby("customer_unique_id").cumcount() + 1
    ranked_orders["customer_order_type"] = np.where(
        ranked_orders.customer_order_number.eq(1), "new customer order", "returning customer order"
    )

    delivery_fields = orders[[
        "order_id", "order_purchase_timestamp", "order_delivered_customer_date",
        "order_estimated_delivery_date",
    ]].copy()
    delivery_fields["delivery_days"] = (
        delivery_fields.order_delivered_customer_date - delivery_fields.order_purchase_timestamp
    ).dt.total_seconds() / 86_400
    actual = delivery_fields.order_delivered_customer_date
    estimated = delivery_fields.order_estimated_delivery_date
    delivery_fields["late_flag"] = pd.Series(pd.NA, index=delivery_fields.index, dtype="Int64")
    eligible = actual.notna() & estimated.notna()
    delivery_fields.loc[eligible, "late_flag"] = (actual[eligible] > estimated[eligible]).astype("int64")
    delivery_fields["delivery_status"] = np.select(
        [actual.isna(), estimated.isna(), actual.gt(estimated)],
        ["missing delivery date", "missing estimate", "late"],
        default="on time",
    )

    order_reviews = tables["reviews"].groupby("order_id").review_score.agg(
        order_average_review_score="mean", review_order_records="count"
    ).reset_index()
    order_dimension_data = ranked_orders[[
        "order_id", "order_purchase_timestamp", "customer_unique_id", "customer_state",
        "order_gmv", "customer_order_number", "customer_order_type",
    ]].merge(delivery_fields.drop(columns="order_purchase_timestamp"), on="order_id", validate="one_to_one")
    order_dimension_data = order_dimension_data.merge(
        order_reviews, on="order_id", how="left", validate="one_to_one"
    )
    fact_order = order_dimension_data.rename(columns={
        "order_purchase_timestamp": "purchase_date",
        "customer_state": "state_code",
    })[[
        "order_id", "purchase_date", "customer_unique_id", "state_code", "order_gmv",
        "customer_order_number", "customer_order_type", "delivery_days", "late_flag",
        "delivery_status", "order_average_review_score", "review_order_records",
    ]]
    fact_order["purchase_date"] = pd.to_datetime(fact_order.purchase_date).dt.normalize()
    fact_order["delivery_time_bucket"] = np.select(
        [fact_order.delivery_days.lt(3), fact_order.delivery_days.lt(7), fact_order.delivery_days.lt(14)],
        ["under_3_days", "3_to_6_days", "7_to_13_days"],
        default="14_days_or_more",
    )
    fact_order.loc[fact_order.delivery_days.isna(), "delivery_time_bucket"] = pd.NA
    fact_order["delivery_bucket_order"] = fact_order.delivery_time_bucket.map({
        "under_3_days": 1, "3_to_6_days": 2, "7_to_13_days": 3, "14_days_or_more": 4,
    }).astype("Int64")
    fact_order = fact_order[[
        "order_id", "purchase_date", "customer_unique_id", "state_code", "order_gmv",
        "customer_order_number", "customer_order_type", "delivery_days", "late_flag",
        "delivery_status", "delivery_time_bucket", "delivery_bucket_order",
        "order_average_review_score", "review_order_records",
    ]]

    product_map = products[["product_id", "product_category_name"]].merge(
        translations, on="product_category_name", how="left", validate="many_to_one"
    )
    product_map["category_key"] = (
        product_map.product_category_name_english
        .fillna(product_map.product_category_name)
        .fillna("unknown")
    )
    fact_sales_item = (
        items.merge(
            ranked_orders[["order_id", "order_purchase_timestamp", "customer_unique_id", "customer_state", "customer_order_type"]],
            on="order_id", how="inner", validate="many_to_one",
        )
        .merge(product_map[["product_id", "category_key"]], on="product_id", validate="many_to_one")
        .rename(columns={"order_purchase_timestamp": "purchase_date", "customer_state": "state_code", "price": "item_price"})
        [["order_id", "order_item_id", "purchase_date", "customer_unique_id", "state_code",
          "product_id", "category_key", "seller_id", "customer_order_type", "item_price"]]
    )
    fact_sales_item["purchase_date"] = pd.to_datetime(fact_sales_item.purchase_date).dt.normalize()

    dim_date = pd.DataFrame({
        "date": pd.date_range(
            order_gmv.order_purchase_timestamp.min().to_period("M").start_time,
            order_gmv.order_purchase_timestamp.max().to_period("M").end_time.normalize(), freq="D",
        )
    })
    dim_date["year"] = dim_date.date.dt.year
    dim_date["quarter"] = "Q" + dim_date.date.dt.quarter.astype(str)
    dim_date["month_number"] = dim_date.date.dt.month
    dim_date["month_name"] = dim_date.date.dt.strftime("%B")
    dim_date["month_start"] = dim_date.date.dt.to_period("M").dt.to_timestamp()
    dim_date["year_month"] = dim_date.date.dt.strftime("%Y-%m")
    dim_date["week_start"] = dim_date.date - pd.to_timedelta(dim_date.date.dt.weekday, unit="D")

    dim_category = (
        product_map[["category_key"]].drop_duplicates().sort_values("category_key")
        .rename(columns={"category_key": "category_key"})
    )
    dim_product = product_map[["product_id", "category_key"]].drop_duplicates("product_id")
    dim_seller = tables["sellers"].loc[
        tables["sellers"].seller_id.isin(fact_sales_item.seller_id.unique()),
        ["seller_id", "seller_state", "seller_city"],
    ].drop_duplicates("seller_id").rename(columns={"seller_state": "seller_state_code"})
    dim_geography = pd.DataFrame({
        "state_code": sorted(fact_order.state_code.dropna().unique())
    })

    category_full_period = fact_sales_item.groupby("category_key").agg(
        category_gmv=("item_price", "sum"),
        category_orders=("order_id", "nunique"),
        item_count=("item_price", "size"),
    ).reset_index()
    category_full_period["average_category_order_value"] = (
        category_full_period.category_gmv / category_full_period.category_orders
    )
    median_orders = category_full_period.category_orders.median()
    median_order_value = category_full_period.average_category_order_value.median()
    category_full_period["category_quadrant"] = np.select(
        [
            category_full_period.category_orders.ge(median_orders)
            & category_full_period.average_category_order_value.ge(median_order_value),
            category_full_period.category_orders.ge(median_orders),
            category_full_period.average_category_order_value.ge(median_order_value),
        ],
        ["high-volume / high-value", "high-volume / lower-value", "lower-volume / high-value"],
        default="lower-volume / lower-value",
    )
    monthly_item = fact_sales_item.assign(
        purchase_month=pd.to_datetime(fact_sales_item.purchase_date).dt.to_period("M").dt.to_timestamp()
    )
    category_metrics = monthly_item.groupby(["purchase_month", "category_key"]).agg(
        category_gmv=("item_price", "sum"),
        category_orders=("order_id", "nunique"),
        item_count=("item_price", "size"),
    ).reset_index()
    category_metrics["average_item_value"] = category_metrics.category_gmv / category_metrics.item_count
    category_metrics["average_category_order_value"] = category_metrics.category_gmv / category_metrics.category_orders
    category_metrics = category_metrics.merge(
        category_full_period[["category_key", "category_quadrant"]],
        on="category_key", validate="many_to_one",
    )

    seller_metrics = fact_sales_item.groupby("seller_id").agg(
        seller_gmv=("item_price", "sum"), delivered_orders=("order_id", "nunique")
    ).reset_index().sort_values(["seller_gmv", "seller_id"], ascending=[False, True])
    seller_metrics["seller_position"] = np.arange(1, len(seller_metrics) + 1)
    seller_metrics["seller_gmv_share"] = seller_metrics.seller_gmv / seller_metrics.seller_gmv.sum()
    seller_metrics["cumulative_gmv_share"] = seller_metrics.seller_gmv.cumsum() / seller_metrics.seller_gmv.sum()
    seller_metrics = seller_metrics[[
        "seller_id", "seller_gmv", "delivered_orders", "seller_gmv_share",
        "cumulative_gmv_share", "seller_position",
    ]]

    first = customer_orders.groupby("customer_unique_id").purchase_month.min().rename("cohort_month")
    activity = customer_orders[["customer_unique_id", "purchase_month"]].drop_duplicates().merge(
        first.reset_index(), on="customer_unique_id", validate="many_to_one"
    )
    activity["month_index"] = (
        (activity.purchase_month.dt.year - activity.cohort_month.dt.year) * 12
        + activity.purchase_month.dt.month - activity.cohort_month.dt.month
    )
    cohort_sizes = first.groupby(first).size().rename("cohort_size")
    last_month = customer_orders.purchase_month.max()
    cohort_rows: list[dict[str, object]] = []
    for cohort_month, cohort_size in cohort_sizes.items():
        final_index = (last_month.year - cohort_month.year) * 12 + last_month.month - cohort_month.month
        cohort_activity = activity.loc[activity.cohort_month.eq(cohort_month)]
        active_counts = cohort_activity.groupby("month_index").customer_unique_id.nunique()
        for month_index in range(final_index + 1):
            active = int(active_counts.get(month_index, 0))
            cohort_rows.append({
                "cohort_month": cohort_month,
                "month_index": month_index,
                "cohort_size": int(cohort_size),
                "active_customers": active,
                "retention_rate": active / cohort_size,
            })
    fact_cohort = pd.DataFrame(cohort_rows)

    fact_order_category_delivery = (
        fact_sales_item[["order_id", "purchase_date", "state_code", "category_key"]]
        .drop_duplicates(["order_id", "category_key"])
        .merge(
            fact_order[["order_id", "delivery_days", "late_flag", "order_average_review_score"]],
            on="order_id", validate="many_to_one",
        )
        .dropna(subset=["delivery_days"])
    )

    return {
        "dim_date": dim_date,
        "dim_customer": dim_customer,
        "dim_category": dim_category,
        "dim_product": dim_product,
        "dim_seller": dim_seller,
        "dim_geography": dim_geography,
        "fact_order": fact_order,
        "fact_sales_item": fact_sales_item,
        "fact_category_economics": category_metrics,
        "fact_seller_performance": seller_metrics,
        "fact_cohort_retention": fact_cohort,
        "fact_order_category_delivery": fact_order_category_delivery,
    }


def write_exports(exports: dict[str, pd.DataFrame], output_dir: Path = OUTPUT) -> None:
    """Write Power BI CSVs with stable headers, portable encoding, and no index column."""
    output_dir.mkdir(parents=True, exist_ok=True)
    for name, frame in exports.items():
        if frame.columns.empty or not frame.columns.is_unique or any(not str(c).strip() for c in frame.columns):
            raise ValueError(f"{name} has missing or duplicate export column names")
        frame.to_csv(
            output_dir / f"{name}.csv",
            index=False,
            header=True,
            encoding="utf-8-sig",
            date_format=CSV_DATE_FORMAT,
            lineterminator="\n",
        )
        print(f"{name}: {len(frame):,} rows -> {output_dir / f'{name}.csv'}")


def main() -> None:
    exports = create_exports(read_sources())
    write_exports(exports)


if __name__ == "__main__":
    main()
