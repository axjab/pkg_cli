from concurrent.futures import ThreadPoolExecutor
import gzip
import hashlib
import os
from pathlib import Path
import pty
import shlex
import shutil
import subprocess
import tempfile
import unittest

LIB = Path(__file__).resolve().parents[1] / 'lib'
BINARY = os.environ.get('PKG_TEST_BINARY')

class PushTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='pkg push ')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.home = self.root / 'remote home'
        self.home.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), GNUPGHOME=str(self.home / '.gnupg'), NO_COLOR='1')
        self.env.pop('PKG_DEBUG', None)
        if os.environ.get('PKG_TEST_FAKE_GPG') == '1':
            self.install_gpg_fixture()
        else:
            self.addCleanup(self.stop_gpg_agent)
        self.call('init')
        self.call('create', 'hello')
        self.call('build')
        self.call('host', 'add', 'localhost')

    def call(self, command, *args, stdin=subprocess.DEVNULL):
        argv = [BINARY, command] if BINARY else [str(LIB / ('pkg-' + command))]
        return subprocess.run(argv + list(args), env=self.env, cwd=self.root, stdin=stdin,
                              capture_output=True, text=True, timeout=20)

    def install_gpg_fixture(self):
        tools = self.root / 'fake-gpg'
        tools.mkdir()
        gpg = tools / 'gpg'
        gpg.write_text('''#!/usr/bin/env python3
import hashlib, os, sys
from pathlib import Path
args = sys.argv[1:]
keyhome = Path(os.environ['GNUPGHOME'])
if '--quick-generate-key' in args:
    name = args[args.index('--quick-generate-key') + 1]
    keyhome.mkdir(mode=0o700, exist_ok=True)
    (keyhome / name).touch(exist_ok=False)
elif '--list-secret-keys' in args:
    for key in sorted(keyhome.iterdir()):
        print('sec:::::::::::S:')
        print('fpr:::::::::' + hashlib.sha1(key.name.encode()).hexdigest().upper() + ':')
elif '--show-keys' in args:
    print('pub:::::::::::S:')
    print('fpr:::::::::' + '1' * 40 + ':')
elif '--output' in args:
    output = Path(args[args.index('--output') + 1])
    if '--clearsign' in args:
        output.write_bytes(Path(args[-1]).read_bytes())
    else:
        output.write_text('fixture')
elif '--export' in args:
    print('fixture')
''')
        gpg.chmod(0o755)
        self.env['PATH'] = f"{tools}:{self.env['PATH']}"

    def stop_gpg_agent(self):
        if Path(self.env['GNUPGHOME']).is_dir():
            subprocess.run(['gpgconf', '--kill', 'gpg-agent'], env=self.env,
                           capture_output=True, timeout=20)

    def key(self, name='Test One'):
        keyhome = Path(self.env['GNUPGHOME'])
        keyhome.mkdir(mode=0o700, exist_ok=True)
        result = subprocess.run(['gpg', '--batch', '--pinentry-mode', 'loopback',
                                 '--passphrase', '', '--quick-generate-key', name,
                                 'ed25519', 'sign', 'never'], env=self.env,
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)

    def failed(self, result, message, status=1):
        self.assertEqual(result.returncode, status, result.stderr)
        self.assertIn(message, result.stderr)
        self.assertEqual(result.stdout, '')
        self.assertFalse(list(self.home.glob('.pkg-preflight.*')))
        self.assertFalse((self.home / 'dists/trixie/InRelease').exists())
        self.assertFalse(list(self.home.glob('pool/main/*.deb')))

    def test_help(self):
        result = self.call('help', 'push') if BINARY else self.call('push', 'help')
        self.assertEqual(result.returncode, 0)
        self.assertIn('signed trixie APT', result.stdout)

    def test_missing_archive(self):
        next((self.root / '.pkg/archives').glob('*.deb')).unlink()
        self.failed(self.call('push'), 'Run pkg build hello first')

    def test_ambiguous_archive(self):
        control=self.root / '.pkg/packages/hello/DEBIAN/control'
        control.write_text(control.read_text().replace('0.0.0','0.0.1'))
        self.call('build')
        self.failed(self.call('push'), 'multiple built archives')

    def test_ambiguous_package_and_host(self):
        self.call('create','world')
        self.failed(self.call('push'), 'multiple packages')
        self.call('host','add','remote')
        self.failed(self.call('push','hello'), 'multiple hosts')

    def test_concurrent_first_push_creates_one_key_and_retry_reuses_it(self):
        self.env['PKG_DEBUG'] = '1'
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda _: self.call('push'), range(2)))
        for result in results:
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('Published hello_0.0.0_all.deb', result.stderr)
        self.assertEqual(sum('push.signing_key_created=true' in r.stderr for r in results), 1)
        self.assertTrue(Path(self.env['GNUPGHOME']).is_dir())
        retry = self.call('push')
        self.assertEqual(retry.returncode, 0, retry.stderr)
        self.assertNotIn('push.signing_key_created', retry.stderr)
        self.assertFalse(list(self.home.glob('.pkg-preflight.*')))
        self.assertEqual(len(list(self.home.glob('pool/main/*.deb'))), 1)
        self.assertTrue((self.home / 'dists/trixie/InRelease').is_file())

    def test_invalid_home(self):
        self.env['HOME']=str(self.home / 'missing')
        self.failed(self.call('push'), 'invalid target home')

    def test_signed_repository_requires_public_key(self):
        d=self.home / 'dists/trixie'
        d.mkdir(parents=True)
        (d / 'InRelease').write_text('old')
        result=self.call('push')
        self.assertEqual(result.returncode,1)
        self.assertIn('requires its public key',result.stderr)
        self.assertEqual((d / 'InRelease').read_text(),'old')
        self.assertFalse(Path(self.env['GNUPGHOME']).exists())

    def test_existing_public_key_requires_original_keyring(self):
        public_key = self.home / 'apt-signing-key.asc'
        public_key.write_text('existing key')
        self.failed(self.call('push'), 'restore the GPG keyring')
        self.assertEqual(public_key.read_text(), 'existing key')
        self.assertFalse(Path(self.env['GNUPGHOME']).exists())

    def test_ambiguous_keys(self):
        self.key()
        self.key('Test Two')
        self.failed(self.call('push'), 'exactly one repository signing key')

    def test_success_and_public_key_selection(self):
        self.key()
        self.env['PKG_DEBUG']='1'
        result=self.call('push')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(result.stdout,'')
        self.assertIn('Published hello_0.0.0_all.deb', result.stderr)
        self.assertIn('push.signature_verified=true',result.stderr)
        self.assertIn('push.transfer_verified=true',result.stderr)
        self.assertNotIn('\033',result.stderr)
        self.assertFalse(list(self.home.glob('.pkg-preflight.*')))
        public_key = self.home / 'apt-signing-key.asc'
        self.assertTrue(public_key.is_file())
        self.assertEqual(public_key.stat().st_mode & 0o777, 0o644)
        self.assertTrue((self.home / 'dists/trixie/InRelease').is_file())
        exported=subprocess.run(['gpg','--armor','--export','Test One'],env=self.env,capture_output=True,check=True).stdout
        (self.home/'apt-signing-key.asc').write_bytes(exported)
        self.key('Test Two')
        result=self.call('push','hello','to','localhost')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual((self.home/'apt-signing-key.asc').read_bytes(),exported)

    def test_metadata_indexes_existing_packages_and_hashes(self):
        pool = self.home / 'pool/main/nested'
        pool.mkdir(parents=True)
        self.assertEqual(self.call('create', 'existing').returncode, 0)
        control = self.root / '.pkg/packages/existing/DEBIAN/control'
        template = control.read_text()
        for version, arch in [('1.0', 'amd64'), ('2.0', 'amd64'), ('3.0', 'arm64')]:
            control.write_text(template.replace('0.0.0', version).replace('Architecture: all', f'Architecture: {arch}'))
            result = self.call('build', 'existing', 'to', str(pool))
            self.assertEqual(result.returncode, 0, result.stderr)

        stage = self.root / 'metadata staging'
        stage.mkdir()
        incoming = stage / 'incoming.deb'
        original = self.root / '.pkg/archives/hello_0.0.0_all.deb'
        shutil.copyfile(original, incoming)
        result = subprocess.run(
            ['bash', '-euc', '''
                fail() { printf '%s\\n' "$1" >&2; exit 1; }
                pkg_debug() { :; }
                source "$1"
                prepare_metadata "$2" "$3" "$4"
            ''', 'metadata', str(LIB / 'push-metadata.sh'), str(self.home),
             str(stage), str(incoming)],
            capture_output=True, text=True, timeout=20,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        release_dir = stage / 'dists/trixie'
        indexes = release_dir / 'main/binary-amd64'
        raw = (indexes / 'Packages').read_bytes()
        self.assertEqual(gzip.decompress((indexes / 'Packages.gz').read_bytes()), raw)
        filenames = [line.split(': ', 1)[1] for line in raw.decode().splitlines()
                     if line.startswith('Filename: ')]
        self.assertCountEqual(filenames, [
            'pool/main/hello_0.0.0_all.deb',
            'pool/main/nested/existing_1.0_amd64.deb',
            'pool/main/nested/existing_2.0_amd64.deb',
        ])
        for filename in filenames:
            digest = hashlib.sha256((stage / filename).read_bytes()).hexdigest()
            self.assertIn(f'SHA256: {digest}', raw.decode())
        release = (release_dir / 'Release').read_text()
        self.assertIn('Architectures: amd64', release)
        hashes = release.split('SHA256:\n', 1)[1].splitlines()
        self.assertEqual(len(hashes), 2)
        for line in hashes:
            digest, size, path = line.split()
            data = (release_dir / path).read_bytes()
            self.assertEqual((digest, int(size)), (hashlib.sha256(data).hexdigest(), len(data)))
        self.assertEqual(len(list(pool.glob('*.deb'))), 3)
        self.assertFalse((self.home / 'dists').exists())

    def test_metadata_reuses_identical_pool_archive_and_rejects_conflict(self):
        pool = self.home / 'pool/main'
        pool.mkdir(parents=True)
        existing = pool / 'hello_0.0.0_all.deb'
        original = self.root / '.pkg/archives' / existing.name
        shutil.copyfile(original, existing)
        release = self.home / 'dists/trixie/Release'
        release.parent.mkdir(parents=True)
        release.write_text('existing release')
        result = self.call('push')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Published hello_0.0.0_all.deb', result.stderr)
        self.assertEqual(existing.read_bytes(), original.read_bytes())
        published_release = release.read_bytes()
        self.assertNotEqual(published_release, b'existing release')
        existing.write_bytes(original.read_bytes() + b'conflict')
        result = self.call('push')
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('different archive already exists', result.stderr)
        self.assertEqual(existing.read_bytes(), original.read_bytes() + b'conflict')
        self.assertEqual(release.read_bytes(), published_release)
        self.assertFalse(list(self.home.glob('.pkg-preflight.*')))

    def test_ssh_failure_preserves_status(self):
        tools=self.root/'tools'; tools.mkdir()
        ssh=tools/'ssh'; ssh.write_text('#!/bin/sh\nexit 255\n'); ssh.chmod(0o755)
        self.env['PATH']=str(tools)+':'+self.env['PATH']
        self.failed(self.call('push','to','apt@some-host'), 'exit 255',255)

    def test_ssh_transfers_binary_archive_and_rejects_truncation(self):
        self.key()
        tools = self.root / 'ssh-fixture'
        tools.mkdir()
        ssh = tools / 'ssh'
        ssh.write_text('''#!/bin/bash
if [[ ${TRUNCATE_ARCHIVE:-0} == 1 ]]; then
    head -c 32 | sh -c "${!#}"
else
    exec sh -c "${!#}"
fi
''')
        ssh.chmod(0o755)
        self.env['PATH'] = f"{tools}:{self.env['PATH']}"
        result = self.call('push', 'hello', 'to', 'apt@some-host')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, '')
        self.assertIn('Published hello_0.0.0_all.deb to apt@some-host', result.stderr)
        self.assertFalse(list(self.home.glob('.pkg-preflight.*')))
        release = self.home / 'dists/trixie/InRelease'
        published_release = release.read_bytes()
        self.env['TRUNCATE_ARCHIVE'] = '1'
        result = self.call('push', 'hello', 'to', 'apt@some-host')
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('archive SHA-256 mismatch', result.stderr)
        self.assertEqual(release.read_bytes(), published_release)
        self.assertFalse(list(self.home.glob('.pkg-preflight.*')))

    def test_interactive_host(self):
        self.key()
        self.call('host','add','remote')
        master,slave=pty.openpty()
        try:
            os.write(master,b'localhost\n')
            result=self.call('push',stdin=slave)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertIn('Available hosts',result.stderr)
        finally:
            os.close(master); os.close(slave)

    def test_invalid_host_and_arguments(self):
        self.failed(self.call('push','hello','to','-bad'), 'expected an SSH alias',2)
        self.failed(self.call('push','hello','to','localhost','extra'), 'Usage',2)

    def test_invalid_archive(self):
        next((self.root/'dist').glob('*.deb')).write_text('bad')
        self.failed(self.call('push'), 'invalid archive')

    def test_probe_write_failure(self):
        tools=self.root/'tools'; tools.mkdir()
        wrapper=tools/'mktemp'
        wrapper.write_text('#!/bin/bash\nif [[ "$*" == *pkg-preflight* ]]; then exit 1; fi\nexec /usr/bin/mktemp "$@"\n')
        wrapper.chmod(0o755)
        self.env['PATH']=str(tools)+':'+self.env['PATH']
        self.failed(self.call('push'), 'cannot write to repository')

    def test_sign_and_verification_failure_cleanup(self):
        self.key()
        original = shutil.which('gpg', path=self.env['PATH'])
        self.assertIsNotNone(original)
        tools = self.root / 'broken-gpg'
        tools.mkdir()
        wrapper = tools / 'gpg'
        self.env['PATH'] = f"{tools}:{self.env['PATH']}"

        for operation, message in [
            ('--clearsign', 'could not sign without a prompt'),
            ('--verify', 'signature verification failed'),
        ]:
            with self.subTest(operation=operation):
                wrapper.write_text(
                    '#!/bin/bash\n'
                    'for arg in "$@"; do\n'
                    f'    [[ $arg != {shlex.quote(operation)} ]] || exit 2\n'
                    'done\n'
                    f'exec {shlex.quote(original)} "$@"\n'
                )
                wrapper.chmod(0o755)
                self.failed(self.call('push'), message)

    def test_update_retains_previous_hashes_and_pool_files(self):
        result = self.call('push')
        self.assertEqual(result.returncode, 0, result.stderr)
        suite = self.home / 'dists/trixie'
        index = suite / 'main/binary-amd64'
        first = (index / 'Packages').read_bytes()
        first_hash = hashlib.sha256(first).hexdigest()
        public_key = self.home / 'apt-signing-key.asc'
        original_key = public_key.read_bytes()
        (suite / 'unrelated').write_text('preserve me')

        self.assertEqual(self.call('create', 'world').returncode, 0)
        result = self.call('build', 'world')
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.call('push', 'world')
        self.assertEqual(result.returncode, 0, result.stderr)
        packages = (index / 'Packages').read_bytes()
        self.assertIn(b'Package: hello', packages)
        self.assertIn(b'Package: world', packages)
        self.assertEqual((index / 'by-hash/SHA256' / first_hash).read_bytes(), first)
        self.assertEqual(public_key.read_bytes(), original_key)
        self.assertEqual((suite / 'unrelated').read_text(), 'preserve me')
        self.assertEqual(len(list(self.home.glob('pool/main/*.deb'))), 2)

    def test_failed_suite_exchange_rolls_back_new_archive(self):
        first = self.call('push')
        self.assertEqual(first.returncode, 0, first.stderr)
        release = self.home / 'dists/trixie/InRelease'
        published_release = release.read_bytes()
        self.assertEqual(self.call('create', 'world').returncode, 0)
        self.assertEqual(self.call('build', 'world').returncode, 0)
        original = shutil.which('mv', path=self.env['PATH'])
        tools = self.root / 'activation-failure'
        tools.mkdir()
        wrapper = tools / 'mv'
        wrapper.write_text(
            '#!/bin/bash\n'
            '[[ $1 != --exchange ]] || exit 1\n'
            f'exec {shlex.quote(original)} "$@"\n'
        )
        wrapper.chmod(0o755)
        self.env['PATH'] = f"{tools}:{self.env['PATH']}"
        result = self.call('push', 'world')
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('could not exchange', result.stderr)
        self.assertEqual(release.read_bytes(), published_release)
        self.assertEqual([p.name for p in self.home.glob('pool/main/*.deb')], ['hello_0.0.0_all.deb'])
        self.assertTrue((self.home / 'apt-signing-key.asc').is_file())
        self.assertFalse(list(self.home.glob('.pkg-preflight.*')))
