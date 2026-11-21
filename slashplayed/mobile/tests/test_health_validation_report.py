import unittest

from health_validation_report import summarize


class HealthValidationReportTest(unittest.TestCase):
    def test_reports_false_ready_and_reference_coverage(self):
        results = summarize([
            "AI health validation: paired visual=73 public=28\n",
            "AI health validation: paired visual=91 public=97\n",
            "AI health validation: paired visual=51 public=49\n",
            "AI health validation: unreadable visual=255 public=47\n",
            "AI health validation: changing visual=95 public=255\n",
            "AI health validation: paired visual=255 public=2\n",
        ])
        self.assertEqual(results["reference_coverage"], {"low": 1, "normal": 1, "recovery": 2})
        self.assertEqual(results["observations"]["invalid"], 1)
        self.assertEqual(results["false_ready_pairs"], 2)
        self.assertEqual(results["missed_low_pairs"], 1)
        self.assertEqual(results["maximum_overestimate_pp"], 45)
        self.assertEqual(results["mean_absolute_error_pp"], 17.67)

    def test_without_reference_does_not_report_zero_errors(self):
        results = summarize(["AI health validation: unknown visual=99 public=255\n"])
        self.assertIsNone(results["false_ready_pairs"])
        self.assertIsNone(results["mean_absolute_error_pp"])


if __name__ == "__main__":
    unittest.main()
