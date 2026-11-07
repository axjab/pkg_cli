"""Run from the repo root with python3 -m unittest discover -s tests -v."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor

LIB = Path(__file__).resolve().parents[1] / "lib"


class CreateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="pkg-create-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = dict(os.environ, NO_COLOR="1")
        self.env.pop("PKG_DEBUG", None)
        self.run_pkg("init")

    def run_pkg(self, command, *args, cwd=None, debug=False, env=None):
        environment = dict(self.env if env is None else env)
        if debug:
            environment["PKG_DEBUG"] = "1"
        return subprocess.run(
            [str(LIB / ("pkg-" + command)), *args],
            cwd=cwd or self.root, env=environment,
            capture_output=True, text=True,
        )

    def test_create_two_packages_and_list(self):
        for name in ("hello", "core"):
            result = self.run_pkg("create", name)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stderr, "")
            package = self.root / ".pkg/packages" / name
            self.assertTrue((package / "bin").is_dir())
            self.assertIn("Package: " + name + "\n",
                          (package / "DEBIAN/control").read_text())
        self.assertEqual(self.run_pkg("ls").stdout, "core\nhello\n")

    def test_duplicate_preserves_contents(self):
        self.run_pkg("create", "hello")
        control = self.root / ".pkg/packages/hello/DEBIAN/control"
        control.write_text("custom metadata\n")
        result = self.run_pkg("create", "hello", debug=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("pkg.debug.package.exists=true", result.stderr)
        self.assertEqual(control.read_text(), "custom metadata\n")

    def test_invalid_names_and_arguments(self):
        for args in ((), ("hello", "extra"), ("",), ("a",), ("Hello",),
                     ("../hello",), ("a/b",), ("a b",), ("-bad",), ("a\nb",)):
            with self.subTest(args=args):
                self.assertEqual(self.run_pkg("create", *args).returncode, 2)
        self.assertEqual(self.run_pkg("ls").stdout, "")

    def test_allowed_punctuation(self):
        self.assertEqual(self.run_pkg("create", "hello-tools.v1+extra").returncode, 0)

    def test_ancestor_discovery_and_debug(self):
        child = self.root / "child space"
        child.mkdir()
        result = self.run_pkg("create", "hello", cwd=child, debug=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        for field in ("workspace.current_marker_present=false",
                      "workspace.result=ancestor", "package.exists=false",
                      "package.name_valid=true", "package.metadata_complete=false",
                      "create.result=created"):
            self.assertIn("pkg.debug." + field, result.stderr)
        self.assertFalse((child / ".pkg").exists())

    def test_missing_workspace(self):
        # Remove the fixture's empty workspace.
        (self.root / ".pkg/packages").rmdir()
        (self.root / ".pkg").rmdir()
        result = self.run_pkg("create", "hello", debug=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("pkg.debug.workspace.discovered=false", result.stderr)
        self.assertFalse((self.root / ".pkg").exists())

    def test_nearest_workspace(self):
        child = self.root / "nested"
        (child / ".pkg/packages").mkdir(parents=True)
        self.assertEqual(self.run_pkg("create", "hello", cwd=child).returncode, 0)
        self.assertEqual(self.run_pkg("ls").stdout, "")
        self.assertEqual(self.run_pkg("ls", cwd=child).stdout, "hello\n")

    def test_invalid_storage(self):
        packages = self.root / ".pkg/packages"
        packages.rmdir()
        packages.write_text("preserve")
        self.assertEqual(self.run_pkg("create", "hello").returncode, 1)
        self.assertEqual(packages.read_text(), "preserve")

    def test_existing_symlink(self):
        target = self.root / ".pkg/packages/hello"
        target.symlink_to(self.root / "missing")
        self.assertEqual(self.run_pkg("create", "hello").returncode, 1)
        self.assertTrue(target.is_symlink())

    def test_help(self):
        result = self.run_pkg("create", "help")
        self.assertEqual(result.returncode, 0)
        self.assertIn("Usage: pkg create <name>", result.stdout)
        self.assertEqual(self.run_pkg("ls").stdout, "")

    def test_color(self):
        environment = dict(self.env)
        environment.pop("NO_COLOR", None)
        result = self.run_pkg("create", "hello", debug=True, env=environment)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("\033[32mtrue", result.stderr)
        self.assertIn("\033[31mfalse", result.stderr)

    def test_failed_staging_leaves_no_package(self):
        tools = self.root / "tools"
        tools.mkdir()
        mkdir = tools / "mkdir"
        mkdir.write_text("#!/bin/sh\nexit 7\n")
        mkdir.chmod(0o755)
        environment = dict(self.env, PATH=str(tools) + ":" + self.env["PATH"])
        result = self.run_pkg("create", "hello", debug=True, env=environment)
        self.assertEqual(result.returncode, 7)
        self.assertIn("pkg.debug.create.result=failed", result.stderr)
        self.assertEqual(self.run_pkg("ls").stdout, "")
        self.assertEqual(list((self.root / ".pkg").glob(".create.*")), [])

    def test_concurrent_duplicate(self):
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda _: self.run_pkg("create", "hello"), range(2)))
        self.assertEqual(sorted(r.returncode for r in results), [0, 1])
        self.assertEqual(self.run_pkg("ls").stdout, "hello\n")
        self.assertTrue((self.root / ".pkg/packages/hello/DEBIAN/control").is_file())
        self.assertEqual(list((self.root / ".pkg").glob(".create.*")), [])


if __name__ == "__main__":
    unittest.main()
