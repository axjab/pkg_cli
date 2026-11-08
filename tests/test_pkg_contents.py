from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


LIB = Path(__file__).resolve().parents[1] / "lib"
BINARY = os.environ.get("PKG_TEST_BINARY")


class PackageContentsTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="pkg contents test ")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.env = dict(os.environ, NO_COLOR="1")
        self.env.pop("PKG_DEBUG", None)
        self.run_pkg("init")
        self.run_pkg("create", "hello")
        self.package = self.root / ".pkg/packages/hello"
        self.control = self.package / "DEBIAN/control"

    def run_pkg(self, command, *args, status=0):
        argv = [BINARY, command] if BINARY else [str(LIB / f"pkg-{command}")]
        result = subprocess.run(
            [*argv, *args], cwd=self.root, env=self.env, stdin=subprocess.DEVNULL,
            capture_output=True, text=True, timeout=15,
        )
        if status is None:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        else:
            self.assertEqual(result.returncode, status, result.stderr)
        return result

    def test_query_and_remove_executables_in_one_package(self):
        self.run_pkg("create", "core")
        self.assertEqual(self.run_pkg("ls").stdout, "core\nhello\n")
        self.assertEqual(self.run_pkg("ls", "--executables", "hello").stdout, "")
        source = self.root / "hello tool"
        source.write_text("#!/bin/sh\n")
        source.chmod(0o755)
        for name in ("core", "hello"):
            self.run_pkg("add", source.name, "to", name)
        self.assertEqual(self.run_pkg("ls", "--executables", "hello").stdout, "hello tool\n")
        listing = self.run_pkg("ls", "hello").stdout
        self.assertIn("Executables\n", listing)
        self.assertIn("Dependencies\n  (empty)", listing)
        self.run_pkg("rm", source.name, "from", "hello")
        self.assertEqual(self.run_pkg("ls", "--executables", "hello").stdout, "")
        self.assertEqual(self.run_pkg("ls", "--executables", "core").stdout, "hello tool\n")
        self.run_pkg("rm", source.name, "from", "hello", status=1)
        self.run_pkg("rm", "../hello tool", "from", "hello", status=2)
        self.run_pkg("ls", "--deps", "missing", status=1)

    def test_add_query_build_and_remove_dependencies(self):
        original = self.control.read_bytes()
        self.assertEqual(self.run_pkg("ls", "--deps", "hello").stdout, "")
        relationship = "curl (>= 8) | wget"
        self.run_pkg("add", "--dep", "gum")
        self.run_pkg("add", "--dep", relationship, "to", "hello")
        self.run_pkg("add", "--dep", "gum", "to", "hello")
        self.assertEqual(self.run_pkg("ls", "--deps", "hello").stdout, f"gum\n{relationship}\n")
        archive = self.run_pkg("build", "hello").stdout.strip()
        depends = subprocess.check_output(["dpkg-deb", "--field", archive, "Depends"], text=True)
        self.assertEqual(depends, f"gum, {relationship}\n")
        self.run_pkg("rm", "--dep", relationship, "from", "hello")
        self.assertEqual(self.run_pkg("ls", "--deps", "hello").stdout, "gum\n")
        self.run_pkg("rm", "--dep", "gum")
        self.assertEqual(self.control.read_bytes(), original)
        self.run_pkg("rm", "--dep", "gum", status=1)

    def test_preserves_unrelated_fields_and_reads_continuations(self):
        original = self.control.read_text() + "Pre-Depends: bash\nRecommends: less\n"
        self.control.write_text(original + "depends: gum,\n curl (>= 8) | wget\n")
        self.assertEqual(self.run_pkg("ls", "--deps", "hello").stdout, "gum\ncurl (>= 8) | wget\n")
        self.run_pkg("rm", "--dep", "gum", "hello")
        self.assertEqual(self.control.read_text(), original + "Depends: curl (>= 8) | wget\n")

    def test_invalid_dependency_leaves_control_untouched(self):
        original = self.control.read_bytes()
        for value in ("", "gum, wget", "gum\nDescription: injected", "gum (>= invalid)"):
            with self.subTest(value=value):
                self.run_pkg("add", "--dep", value, "to", "hello", status=None)
                self.assertEqual(self.control.read_bytes(), original)
        self.assertEqual(list((self.root / ".pkg").glob(".depends.*")), [])

    def test_concurrent_dependency_updates_are_preserved(self):
        dependencies = ["gum", "curl", "wget", "openssh-client"]
        with ThreadPoolExecutor() as workers:
            list(workers.map(lambda entry: self.run_pkg("add", "--dep", entry), dependencies))
        result = self.run_pkg("ls", "--deps", "hello")
        self.assertCountEqual(result.stdout.splitlines(), dependencies)
