from concurrent.futures import ThreadPoolExecutor
import io
import os
from pathlib import Path
import pty
import subprocess
import tarfile
import tempfile
import unittest


LIB = Path(__file__).resolve().parents[1] / "lib"
BINARY = os.environ.get("PKG_TEST_BINARY")


class BuildTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="pkg build test ")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.env = dict(os.environ, NO_COLOR="1", SOURCE_DATE_EPOCH="1")
        self.env.pop("PKG_DEBUG", None)
        self.assert_ok(self.run_pkg("init"))

    def run_pkg(self, command, *args, cwd=None, stdin=subprocess.DEVNULL, debug=False, env=None):
        environment = dict(self.env if env is None else env)
        if BINARY:
            argv = [BINARY, "--debug", command, *args] if debug else [BINARY, command, *args]
        else:
            if debug:
                environment["PKG_DEBUG"] = "1"
            argv = [str(LIB / f"pkg-{command}"), *args]
        return subprocess.run(
            argv, cwd=cwd or self.root, env=environment, stdin=stdin,
            capture_output=True, text=True, timeout=15,
        )

    def assert_ok(self, result):
        self.assertEqual(result.returncode, 0, result.stderr)

    def stage(self, package, filename):
        source = self.root / filename
        source.write_text(f"#!/bin/sh\nprintf '%s\\n' '{filename}'\n")
        source.chmod(0o755)
        self.assert_ok(self.run_pkg("add", filename, "to", package))

    def test_builds_each_package_from_root_and_child(self):
        child = self.root / "child directory"
        child.mkdir()
        for package, executable, cwd in (("hello", "hello tool", self.root), ("core", "core-tool", child)):
            self.assert_ok(self.run_pkg("create", package))
            self.stage(package, executable)
            result = self.run_pkg("build", package, cwd=cwd, debug=True)
            self.assert_ok(result)
            artifact = self.root / ".pkg/archives" / f"{package}_0.0.0_all.deb"
            self.assertEqual(result.stdout, f"{artifact}\n")
            expected_discovery = "ancestor" if cwd == child else "current"
            for field in (f"workspace.result={expected_discovery}", "package.selection=explicit",
                          "build.verified=true", "build.result=built"):
                self.assertIn("pkg.debug." + field, result.stderr)
            self.assertNotIn("\033[", result.stderr)
            name = subprocess.check_output(["dpkg-deb", "--field", artifact, "Package"], text=True)
            self.assertEqual(name.strip(), package)
            payload = subprocess.check_output(["dpkg-deb", "--fsys-tarfile", artifact])
            with tarfile.open(fileobj=io.BytesIO(payload)) as archive:
                files = [entry for entry in archive if entry.isfile()]
                self.assertEqual([entry.name for entry in files], [f"./bin/{executable}"])
                self.assertEqual((files[0].uid, files[0].gid, files[0].mode), (0, 0, 0o755))
        self.assertFalse((child / ".pkg/archives").exists())

    def test_inferred_package_and_relative_output(self):
        self.assert_ok(self.run_pkg("create", "hello"))
        child = self.root / "child"
        child.mkdir()
        result = self.run_pkg("build", "to", "release files", cwd=child, debug=True)
        self.assert_ok(result)
        artifact = child / "release files/hello_0.0.0_all.deb"
        self.assertTrue(artifact.is_file())
        self.assertEqual(result.stdout, f"{artifact}\n")
        self.assertIn("pkg.debug.package.selection=only", result.stderr)
        self.assertFalse((self.root / ".pkg/archives").exists())

    def test_ambiguous_package_prompts_in_a_terminal(self):
        for name in ("hello", "core"):
            self.assert_ok(self.run_pkg("create", name))
        result = self.run_pkg("build")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Use pkg build <package>", result.stderr)
        self.assertFalse((self.root / ".pkg/archives").exists())
        master, terminal = pty.openpty()
        self.addCleanup(os.close, master)
        self.addCleanup(os.close, terminal)
        os.write(master, b"core\n")
        result = self.run_pkg("build", stdin=terminal)
        self.assert_ok(result)
        self.assertIn("Available packages:\n  core\n  hello\nPackage name:", result.stderr)
        self.assertEqual([p.name for p in (self.root / ".pkg/archives").iterdir()], ["core_0.0.0_all.deb"])

    def test_missing_unknown_and_invalid_arguments(self):
        for args, status, message in (
            ((), 1, "pkg create <name>"),
            (("hello",), 1, "pkg create hello"),
            (("hello", "in", "releases"), 2, "Usage: pkg build"),
            (("to", ""), 2, "Usage: pkg build"),
            (("../hello",), 2, "invalid package name"),
        ):
            with self.subTest(args=args):
                result = self.run_pkg("build", *args)
                self.assertEqual(result.returncode, status)
                self.assertEqual(result.stdout, "")
                self.assertIn(message, result.stderr)
        self.assertFalse((self.root / ".pkg/archives").exists())

    def test_rejects_output_inside_package_storage(self):
        self.assert_ok(self.run_pkg("create", "hello"))
        result = self.run_pkg("build", "to", ".pkg/packages/hello/releases")
        self.assertEqual(result.returncode, 1)
        self.assertIn("outside the managed .pkg directory", result.stderr)
        self.assertFalse((self.root / ".pkg/packages/hello/releases").exists())

    def test_retry_and_changed_build_preserve_existing_archive(self):
        self.assert_ok(self.run_pkg("create", "hello"))
        self.stage("hello", "first")
        result = self.run_pkg("build")
        self.assert_ok(result)
        artifact = Path(result.stdout.strip())
        previous = artifact.read_bytes()
        result = self.run_pkg("build", debug=True)
        self.assert_ok(result)
        self.assertIn("pkg.debug.build.result=already_built", result.stderr)
        self.stage("hello", "second")
        result = self.run_pkg("build")
        self.assertEqual(result.returncode, 1)
        self.assertIn("version 0.0.0 was already built with different contents", result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertEqual(artifact.read_bytes(), previous)
        self.assertEqual(list(artifact.parent.iterdir()), [artifact])

    def test_concurrent_builds_publish_only_one_archive(self):
        self.assert_ok(self.run_pkg("create", "hello"))
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(
                lambda epoch: self.run_pkg("build", env=dict(self.env, SOURCE_DATE_EPOCH=epoch)),
                ("1", "2"),
            ))
        self.assertEqual(sorted(result.returncode for result in results), [0, 1])
        files = list((self.root / ".pkg/archives").iterdir())
        self.assertEqual([file.name for file in files], ["hello_0.0.0_all.deb"])
        subprocess.run(["dpkg-deb", "--info", files[0]], check=True, capture_output=True)

    def test_build_and_verification_failures_leave_no_partial_artifact(self):
        self.assert_ok(self.run_pkg("create", "hello"))
        tools = self.root / "tools"
        tools.mkdir()
        builder = tools / "dpkg-deb"
        self.env["PATH"] = f"{tools}:{self.env['PATH']}"
        for failed_step, expected in (("build", 7), ("verification", 8)):
            with self.subTest(failed_step=failed_step):
                build_status = 7 if failed_step == "build" else 0
                builder.write_text(
                    '#!/bin/sh\n'
                    'if [ "$1" = --root-owner-group ]; then\n'
                    '    printf partial > "$4/hello_0.0.0_all.deb"\n'
                    f'    exit {build_status}\n'
                    'fi\n'
                    'exit 8\n'
                )
                builder.chmod(0o755)
                result = self.run_pkg("build", debug=True)
                self.assertEqual(result.returncode, expected)
                self.assertEqual(result.stdout, "")
                self.assertIn("pkg.debug.build.result=failed", result.stderr)
                self.assertEqual(list((self.root / ".pkg/archives").iterdir()), [])

    def test_help(self):
        result = self.run_pkg("help", "build") if BINARY else self.run_pkg("build", "help")
        self.assert_ok(result)
        self.assertIn("Usage: pkg build [<package>] [to <directory>]", result.stdout)
        self.assertEqual(result.stderr, "")
