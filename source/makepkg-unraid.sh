#!/bin/bash
set -e

# Build the WebGUI plugin from this checkout; no installed Unraid system is needed.
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$REPO_DIR" <<'PY'
import hashlib
import io
from pathlib import Path
import re
import sys
import tarfile

repo = Path(sys.argv[1])
manifest = repo / 'nvidia-driver.plg'
xml = manifest.read_text(encoding='utf-8')
version = re.search(r'<!ENTITY version\s+"([^"]+)"', xml).group(1)
output = repo / 'packages' / ('nvidia-driver-' + version + '.txz')
source = repo / 'source'
plugin_dir = Path('usr/local/emhttp/plugins/nvidia-driver')
files = [(path, path.relative_to(source)) for path in sorted((source / plugin_dir).rglob('*')) if path.is_file()]
files.append((repo / 'architecture-mapping.json', plugin_dir / 'architecture-mapping.json'))

with tarfile.open(output, 'w:xz', format=tarfile.USTAR_FORMAT) as package:
    for path, target in files:
        content = path.read_bytes()
        info = tarfile.TarInfo(target.as_posix())
        info.size = len(content)
        info.mode = 0o755 if path.suffix == '.sh' else 0o644
        info.uid = info.gid = 0
        info.uname = info.gname = 'root'
        package.addfile(info, io.BytesIO(content))

# Unraid's existing plugin installer requires this MD5 value.
checksum = hashlib.md5(output.read_bytes()).hexdigest()
Path(str(output) + '.md5').write_text(checksum + '\n', encoding='utf-8')
xml = re.sub(r'(<!ENTITY md5\s+")[^"]+("\s*>)', lambda m: m[1] + checksum + m[2], xml)
manifest.write_text(xml, encoding='utf-8')
print('已构建：' + str(output))
PY
