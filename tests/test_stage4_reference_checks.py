"""Reference checks over cleaned CSVs for the Stage 4 SQL definitions.

These checks validate data grains and reference totals; the PostgreSQL validation
queries remain the source of truth after the tables are loaded into PostgreSQL.
"""

import unittest
from pathlib import Path

import numpy as np
import pandas as pd


DATA_DIR = Path(__file__).resolve().parents[1] / "data" / "processed"


class Stage4ReferenceChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.orders = pd.read_csv(
            DATA_DIR / "olist_orders_dataset.csv",
            parse_dates=[
                "order_purchase_timestamp",
                "order_delivered_customer_date",
                "order_estimated_delivery_date",
            ],
        )
        cls.items = pd.read_csv(DATA_DIR / "olist_order_items_dataset.csv")
        cls.customers = pd.read_csv(DATA_DIR / "olist_customers_dataset.csv")
        cls.products = pd.read_csv(DATA_DIR / "olist_products_dataset.csv")
        cls.sellers = pd.read_csv(DATA_DIR / "olist_sellers_dataset.csv")
        cls.reviews = pd.read_csv(DATA_DIR / "olist_order_reviews_dataset.csv")
        delivered = cls.orders.loc[cls.orders.order_status.eq("delivered")]
        cls.delivered_orders = delivered
        cls.lines = delivered[["order_id", "customer_id", "order_purchase_timestamp"]].merge(
            cls.items, on="order_id", validate="one_to_many"
        )
        cls.order_gmv = cls.lines.groupby(
            ["order_id", "customer_id", "order_purchase_timestamp"], as_index=False
        )["price"].sum().rename(columns={"price": "gmv"})

    def test_order_month_category_and_seller_gmv_grains_reconcile(self):
        total_gmv = self.order_gmv.gmv.sum()
        monthly = self.lines.assign(
            purchase_month=self.lines.order_purchase_timestamp.dt.to_period("M")
        ).groupby("purchase_month").price.sum()
        category_items = self.lines.merge(
            self.products[["product_id", "product_category_name"]],
            on="product_id",
            validate="many_to_one",
        )
        seller_items = self.lines.merge(
            self.sellers[["seller_id"]], on="seller_id", validate="many_to_one"
        )
        self.assertAlmostEqual(total_gmv, monthly.sum(), places=2)
        self.assertAlmostEqual(total_gmv, category_items.price.sum(), places=2)
        self.assertAlmostEqual(total_gmv, seller_items.price.sum(), places=2)

    def test_customer_value_and_repeat_customer_population_reconcile(self):
        customer_orders = self.order_gmv.merge(
            self.customers[["customer_id", "customer_unique_id"]],
            on="customer_id",
            validate="many_to_one",
        )
        value = customer_orders.groupby("customer_unique_id").agg(
            orders=("order_id", "nunique"), gmv=("gmv", "sum")
        )
        self.assertEqual(len(value), 93_358)
        self.assertEqual(int(value.orders.ge(2).sum()), 2_801)
        self.assertAlmostEqual(value.gmv.sum(), self.order_gmv.gmv.sum(), places=2)

    def test_rfm_quintiles_and_segment_sizes_reproduce_reference(self):
        customer_orders = self.order_gmv.merge(
            self.customers[["customer_id", "customer_unique_id"]],
            on="customer_id",
            validate="many_to_one",
        )
        rfm = customer_orders.groupby("customer_unique_id").agg(
            frequency=("order_id", "nunique"),
            monetary=("gmv", "sum"),
            last_purchase=("order_purchase_timestamp", "max"),
        ).reset_index()
        snapshot = customer_orders.order_purchase_timestamp.max().normalize() + pd.Timedelta(days=1)
        rfm["recency"] = (snapshot - rfm.last_purchase.dt.normalize()).dt.days

        def score_quintile(column, invert=False):
            ordered = rfm.sort_values([column, "customer_unique_id"], kind="mergesort")
            row_number = np.arange(1, len(ordered) + 1)
            quotient, remainder = divmod(len(ordered), 5)
            first_group_rows = (quotient + 1) * remainder
            tiles = np.where(
                row_number <= first_group_rows,
                np.ceil(row_number / (quotient + 1)),
                remainder + np.ceil((row_number - first_group_rows) / quotient),
            ).astype(int)
            scores = pd.Series(tiles, index=ordered.index).reindex(rfm.index)
            return 6 - scores if invert else scores

        rfm["r_score"] = score_quintile("recency", invert=True)
        rfm["f_score"] = score_quintile("frequency")
        rfm["m_score"] = score_quintile("monetary")

        def segment(row):
            recency, frequency, monetary = row.r_score, row.f_score, row.m_score
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

        rfm["segment"] = rfm.apply(segment, axis=1)
        counts = rfm.segment.value_counts().to_dict()
        self.assertEqual(len(rfm), 93_358)
        self.assertEqual(counts, {
            "Loyal Customers": 15_982,
            "Hibernating": 15_004,
            "Cannot Lose Them": 14_870,
            "Potential Loyalists": 14_956,
            "Champions": 6_490,
            "New Customers": 7_481,
            "At Risk": 7_468,
            "Need Attention": 7_389,
            "Promising": 3_718,
        })

    def test_cohort_month_zero_is_full_and_retention_is_bounded(self):
        customer_orders = self.order_gmv.merge(
            self.customers[["customer_id", "customer_unique_id"]],
            on="customer_id",
            validate="many_to_one",
        )
        customer_orders["purchase_month"] = customer_orders.order_purchase_timestamp.dt.to_period("M")
        first_month = customer_orders.groupby("customer_unique_id").purchase_month.min()
        cohort_sizes = first_month.groupby(first_month).size()
        for cohort_month, size in cohort_sizes.items():
            cohort_customer_ids = set(first_month[first_month.eq(cohort_month)].index)
            month_zero_active = customer_orders.loc[
                customer_orders.customer_unique_id.isin(cohort_customer_ids)
                & customer_orders.purchase_month.eq(cohort_month),
                "customer_unique_id",
            ].nunique()
            self.assertEqual(month_zero_active, size)

    def test_seller_top_twenty_share_is_at_least_top_ten(self):
        seller_gmv = self.lines.groupby("seller_id").price.sum().sort_values(ascending=False)
        top_10_share = seller_gmv.head(10).sum() / seller_gmv.sum()
        top_20_share = seller_gmv.head(20).sum() / seller_gmv.sum()
        self.assertGreaterEqual(top_20_share, top_10_share)
        self.assertLessEqual(top_20_share, 1)
        self.assertAlmostEqual(top_10_share * 100, 13.27, places=2)
        self.assertAlmostEqual(top_20_share * 100, 21.28, places=2)

    def test_delivery_review_join_stays_at_order_grain(self):
        delivered = self.delivered_orders.loc[
            self.delivered_orders.order_delivered_customer_date.notna()
            & self.delivered_orders.order_estimated_delivery_date.notna()
        ].copy()
        delivered["delivery_days"] = (
            delivered.order_delivered_customer_date - delivered.order_purchase_timestamp
        ).dt.total_seconds() / 86_400
        delivered["is_late"] = (
            delivered.order_delivered_customer_date > delivered.order_estimated_delivery_date
        )
        review_by_order = self.reviews.groupby("order_id").review_score.mean().rename("order_score")
        with_reviews = delivered.merge(
            review_by_order, left_on="order_id", right_index=True, validate="one_to_one"
        )
        self.assertEqual(len(delivered), 96_470)
        self.assertEqual(int(delivered.is_late.sum()), 7_826)
        self.assertEqual(len(with_reviews), 95_824)
        self.assertLess(with_reviews.delivery_days.corr(with_reviews.order_score), 0)
        self.assertAlmostEqual(with_reviews.delivery_days.corr(with_reviews.order_score), -0.3343, places=4)


if __name__ == "__main__":
    unittest.main()
