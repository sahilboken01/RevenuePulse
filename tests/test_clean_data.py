import unittest

import pandas as pd

from src.clean_data import build_report, clean_table


class CleaningRuleTests(unittest.TestCase):
    def test_exact_duplicates_are_removed_and_reported(self):
        frame = pd.DataFrame({"order_id": ["a", "a"], "order_status": ["delivered", "delivered"]})
        cleaned, report = clean_table("orders", frame)
        self.assertEqual(len(cleaned), 1)
        self.assertEqual(report["exact_duplicate_rows_removed"], 1)

    def test_invalid_dates_become_null_and_are_counted(self):
        frame = pd.DataFrame({"order_purchase_timestamp": ["2018-01-01", "not-a-date", None]})
        cleaned, report = clean_table("orders", frame)
        self.assertTrue(pd.isna(cleaned.loc[1, "order_purchase_timestamp"]))
        self.assertEqual(report["invalid_dates_set_null"]["order_purchase_timestamp"], 1)

    def test_negative_price_and_freight_become_null_without_dropping_rows(self):
        frame = pd.DataFrame({"price": [10.0, -1.0], "freight_value": [0.0, -2.0]})
        cleaned, report = clean_table("order_items", frame)
        self.assertEqual(len(cleaned), 2)
        self.assertTrue(pd.isna(cleaned.loc[1, "price"]))
        self.assertTrue(pd.isna(cleaned.loc[1, "freight_value"]))
        self.assertEqual(report["negative_currency_values_set_null"], {"price": 1, "freight_value": 1})

    def test_text_values_are_trimmed_and_lowercased(self):
        frame = pd.DataFrame({"order_status": [" Delivered ", "CANCELED"]})
        cleaned, _ = clean_table("orders", frame)
        self.assertEqual(cleaned["order_status"].tolist(), ["delivered", "canceled"])

    def test_orphan_foreign_keys_are_reported_not_removed(self):
        tables = {
            "customers": pd.DataFrame({"customer_id": ["known"]}),
            "orders": pd.DataFrame({
                "order_id": ["o1", "o2"], "customer_id": ["known", "missing"],
                "order_status": ["delivered", "delivered"],
                "order_approved_at": [None, None], "order_purchase_timestamp": [None, None],
                "order_delivered_carrier_date": [None, None], "order_delivered_customer_date": [None, None],
            }),
            "order_items": pd.DataFrame({"order_id": [], "product_id": [], "seller_id": []}),
            "products": pd.DataFrame({"product_id": [], "product_category_name": []}),
            "sellers": pd.DataFrame({"seller_id": []}),
            "order_payments": pd.DataFrame({"order_id": [], "payment_type": []}),
            "order_reviews": pd.DataFrame({"order_id": []}),
            "category_translation": pd.DataFrame({"product_category_name": []}),
        }
        report = build_report(tables, {})
        self.assertEqual(report["foreign_key_orphan_rows"]["orders.customer_id"], 1)


if __name__ == "__main__":
    unittest.main()
