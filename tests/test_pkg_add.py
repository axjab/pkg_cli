import os
from pathlib import Path
import pty
import subprocess
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor

LIB = Path(__file__).resolve().parents[1] / "lib"
BINARY = os.environ.get("PKG_TEST_BINARY")


class AddTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="pkg add test ")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.packages = self.root / ".pkg/packages"
        self.source = self.root / "hello tool"
        self.source.write_text("#!/bin/sh\nprintf 'hello\\n'\n")
        self.source.chmod(0o751)
        self.env = dict(os.environ, NO_COLOR="1")
        self.env.pop("PKG_DEBUG", None)
        self.assertEqual(self.run_pkg("init").returncode, 0)

    def run_pkg(self, command, *args, cwd=None, debug=False, stdin=subprocess.DEVNULL,
                stderr=subprocess.PIPE):
        env = dict(self.env)
        if BINARY:
            argv = [BINARY]
            if debug:
                argv.append("--debug")
            argv.extend([command, *args])
        else:
            if debug:
                env["PKG_DEBUG"] = "1"
            argv = [str(LIB / f"pkg-{command}"), *args]
        return subprocess.run(
            argv, cwd=cwd or self.root, env=env, stdin=stdin,
            stdout=subprocess.PIPE, stderr=stderr, text=True, timeout=10,
        )

    def create(self, *names):
        for name in names:
            result = self.run_pkg("create", name)
            self.assertEqual(result.returncode, 0, result.stderr)

    def staged(self, name):
        return self.packages / name / "bin" / self.source.name

    def test_explicit_name_only_stages_in_selected_package(self):
        self.create("hello", "core")
        child = self.root / "child directory"
        child.mkdir()
        result = self.run_pkg("add", "../hello tool", "to", "hello", cwd=child)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, f"Staged: ../hello tool -> {self.staged('hello')}\n")
        self.assertEqual(result.stderr, "")
        self.assertEqual(self.staged("hello").read_bytes(), self.source.read_bytes())
        self.assertEqual(self.staged("hello").stat().st_mode & 0o777, 0o755)
        self.assertFalse(self.staged("core").exists())

        result = self.run_pkg("add", self.source.name, "core")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.staged("core").read_bytes(), self.source.read_bytes())

    def test_omitted_name_selects_only_package_in_nearest_workspace(self):
        self.create("outer")
        nested = self.root / "nested workspace"
        # Init reuses a parent workspace, so construct the nested fixture directly.
        (nested / ".pkg/packages").mkdir(parents=True)
        self.assertEqual(self.run_pkg("create", "inner", cwd=nested).returncode, 0)
        result = self.run_pkg("add", "../hello tool", cwd=nested, debug=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((nested / ".pkg/packages/inner/bin/hello tool").is_file())
        self.assertFalse(self.staged("outer").exists())
        for field in ("workspace.current_marker_present=true",
                      "workspace.discovered=true", "workspace.result=current",
                      "packages.count=1", "package.selection=only",
                      "package.name=inner", "add.result=staged"):
            self.assertIn("pkg.debug." + field, result.stderr)
        self.assertNotIn("\033[", result.stderr)
        self.assertNotIn("pkg.debug", result.stdout)

    def test_debug_color_and_ancestor_discovery(self):
        self.create("hello")
        child = self.root / "child"
        child.mkdir()
        self.env.pop("NO_COLOR")
        result = self.run_pkg("add", "../hello tool", cwd=child, debug=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("\033[31mfalse", result.stderr)
        self.assertIn("\033[32mtrue", result.stderr)
        self.assertIn("workspace.result\033[0m=\033[0mancestor", result.stderr)
        self.assertNotIn("pkg.debug", result.stdout)

    def test_empty_workspace_and_unknown_target_point_to_create(self):
        result = self.run_pkg("add", self.source.name)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertIn("pkg create <name>", result.stderr)
        self.create("core")
        result = self.run_pkg("add", self.source.name, "to", "hello")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertIn("pkg create hello", result.stderr)
        self.assertFalse(self.staged("core").exists())
        self.assertFalse((self.packages / "hello").exists())

    def test_multiple_packages_require_an_explicit_target_without_terminal(self):
        self.create("hello", "core")
        result = self.run_pkg("add", self.source.name, debug=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertIn("pkg.debug.package.selection=ambiguous", result.stderr)
        self.assertIn("pkg add <executable> to <package>", result.stderr)
        self.assertFalse(self.staged("hello").exists())
        self.assertFalse(self.staged("core").exists())

    def test_multiple_packages_prompt_in_a_terminal(self):
        self.create("hello", "core")
        master, terminal = pty.openpty()
        self.addCleanup(os.close, master)
        self.addCleanup(os.close, terminal)
        os.write(master, b"core\n")
        result = self.run_pkg("add", self.source.name, stdin=terminal, debug=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Available packages:\n  core\n  hello\nPackage name:", result.stderr)
        self.assertIn("pkg.debug.package.selection=interactive", result.stderr)
        self.assertTrue(self.staged("core").is_file())
        self.assertFalse(self.staged("hello").exists())

    def test_empty_terminal_selection_stages_nothing(self):
        self.create("hello", "core")
        master, terminal = pty.openpty()
        self.addCleanup(os.close, master)
        self.addCleanup(os.close, terminal)
        os.write(master, b"\n")
        result = self.run_pkg("add", self.source.name, stdin=terminal)
        self.assertEqual(result.returncode, 1)
        self.assertIn("no package selected", result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertFalse(self.staged("core").exists())
        self.assertFalse(self.staged("hello").exists())

    def test_gum_selection_keeps_the_menu_on_stderr(self):
        self.create("hello", "core")
        self.use_gum_stub()
        self.env["GUM_TEST_CHOICE"] = "core"
        result, terminal_output = self.run_add_with_gum_terminal()
        self.assertEqual(result.returncode, 0)
        self.assertIn(b"gum menu", terminal_output)
        self.assertEqual(result.stdout, f"Staged: {self.source.name} -> {self.staged('core')}\n")
        self.assertTrue(self.staged("core").is_file())
        self.assertFalse(self.staged("hello").exists())

    def test_unsuccessful_gum_selection_stages_nothing(self):
        self.create("hello", "core")
        self.use_gum_stub()
        for choice, status, expected in (("core", 130, 130), ("", 0, 1), ("other", 0, 1)):
            with self.subTest(choice=choice, status=status):
                self.env.update(GUM_TEST_CHOICE=choice, GUM_TEST_STATUS=str(status))
                result, terminal_output = self.run_add_with_gum_terminal()
                self.assertEqual(result.returncode, expected)
                self.assertEqual(result.stdout, "")
                self.assertIn(b"gum menu", terminal_output)
                self.assertFalse(self.staged("core").exists())
                self.assertFalse(self.staged("hello").exists())

    def use_gum_stub(self):
        gum = self.root / "gum"
        gum.write_text(
            '#!/bin/sh\n'
            '[ "$#" -eq 8 ] && [ "$1" = choose ] && [ "$6" = -- ] && '
            '[ "$7" = core ] && [ "$8" = hello ] || exit 2\n'
            'printf "gum menu\\n" >&2\n'
            'printf "%s" "$GUM_TEST_CHOICE"\n'
            'exit "${GUM_TEST_STATUS:-0}"\n'
        )
        gum.chmod(0o755)
        self.env.pop("NO_COLOR")
        self.env.update(TERM="xterm-256color", PATH=f"{self.root}:{self.env['PATH']}")

    def run_add_with_gum_terminal(self):
        master, terminal = pty.openpty()
        try:
            result = self.run_pkg("add", self.source.name, stdin=terminal, stderr=terminal)
            os.set_blocking(master, False)
            return result, os.read(master, 4096)
        finally:
            os.close(master)
            os.close(terminal)

    def test_no_workspace_and_malformed_nearest_marker(self):
        self.packages.rmdir()
        self.packages.parent.rmdir()
        result = self.run_pkg("add", self.source.name, debug=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("pkg.debug.workspace.discovered=false", result.stderr)
        self.assertIn("not a pkg workspace", result.stderr)
        self.assertEqual(self.run_pkg("init").returncode, 0)
        self.create("hello")
        child = self.root / "child"
        child.mkdir()
        (child / ".pkg").touch()
        result = self.run_pkg("add", "../hello tool", cwd=child)
        self.assertEqual(result.returncode, 1)
        self.assertIn("invalid workspace directory", result.stderr)
        self.assertFalse(self.staged("hello").exists())

    def test_invalid_source_and_arguments(self):
        self.create("hello")
        for args in ((), (self.source.name, "in", "hello"),
                     (self.source.name, "to", ""), (self.source.name, "../hello")):
            with self.subTest(args=args):
                self.assertEqual(self.run_pkg("add", *args).returncode, 2)
        self.source.chmod(0o644)
        result = self.run_pkg("add", self.source.name)
        self.assertEqual(result.returncode, 1)
        self.assertIn("readable executable file", result.stderr)
        self.assertFalse(self.staged("hello").exists())

    def test_duplicate_preserves_existing_file(self):
        self.create("hello")
        self.assertEqual(self.run_pkg("add", self.source.name).returncode, 0)
        duplicate = self.run_pkg("add", self.source.name, debug=True)
        self.assertEqual(duplicate.returncode, 0, duplicate.stderr)
        self.assertIn("pkg.debug.add.result=already_staged", duplicate.stderr)
        original = self.source.read_bytes()
        self.source.write_text("#!/bin/sh\nexit 9\n")
        result = self.run_pkg("add", self.source.name)
        self.assertEqual(result.returncode, 1)
        self.assertIn("destination already exists", result.stderr)
        self.assertEqual(self.staged("hello").read_bytes(), original)
        self.assertEqual(list(self.packages.parent.glob(".add.*")), [])

    def test_refuses_symlink_to_other_package_bin(self):
        self.create("hello", "core")
        bin_directory = self.packages / "hello/bin"
        bin_directory.rmdir()
        bin_directory.symlink_to(self.packages / "core/bin", target_is_directory=True)
        result = self.run_pkg("add", self.source.name, "to", "hello")
        self.assertEqual(result.returncode, 1)
        self.assertIn("invalid package layout", result.stderr)
        self.assertFalse(self.staged("core").exists())

    def test_copy_failure_cleans_temporary_state(self):
        self.create("hello")
        tools = self.root / "tools"
        tools.mkdir()
        installer = tools / "install"
        installer.write_text('#!/bin/sh\nprintf "partial" > "$5"\nexit 7\n')
        installer.chmod(0o755)
        self.env["PATH"] = f"{tools}:{self.env['PATH']}"
        result = self.run_pkg("add", self.source.name, debug=True)
        self.assertEqual(result.returncode, 7)
        self.assertIn("pkg.debug.add.result=failed", result.stderr)
        self.assertFalse(self.staged("hello").exists())
        self.assertEqual(list(self.packages.parent.glob(".add.*")), [])

    def test_concurrent_different_sources_do_not_overwrite(self):
        self.create("hello")
        other = self.root / "other" / self.source.name
        other.parent.mkdir()
        other.write_text("#!/bin/sh\nexit 9\n")
        other.chmod(0o755)
        sources = (self.source, other)
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda path: self.run_pkg("add", str(path)), sources))
        self.assertEqual(sorted(result.returncode for result in results), [0, 1])
        winner = sources[0] if results[0].returncode == 0 else sources[1]
        self.assertEqual(self.staged("hello").read_bytes(), winner.read_bytes())
        self.assertEqual(list(self.packages.parent.glob(".add.*")), [])

    def test_help(self):
        result = self.run_pkg("help", "add") if BINARY else self.run_pkg("add", "help")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Usage: pkg add <executable> [to <package>]", result.stdout)
        self.assertEqual(result.stderr, "")
