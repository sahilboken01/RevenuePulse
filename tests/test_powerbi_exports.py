import csv
import tempfile
import unittest
from pathlib import Path

import pandas as pd

from src.export_powerbi_data import create_exports, read_sources, write_exports


class PowerBIExportChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.datasets = create_exports(read_sources())

    def test_export_grains_and_expected_row_counts(self):
        expected = {
            "dim_date": 730,
            "dim_customer": 93_358,
            "dim_category": 74,
            "dim_product": 32_951,
            "dim_seller": 2_970,
            "dim_geography": 27,
            "fact_order": 96_478,
            "fact_sales_item": 110_197,
            "fact_category_economics": 1_273,
            "fact_seller_performance": 2_970,
            "fact_cohort_retention": 278,
            "fact_order_category_delivery": 97_268,
        }
        self.assertEqual({name: len(frame) for name, frame in self.datasets.items()}, expected)
        self.assertEqual(self.datasets["fact_order"].order_id.nunique(), 96_478)
        self.assertFalse(self.datasets["fact_sales_item"].duplicated(["order_id", "order_item_id"]).any())
        self.assertFalse(self.datasets["fact_cohort_retention"].duplicated(["cohort_month", "month_index"]).any())
        self.assertFalse(self.datasets["fact_order_category_delivery"].duplicated(["order_id", "category_key"]).any())

    def test_order_item_category_and_seller_gmv_reconcile(self):
        fact_order = self.datasets["fact_order"]
        fact_item = self.datasets["fact_sales_item"]
        fact_category = self.datasets["fact_category_economics"]
        fact_seller = self.datasets["fact_seller_performance"]
        expected_gmv = 13_221_498.11
        for actual in [
            fact_order.order_gmv.sum(),
            fact_item.item_price.sum(),
            fact_category.category_gmv.sum(),
            fact_seller.seller_gmv.sum(),
        ]:
            self.assertAlmostEqual(actual, expected_gmv, places=2)

    def test_date_and_dimension_keys_are_model_ready(self):
        date_keys = set(pd.to_datetime(self.datasets["dim_date"].date))
        self.assertTrue(set(pd.to_datetime(self.datasets["fact_order"].purchase_date)).issubset(date_keys))
        self.assertTrue(set(pd.to_datetime(self.datasets["fact_sales_item"].purchase_date)).issubset(date_keys))
        self.assertTrue(set(pd.to_datetime(self.datasets["fact_cohort_retention"].cohort_month)).issubset(date_keys))
        self.assertTrue(set(self.datasets["fact_order"].customer_unique_id).issubset(
            set(self.datasets["dim_customer"].customer_unique_id)
        ))
        self.assertTrue(set(self.datasets["fact_sales_item"].category_key).issubset(
            set(self.datasets["dim_category"].category_key)
        ))
        self.assertTrue(set(self.datasets["fact_sales_item"].product_id).issubset(
            set(self.datasets["dim_product"].product_id)
        ))
        self.assertTrue(set(self.datasets["fact_sales_item"].seller_id).issubset(
            set(self.datasets["dim_seller"].seller_id)
        ))

    def test_cohort_month_zero_and_category_classification(self):
        cohort = self.datasets["fact_cohort_retention"]
        month_zero = cohort.loc[cohort.month_index.eq(0)]
        self.assertEqual(len(month_zero), 23)
        self.assertTrue(month_zero.retention_rate.eq(1).all())
        self.assertTrue(cohort.retention_rate.between(0, 1).all())
        self.assertEqual(
            self.datasets["fact_category_economics"].drop_duplicates("category_key").category_quadrant.value_counts().to_dict(),
            {
                "high-volume / high-value": 20,
                "lower-volume / lower-value": 20,
                "high-volume / lower-value": 17,
                "lower-volume / high-value": 17,
            },
        )

    def test_csv_writer_preserves_headers_and_omits_dataframe_index(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            write_exports(self.datasets, Path(temp_dir))
            for name, frame in self.datasets.items():
                path = Path(temp_dir) / f"{name}.csv"
                with path.open(encoding="utf-8-sig", newline="") as csv_file:
                    header = next(csv.reader(csv_file))
                self.assertEqual(header, list(frame.columns), name)
                self.assertFalse(any(column.startswith("Unnamed:") for column in header), name)


if __name__ == "__main__":
    unittest.main()
