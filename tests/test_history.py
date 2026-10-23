"""Exercise the real PHP CLI against a local release server and temporary boot files."""
import hashlib
import http.server
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.request
import unittest

ROOT = Path(__file__).resolve().parents[1]
KERNEL = '6.18.54-Unraid'
OTHER_KERNEL = '6.18.58-Unraid'


class HistoryTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.boot = self.root / 'boot'
        self.boot.mkdir()
        self.settings = self.boot / 'settings.cfg'
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.kernel = KERNEL
        self.failed_path = None
        self.metadata_failure = False
        self.request_count = 0
        self.payloads = {}
        self.assets = []
        owner = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                owner.request_count += 1
                path = self.path.split('?')[0]
                if owner.metadata_failure or owner.failed_path == path:
                    self.send_response(500)
                    self.end_headers()
                    self.wfile.write(b'{"message":"test download failure"}')
                    return
                if '/tags/' in path:
                    data = json.dumps({'id': 1}).encode()
                elif path.endswith('/assets'):
                    page = int(self.path.split('page=')[-1])
                    data = json.dumps(owner.assets[(page - 1) * 100:page * 100]).encode()
                elif path == '/versions.json':
                    data = json.dumps({'branches': {'production': {'current': '580.20', 'last_prb': '580.19'}, 'newfeature': {'current': '590.30'}}}).encode()
                elif path in owner.payloads:
                    data = owner.payloads[path]
                else:
                    self.send_response(404)
                    self.end_headers()
                    return
                self.send_response(200)
                self.end_headers()
                self.wfile.write(data)

            def log_message(self, *_args):
                pass

        self.server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.url = 'http://127.0.0.1:' + str(self.server.server_port)
        source = (ROOT / 'source/usr/local/emhttp/plugins/nvidia-driver/include/driver-history.php').read_text()
        source = source.replace('/boot/config/plugins/nvidia-driver', str(self.boot))
        source = source.replace('/tmp/nvidia-driver-release-', str(self.root / 'release-'))
        source = source.replace('https://api.github.com/repos/unraid/unraid-nvidia-driver/releases', self.url + '/releases')
        source = source.replace('https://raw.githubusercontent.com/unraid/unraid-nvidia-driver/master/versions.json', self.url + '/versions.json')
        source = source.replace('/usr/local/emhttp/plugins/nvidia-driver/include/exec.sh', str(self.bin / 'change-check'))
        source = source.replace('/usr/local/emhttp/plugins/dynamix/scripts/notify', str(self.bin / 'notify'))
        self.php = self.root / 'driver-history.php'
        self.php.write_text(source)
        for name, body in {
            'uname': 'printf "%s\\n" "$TEST_KERNEL"',
            'nvidia-smi': 'echo 580.20',
            'modinfo': 'echo NVIDIA',
            'change-check': 'echo disabled >> "$TEST_CRON_LOG"',
            'notify': 'exit 0',
        }.items():
            path = self.bin / name
            path.write_text('#!/bin/sh\n' + body + '\n')
            path.chmod(0o755)
        self.settings.write_text('first_installation=false\ndriver_version=latest\nupdate_check=true\ndisable_xconfig=true\n')
        self.add_asset('580.20')
        self.add_asset('580.19')
        self.add_asset('580.19', 'nvos')
        self.add_asset('590.30')

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.temp.cleanup()

    def add_asset(self, version, kind='nvidia', kernel=KERNEL, revision=1):
        name = f'{kind}-{version}-{kernel}-{revision}.txz'
        data = ('driver ' + name).encode()
        self.payloads['/download/' + name] = data
        self.payloads['/download/' + name + '.md5'] = hashlib.md5(data).hexdigest().encode() + b'\n'
        for suffix in ('', '.md5'):
            self.assets.append({'name': name + suffix, 'size': len(self.payloads['/download/' + name + suffix]), 'browser_download_url': self.url + '/download/' + name + suffix})
        return name

    def environment(self):
        return dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'], TEST_KERNEL=self.kernel, TEST_CRON_LOG=str(self.root / 'cron.log'))

    def run_php(self, *args, success=True):
        env = self.environment()
        result = subprocess.run(['php', str(self.php), *args], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0 if success else 1, result.stdout + result.stderr)
        return result

    def package(self, name, kernel=KERNEL):
        return self.boot / 'packages' / kernel.split('-')[0] / name

    def put_local(self, name, kernel=KERNEL):
        path = self.package(name, kernel)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(self.payloads['/download/' + name])
        Path(str(path) + '.md5').write_bytes(self.payloads['/download/' + name + '.md5'])

    def test_fixed_open_package_survives_offline_boot_and_disables_updates(self):
        name = f'nvos-580.19-{KERNEL}-1.txz'
        self.run_php('download', name)
        cfg = self.settings.read_text()
        self.assertIn('driver_version=580.19', cfg)
        self.assertIn('driver_type=nvos', cfg)
        self.assertIn('update_check=false', cfg)
        self.assertIn('disable_xconfig=true', cfg)
        self.assertTrue((self.root / 'cron.log').is_file())
        self.metadata_failure = True
        self.assertEqual(self.run_php('boot').stdout, name)
        self.assertFalse(list(self.boot.rglob('*.part')))

    def test_failures_keep_settings_and_current_package(self):
        current = f'nvidia-580.20-{KERNEL}-1.txz'
        target = f'nvidia-580.19-{KERNEL}-1.txz'
        self.put_local(current)
        before = self.settings.read_bytes()
        self.failed_path = '/download/' + target
        self.run_php('download', target, success=False)
        self.assertEqual(self.settings.read_bytes(), before)
        self.assertTrue(self.package(current).is_file())
        self.assertFalse(self.package(target).is_file())
        self.assertFalse(list(self.boot.rglob('*.part')))
        self.failed_path = None
        self.payloads['/download/' + target + '.md5'] = b'0' * 32
        self.run_php('download', target, success=False)
        self.assertEqual(self.settings.read_bytes(), before)
        self.assertTrue(self.package(current).is_file())

    def test_absent_version_and_wrong_kernel_never_select_latest(self):
        before = self.settings.read_bytes()
        self.run_php('download', '470.256.02', success=False)
        self.run_php('download', f'nvidia-580.19-{OTHER_KERNEL}-1.txz', success=False)
        self.assertEqual(self.settings.read_bytes(), before)

    def test_boot_resolves_same_version_for_new_kernel(self):
        old = f'nvos-580.19-{KERNEL}-1.txz'
        self.run_php('download', old)
        new = self.add_asset('580.19', 'nvos', OTHER_KERNEL)
        self.kernel = OTHER_KERNEL
        self.assertEqual(self.run_php('boot').stdout, new)
        self.assertIn('driver_version=580.19', self.settings.read_text())
        self.assertIn('driver_kernel=' + OTHER_KERNEL, self.settings.read_text())

    def test_missing_new_kernel_build_preserves_fixed_selection(self):
        self.run_php('download', f'nvidia-580.19-{KERNEL}-1.txz')
        before = self.settings.read_bytes()
        self.kernel = OTHER_KERNEL
        self.run_php('boot', success=False)
        self.assertEqual(self.settings.read_bytes(), before)

    def test_latest_branches_and_automatic_staging(self):
        for selector, version, kind in [('latest', '590.30', 'nvidia'), ('latest_prb', '580.20', 'nvidia'), ('latest_nfb', '590.30', 'nvidia'), ('latest_nos', '580.19', 'nvos')]:
            self.run_php('download', selector)
            self.assertIn('driver_version=' + selector, self.settings.read_text())
            self.assertEqual(self.run_php('boot').stdout, f'{kind}-{version}-{KERNEL}-1.txz')
        self.run_php('download', 'latest')
        staged = self.add_asset('595.40')
        self.put_local(staged)
        self.run_php('stage', staged)
        self.assertEqual(self.run_php('boot').stdout, staged)
        self.assertIn('driver_version=latest', self.settings.read_text())

    def test_catalog_pagination_types_and_running_cache_retention(self):
        for minor in range(60):
            self.add_asset('570.' + str(minor))
        orphan = self.add_asset('560.10')
        self.assets = [a for a in self.assets if a['name'] != orphan + '.md5']
        self.add_asset('550.10', kernel=OTHER_KERNEL)
        current = f'nvidia-580.20-{KERNEL}-1.txz'
        obsolete = f'nvidia-590.30-{KERNEL}-1.txz'
        target = f'nvidia-580.19-{KERNEL}-1.txz'
        self.put_local(current)
        self.put_local(obsolete)
        self.run_php('download', target)
        cached = json.loads((self.root / ('release-' + KERNEL + '.json')).read_text())['rows']
        self.assertEqual(len(cached), 64)
        self.assertNotIn(orphan, [row['name'] for row in cached])
        self.assertEqual(cached[0]['version'], '590.30')
        self.assertTrue(self.package(current).is_file())
        self.assertTrue(self.package(target).is_file())
        self.assertFalse(self.package(obsolete).is_file())
        count = self.request_count
        self.run_php('download', target)
        self.assertEqual(self.request_count, count)  # cached catalog and verified package

    def test_http_catalog_status_and_refresh_failure(self):
        target = f'nvos-580.19-{KERNEL}-1.txz'
        self.run_php('download', target)
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            port = sock.getsockname()[1]
        process = subprocess.Popen(['php', '-S', f'127.0.0.1:{port}', '-t', str(self.root)], env=self.environment(), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        url = f'http://127.0.0.1:{port}/driver-history.php'
        try:
            for _ in range(50):
                try:
                    with urllib.request.urlopen(url, timeout=2) as response:
                        data = json.load(response)
                    break
                except urllib.error.URLError:
                    time.sleep(0.05)
            else:
                self.fail('PHP HTTP endpoint did not start')
            self.assertTrue(data['ok'])
            self.assertEqual(data['kernel'], KERNEL)
            selected = next(row for row in data['rows'] if row['name'] == target)
            self.assertTrue(selected['selected'])
            self.assertTrue(selected['cached'])
            self.assertFalse(selected['installed'])
            self.metadata_failure = True
            with urllib.request.urlopen(url + '?refresh=1', timeout=2) as response:
                stale = json.load(response)
            self.assertEqual(len(stale['rows']), 4)
            self.assertIn('上次获取', stale['notice'])
            (self.root / ('release-' + KERNEL + '.json')).unlink()
            with self.assertRaises(urllib.error.HTTPError) as caught:
                urllib.request.urlopen(url, timeout=2)
            self.assertEqual(caught.exception.code, 502)
        finally:
            process.terminate()
            process.wait(timeout=5)

    def test_existing_numeric_selection_boots_exact_local_version(self):
        name = f'nvidia-580.19-{KERNEL}-1.txz'
        self.put_local(name)
        self.settings.write_text('driver_version=580.19\nupdate_check=false\n')
        self.metadata_failure = True
        self.assertEqual(self.run_php('boot').stdout, name)


if __name__ == '__main__':
    if not shutil.which('php'):
        raise SystemExit('PHP CLI is required for these integration tests.')
    unittest.main(verbosity=2)
