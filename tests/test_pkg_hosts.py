from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import pty
import subprocess
import tempfile
import unittest

LIB = Path(__file__).resolve().parents[1] / "lib"
BINARY = os.environ.get("PKG_TEST_BINARY")


class HostTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="pkg hosts ")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.log = self.root / "ssh.log"
        tools = self.root / "tools"
        tools.mkdir()
        ssh = tools / "ssh"
        ssh.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$SSH_LOG"\nexit "$SSH_STATUS"\n')
        ssh.chmod(0o755)
        self.env = dict(os.environ, PATH=f"{tools}:{os.environ['PATH']}",
                        SSH_LOG=str(self.log), SSH_STATUS="0", NO_COLOR="1")
        self.env.pop("PKG_DEBUG", None)
        self.assertEqual(self.run_pkg("init").returncode, 0)

    def run_pkg(self, command, *args, cwd=None, stdin=subprocess.DEVNULL, debug=False,
                output=subprocess.PIPE):
        env = dict(self.env)
        if BINARY:
            argv = [BINARY]
            if debug:
                argv.append("--debug")
            argv += [command, *args]
        else:
            if debug:
                env["PKG_DEBUG"] = "1"
            argv = [str(LIB / f"pkg-{command}"), *args]
        return subprocess.run(argv, cwd=cwd or self.root, env=env, stdin=stdin,
                              text=True, stdout=output, stderr=output, timeout=10)

    def test_offline_registration_and_alias_listing_from_child(self):
        child = self.root / "child directory"
        child.mkdir()
        for command in ("host", "hosts"):
            empty = self.run_pkg(command, cwd=child)
            self.assertEqual(empty.returncode, 0)
            self.assertEqual(empty.stdout, "")
            self.assertIn("No hosts configured. Add one with pkg host add <host>.", empty.stderr)
        for host in ("pkg-host", "apt@old_shrine"):
            result = self.run_pkg("host", "add", host, cwd=child)
            self.assertEqual(result.returncode, 0, result.stderr)
        for command in ("host", "hosts"):
            self.assertEqual(self.run_pkg(command, cwd=child).stdout, "apt@old_shrine\npkg-host\n")
        self.assertFalse(self.log.exists())
        self.assertFalse((child / ".pkg").exists())

    def test_ping_only_host_and_preserve_ssh_status(self):
        self.run_pkg("host", "add", "pkg-host")
        self.env["SSH_STATUS"] = "255"
        result = self.run_pkg("ping", debug=True)
        self.assertEqual(result.returncode, 255)
        self.assertEqual(result.stdout, "")
        self.assertIn("pkg.debug.host.selection=only", result.stderr)
        self.assertIn("pkg.debug.ping.exit=255", result.stderr)
        self.assertEqual(self.log.read_text().splitlines()[-3:], ["--", "pkg-host", "true"])

    def test_ping_colors_terminal_results_and_honors_no_color(self):
        self.env.pop("NO_COLOR")
        for status, color, message in (
            (0, b"32", b"Reachable: pkg-host"),
            (255, b"31", b"pkg: SSH check failed for pkg-host (exit 255)"),
        ):
            with self.subTest(status=status):
                self.env["SSH_STATUS"] = str(status)
                plain = self.run_pkg("ping", "pkg-host")
                self.assertNotIn("\033", plain.stdout + plain.stderr)
                master, terminal = pty.openpty()
                self.addCleanup(os.close, master)
                self.addCleanup(os.close, terminal)
                result = self.run_pkg("ping", "pkg-host", output=terminal)
                self.assertEqual(result.returncode, status)
                self.assertIn(b"\x1b[" + color + b"m" + message + b"\x1b[0m",
                              os.read(master, 4096))
                self.env["NO_COLOR"] = "1"
                self.run_pkg("ping", "pkg-host", output=terminal)
                self.assertEqual(os.read(master, 4096).rstrip(b"\r\n"), message)
                del self.env["NO_COLOR"]

    def test_explicit_target_outside_workspace_and_localhost(self):
        with tempfile.TemporaryDirectory() as outside:
            result = self.run_pkg("ping", "apt@old_shrine", cwd=outside)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.log.read_text().splitlines()[-2], "apt@old_shrine")
            self.log.unlink()
            result = self.run_pkg("ping", "localhost", cwd=outside, debug=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("pkg.debug.host.transport=local", result.stderr)
            self.assertFalse(self.log.exists())

    def test_ambiguous_host_prompts_only_in_terminal(self):
        self.run_pkg("host", "add", "pkg-host")
        self.run_pkg("host", "add", "apt@old_shrine")
        self.assertEqual(self.run_pkg("ping").returncode, 1)
        self.assertFalse(self.log.exists())
        master, terminal = pty.openpty()
        self.addCleanup(os.close, master)
        self.addCleanup(os.close, terminal)
        os.write(master, b"pkg-host\n")
        result = self.run_pkg("ping", stdin=terminal)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Available hosts:", result.stderr)
        self.assertEqual(self.log.read_text().splitlines()[-2], "pkg-host")

    def test_registration_keeps_create_add_and_build_local(self):
        self.run_pkg("host", "add", "pkg-host")
        self.env["SSH_STATUS"] = "255"
        self.assertEqual(self.run_pkg("create", "hello").returncode, 0)
        source = self.root / "hello"
        source.write_text("#!/bin/sh\necho hello\n")
        source.chmod(0o755)
        self.assertEqual(self.run_pkg("add", "./hello").returncode, 0)
        result = self.run_pkg("build", "hello")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.root / "dist/hello_0.0.0_all.deb").is_file())
        self.assertFalse(self.log.exists())

    def test_duplicate_registration_is_atomic(self):
        with ThreadPoolExecutor(2) as pool:
            results = list(pool.map(lambda _: self.run_pkg("host", "add", "pkg-host"), range(2)))
        self.assertEqual(sorted(result.returncode for result in results), [0, 1])
        self.assertEqual(self.run_pkg("hosts").stdout, "pkg-host\n")

    def test_invalid_input_and_storage(self):
        for target in ("", "../escape", "-oProxyCommand=bad", "host path", "host\nother"):
            self.assertEqual(self.run_pkg("host", "add", target).returncode, 2)
            self.assertEqual(self.run_pkg("ping", target).returncode, 2)
        self.assertEqual(self.run_pkg("ping").returncode, 1)
        self.assertFalse(self.log.exists())
        (self.root / ".pkg/hosts").symlink_to(self.root, target_is_directory=True)
        self.assertEqual(self.run_pkg("host", "add", "pkg-host").returncode, 1)
        self.assertFalse((self.root / "pkg-host").exists())

    def test_help(self):
        for command in ("host", "hosts", "ping"):
            result = self.run_pkg("help", command) if BINARY else self.run_pkg(command, "help")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("Usage:", result.stdout)
