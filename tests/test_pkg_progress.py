from pathlib import Path
import os
import pty
import subprocess
import unittest

PROGRESS = Path(__file__).resolve().parents[1] / "lib" / "progress.sh"


class ProgressTests(unittest.TestCase):
    def test_redirected_output_has_no_animation_and_preserves_status(self):
        result = subprocess.run(
            ["bash", "-c",
             'source "$1"; pkg_run_with_spinner "Working" bash -c '
             '"printf result; printf diagnostic >&2; exit 7"',
             "test", str(PROGRESS)],
            capture_output=True, text=True, timeout=5,
        )
        self.assertEqual(result.returncode, 7)
        self.assertEqual(result.stdout, "result")
        self.assertEqual(result.stderr, "diagnostic")
        self.assertNotIn("\x1b[", result.stderr)

    def test_terminal_output_shows_spinner_and_preserves_command_output(self):
        master, slave = pty.openpty()
        self.addCleanup(os.close, master)
        self.addCleanup(os.close, slave)
        result = subprocess.run(
            ["bash", "-c",
             'source "$1"; pkg_run_with_spinner "Working" bash -c '
             '"sleep 0.35; printf result; printf diagnostic >&2"',
             "test", str(PROGRESS)],
            stdout=subprocess.PIPE, stderr=slave, text=True, timeout=5,
        )
        output = os.read(master, 4096).decode()
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "result")
        self.assertIn("Working", output)
        self.assertIn("diagnostic", output)
        self.assertIn("\r", output)


if __name__ == "__main__":
    unittest.main()
