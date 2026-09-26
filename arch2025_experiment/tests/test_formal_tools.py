import csv
import importlib.util
import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from types import SimpleNamespace


MODULE_PATH = Path(__file__).parents[1] / "formal_tools.py"
SPEC = importlib.util.spec_from_file_location("formal_tools", MODULE_PATH)
FORMAL_TOOLS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(FORMAL_TOOLS)


class FormalToolsProtocolTest(unittest.TestCase):
    def write_csv(self, path, rows):
        with path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)

    def valid_summary_row(self):
        return {
            "CaseID": "cc_cc1_i2_rand",
            "Seed": "20250001",
            "Status": "VALIDATED",
            "TrialComplete": "true",
            "OverallPass": "true",
            "InputPass": "true",
            "FalsifyRunPass": "true",
            "OfficialReplayPass": "true",
            "ClassificationAgreementPass": "true",
            "EvaluationProtocol": FORMAL_TOOLS.EVALUATION_PROTOCOL,
            "ObjectiveSource": FORMAL_TOOLS.OBJECTIVE_SOURCE,
            "Episodes": "3",
            "OfficialEvaluationCount": "3",
            "FalsifyRobustness": "-0.125",
            "OfficialRobustness": "-0.125",
            "OfficialClassification": "VIOLATED",
        }

    def validation_args(self, root, summary):
        return SimpleNamespace(
            matlab_exit="0",
            summary=str(summary),
            case_id="cc_cc1_i2_rand",
            seed="20250001",
            max_evaluations="1500",
            trial_id="s01_cc_cc1_i2_rand",
            batch_id="s01_cc",
            sequence="1",
            time_file=str(root / "time.txt"),
            matlab_log=str(root / "matlab.log"),
            attempt_status=str(root / "attempt.json"),
            complete=str(root / "complete.json"),
        )

    def test_validate_attempt_accepts_official_per_episode_result(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            summary = root / "summary.csv"
            self.write_csv(summary, [self.valid_summary_row()])

            result = FORMAL_TOOLS.validate_attempt(
                self.validation_args(root, summary)
            )

            self.assertEqual(result, 0)
            complete = json.loads((root / "complete.json").read_text())
            self.assertEqual(
                complete["EvaluationProtocol"],
                FORMAL_TOOLS.EVALUATION_PROTOCOL,
            )
            self.assertEqual(complete["OfficialEvaluationCount"], 3)

    def test_validate_attempt_rejects_legacy_posthoc_result(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            summary = root / "summary.csv"
            row = self.valid_summary_row()
            row["EvaluationProtocol"] = ""
            row["OfficialEvaluationCount"] = "1"
            self.write_csv(summary, [row])

            result = FORMAL_TOOLS.validate_attempt(
                self.validation_args(root, summary)
            )

            self.assertEqual(result, 1)
            status = json.loads((root / "attempt.json").read_text())
            self.assertEqual(status["Outcome"], "ERROR")
            self.assertFalse((root / "complete.json").exists())

    def test_pending_does_not_skip_legacy_completion_marker(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = root / "manifest.csv"
            run_root = root / "runs"
            trial_id = "s01_cc_cc1_i2_rand"
            row = {
                "Sequence": "1",
                "BatchID": "s01_cc",
                "SeedIndex": "1",
                "Seed": "20250001",
                "TrialID": trial_id,
                "CaseID": "cc_cc1_i2_rand",
                "Model": "CC",
                "Requirement": "CC1",
                "Instance": "2",
                "Algorithm": "RAND",
                "MaxEvaluations": "1500",
            }
            self.write_csv(manifest, [row])
            trial_root = run_root / trial_id
            trial_root.mkdir(parents=True)
            (trial_root / "complete.json").write_text(
                json.dumps({"EvaluationProtocol": "legacy-posthoc"})
            )

            output = io.StringIO()
            with redirect_stdout(output):
                FORMAL_TOOLS.list_pending(SimpleNamespace(
                    manifest=str(manifest),
                    batch="s01_cc",
                    run_root=str(run_root),
                ))

            self.assertIn(trial_id, output.getvalue())

            (trial_root / "complete.json").write_text(json.dumps({
                "EvaluationProtocol": FORMAL_TOOLS.EVALUATION_PROTOCOL,
            }))
            output = io.StringIO()
            with redirect_stdout(output):
                FORMAL_TOOLS.list_pending(SimpleNamespace(
                    manifest=str(manifest),
                    batch="s01_cc",
                    run_root=str(run_root),
                ))
            self.assertEqual(output.getvalue(), "")


if __name__ == "__main__":
    unittest.main()
