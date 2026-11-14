#!/usr/bin/env python3
"""Package only the exact bundle already checked by verify-release.py."""
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess

project = Path(__file__).resolve().parent.parent
manifest = project / 'evidence/acceptance-path.json'
m = json.loads(manifest.read_text())
app = project / 'dist/Tom Music.app'
binary = app / 'Contents/MacOS/TomMusic'
assert hashlib.sha256(binary.read_bytes()).hexdigest() == m['binary_sha256'], 'Re-run final-byte acceptance after rebuilding'
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
version = info['CFBundleShortVersionString']
zipfile = project / f'dist/Tom Music-{version}-macOS-arm64.zip'
extract = Path(m['root']) / 'PackageExtract'
assert not extract.exists(), 'Use a fresh verify-release.py acceptance root; do not replace a running extracted bundle'
subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(zipfile)], check=True, timeout=60)
extract.mkdir()
subprocess.run(['ditto', '-x', '-k', str(zipfile), str(extract)], check=True, timeout=30)
extracted = extract / app.name
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(extracted)], check=True, timeout=15)

def hashes(root):
    return {str(f.relative_to(root)): hashlib.sha256(f.read_bytes()).hexdigest() for f in root.rglob('*') if f.is_file()}

assert hashes(app) == hashes(extracted), 'Extracted bytes differ'
sha = hashlib.sha256(zipfile.read_bytes()).hexdigest()
zipfile.with_suffix('.zip.sha256').write_text(sha + '  ' + zipfile.name + '\n')
m.update(model_app=m['app'], app=str(extracted), zip=str(zipfile), zip_sha256=sha)
manifest.write_text(json.dumps(m, indent=2))
report = dict(passed=True, app=str(extracted), version=version, build=info['CFBundleVersion'], zip=str(zipfile), zip_sha256=sha,
              binary_sha256=m['binary_sha256'], all_extracted_file_hashes_match=True, file_hashes=hashes(extracted),
              signature='local ad-hoc, verified; not notarized', ui='pending extracted-bundle user workflow')
(project / f'evidence/package-report-{version.rsplit(".", 1)[0]}.json').write_text(json.dumps(report, indent=2))
print('ZIP:', zipfile)
print('SHA256:', sha)
print('Independent app:', extracted)
