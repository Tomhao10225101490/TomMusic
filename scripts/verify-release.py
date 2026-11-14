#!/usr/bin/env python3
"""Exercise the final bundle copied outside the source tree; no user library access."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--extended', action='store_true', help='Generated codec/artwork/system metadata tests')
parser.add_argument('--network', action='store_true', help='Also exercise real Internet Archive search, licensed MP3 download and playback')
parser.add_argument('--discovery', action='store_true', help='Real five-source search, public-page parser, licensed ccMixter save and Audius streaming tests')
options = parser.parse_args()
project = Path(__file__).resolve().parent.parent
evidence = project / "evidence"
evidence.mkdir(exist_ok=True)
root = Path(tempfile.mkdtemp(prefix="tommusic-acceptance-"))
app = root / "Tom Music.app"
shutil.copytree(project / "dist/Tom Music.app", app)
binary = app / "Contents/MacOS/TomMusic"
data = root / "DiagnosticLibrary"
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True, timeout=15)
args = [str(binary), "--self-test", "--data-dir", str(data)]
if options.network:
    args.append('--network-test')
elif options.extended:
    args.append('--extended-test')
if options.discovery:
    args.append('--discovery-test')
result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                        text=True, timeout=240 if options.network else (210 if options.discovery else (120 if options.extended else 35)), cwd="/tmp")
(evidence / "self-test.log").write_text(result.stdout)
print(result.stdout, end="")
result.check_returncode()
shutil.copy2(data / "test-report.json", evidence / "test-report.json")
if options.extended or options.network:
    shutil.copy2(data / 'audio-route-report.json', evidence / 'audio-route-report.json')
# Refuse unisolated diagnostics before loading any default user data.
refused = subprocess.run([str(binary), "--self-test"], capture_output=True, text=True, timeout=10, cwd="/tmp")
assert refused.returncode == 2, "Unisolated self-test must refuse to run"
persisted = json.loads((data / "Library.json").read_text())
assert len(persisted["tracks"]) == (12 if options.network else (11 if options.extended else 1)) + int(options.discovery)
if options.discovery:
    shutil.copy2(data / 'discovery-report.json', evidence / 'discovery-report.json')
    assert any(t.get('origin', {}).get('provider') == 'ccMixter' for t in persisted['tracks'] if t.get('origin'))
if options.network:
    assert any(t.get('origin', {}).get('provider') == 'Internet Archive' for t in persisted['tracks'] if t.get('origin'))
    shutil.copy2(data / 'network-report.json', evidence / 'network-report.json')
assert len(persisted["playlists"][0]["trackIDs"]) == 1
assert abs(persisted["volume"] - 0.23) < 0.001
manifest = {"root": str(root), "app": str(app), "data": str(data),
            "extended": options.extended or options.network, "network": options.network, "discovery": options.discovery,
            "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
            "unisolated_diagnostics_refused": True,
            "on_disk_library_assertions": "passed",
            "ui_interaction": "not verified by this script; requires Accessibility permission"}
(evidence / "acceptance-path.json").write_text(json.dumps(manifest, indent=2))
print("PASS: independent signed bundle, diagnostic isolation, on-disk persistence")
print("Isolated app:", app)
