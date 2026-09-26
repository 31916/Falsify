import os
import stat
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
MONITOR = REPOSITORY_ROOT / "arch2025_experiment" / "run_formal_parallel_monitor.sh"


class ParallelMonitorTest(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name) / "experiment"
        self.fake_bin = Path(self.temporary_directory.name) / "bin"
        self.fake_bin.mkdir(parents=True)
        self.launch_id = "test-launch"
        self.namespace = "test"
        self.manifest = self.root / "manifest.csv"
        self.manifest.parent.mkdir(parents=True)
        self.manifest.write_text("TrialID\ntrial-1\n", encoding="utf-8")
        self.fake_python = self.fake_bin / "fake-python"
        self._write_executable(
            self.fake_bin / "tmux",
            "#!/usr/bin/env bash\nexit 1\n",
        )
        self._write_executable(
            self.fake_python,
            textwrap.dedent(
                """\
                #!/usr/bin/env bash
                if [[ "$1" == *formal_tools.py && "$2" == aggregate ]]; then
                  if [[ "${FAKE_AGGREGATE_EXIT:-0}" != 0 ]]; then
                    exit "$FAKE_AGGREGATE_EXIT"
                  fi
                  while [[ $# -gt 0 ]]; do
                    if [[ "$1" == --output ]]; then
                      output=$2
                      break
                    fi
                    shift
                  done
                  mkdir -p "$output"
                  printf 'OverallPass\ntrue\n' > "$output/all_trials.csv"
                  exit 0
                fi
                if [[ "$1" == -c ]]; then
                  exit 0
                fi
                exit 2
                """
            ),
        )

    def tearDown(self):
        self.temporary_directory.cleanup()

    @staticmethod
    def _write_executable(path, contents):
        path.write_text(contents, encoding="utf-8")
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def _worker_exit_file(self, worker):
        path = (
            self.root
            / "manifests"
            / self.namespace
            / "workers"
            / self.launch_id
            / f"w{worker:02d}"
            / "exit-code.txt"
        )
        path.parent.mkdir(parents=True, exist_ok=True)
        return path

    def _run_monitor(self, aggregate_exit=0):
        environment = os.environ.copy()
        environment.update(
            {
                "PATH": f"{self.fake_bin}{os.pathsep}{environment['PATH']}",
                "FALSIFY_ARCH2025_EXPERIMENT_ROOT": str(self.root),
                "FALSIFY_ARCH2025_LAUNCH_ID": self.launch_id,
                "FALSIFY_ARCH2025_RUN_NAMESPACE": self.namespace,
                "FALSIFY_ARCH2025_MANIFEST": str(self.manifest),
                "FALSIFY_ARCH2025_EXPECTED_TRIALS": "1",
                "FALSIFY_ARCH2025_PYTHON_BIN": str(self.fake_python),
                "FAKE_AGGREGATE_EXIT": str(aggregate_exit),
            }
        )
        return subprocess.run(
            ["bash", str(MONITOR), "2"],
            check=False,
            capture_output=True,
            text=True,
            env=environment,
        )

    def _monitor_root(self):
        return (
            self.root
            / "manifests"
            / self.namespace
            / f"launch-{self.launch_id}"
            / "monitor"
        )

    def test_recovered_worker_failure_does_not_fail_complete_run(self):
        self._worker_exit_file(1).write_text("1\n", encoding="utf-8")
        self._worker_exit_file(2).write_text("0\n", encoding="utf-8")

        completed = self._run_monitor()

        self.assertEqual(completed.returncode, 0, completed.stderr)
        monitor_root = self._monitor_root()
        self.assertEqual(
            (monitor_root / "worker-failures.txt").read_text(encoding="utf-8").strip(),
            "1",
        )
        self.assertIn(
            "completed successfully with 1 recovered worker failure",
            (monitor_root / "status.txt").read_text(encoding="utf-8"),
        )
        self.assertEqual(
            (monitor_root / "exit-code.txt").read_text(encoding="utf-8").strip(),
            "0",
        )

    def test_aggregate_failure_still_fails_run(self):
        self._worker_exit_file(1).write_text("0\n", encoding="utf-8")
        self._worker_exit_file(2).write_text("0\n", encoding="utf-8")

        completed = self._run_monitor(aggregate_exit=3)

        self.assertEqual(completed.returncode, 1)
        monitor_root = self._monitor_root()
        self.assertIn(
            "incomplete or failed",
            (monitor_root / "status.txt").read_text(encoding="utf-8"),
        )
        self.assertEqual(
            (monitor_root / "aggregate-exit-code.txt").read_text(encoding="utf-8").strip(),
            "3",
        )
        self.assertEqual(
            (monitor_root / "exit-code.txt").read_text(encoding="utf-8").strip(),
            "1",
        )


if __name__ == "__main__":
    unittest.main()
