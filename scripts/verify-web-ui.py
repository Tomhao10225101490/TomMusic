#!/usr/bin/env python3
"""Bounded real in-app public video playback, not an original-recording/download claim.
Requires Accessibility and the compiled ui-input helper; uses only copied test profiles.
"""
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

project = Path(__file__).resolve().parent.parent
evidence = project / 'evidence'
m = json.loads((evidence / 'acceptance-path.json').read_text())
old = json.loads((evidence / 'acceptance-1.1.json').read_text())
original = Path(old.get('ui_data', old['data']))
profile = Path(tempfile.mkdtemp(prefix='WebPlayerUI-', dir=m['root']))
shutil.copytree(original, profile, dirs_exist_ok=True)
original_bytes = (original / 'Library.json').read_bytes()
helper = project / '.build/ui-input'
checks = []
report = {'passed': False, 'app': m['app'], 'binary_sha256': m['binary_sha256'], 'profile': str(profile), 'checks': checks,
          'source': 'https://www.bilibili.com/video/BV1JV62BaEVo/', 'version': 'User upload explicitly titled 剪辑版, 243 s; NOT verified official album original',
          'original_album_download_verified': False}

def command(args):
    return subprocess.check_output([str(a) for a in args], text=True, timeout=15).strip()

def ax(script):
    return command(['osascript', '-e', 'tell application "System Events" to tell process "TomMusic"\n' + script + '\nend tell'])

def texts():
    return ax('return value of static texts of group 1 of window "Tom Music"')

def wait(predicate, seconds=35):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(.5)
    raise TimeoutError(f'UI wait stopped at {seconds}s bound')

def check(value, label, detail=None):
    if not value:
        raise AssertionError((label, detail))
    checks.append({'check': label, 'detail': detail})
    print('PASS:', label, detail or '', flush=True)

def field(value):
    x, y = map(float, ax('return position of text field 1 of group 1 of window "Tom Music"').split(','))
    command([helper, 'click', x + 20, y + 8])
    ax('keystroke "a" using command down\nkey code 51')
    command([helper, 'type', value])
    ax('key code 36')

def clock():
    match = re.search(r'网页音频(播放中|已暂停) · (\d+):(\d+) / (\d+):(\d+)', texts())
    return (match[1], 60*int(match[2])+int(match[3]), 60*int(match[4])+int(match[5])) if match else None

def capture(name):
    line = next(l for l in command([helper, 'windows']).splitlines() if l.endswith('Tom Music'))
    command(['screencapture', '-x', '-l', line.split()[0], '-t', 'png', evidence / name])

previous_input = command([helper, 'input-source'])
try:
    command([helper, 'input-source', 'com.apple.keylayout.ABC'])
    command(['open', '-n', m['app'], '--args', '--data-dir', profile])
    wait(lambda: ax('return exists window "Tom Music"') == 'true', 10)
    ax('set size of window "Tom Music" to {1180, 820}')
    x, y = map(float, ax('return position of window "Tom Music"').split(','))
    command([helper, 'click', x + 65, y + 137])
    wait(lambda: '全网音乐发现' in texts(), 5)
    ax('click radio button 3 of radio group "发现方式" of group 1 of window "Tom Music"')
    wait(lambda: ax('return description of text field 1 of group 1 of window "Tom Music"') == '站内听歌搜索', 5)
    time.sleep(.2)
    check('站内网页播放器' in texts(), 'Web mode displays distinct transport, not stale local-track playback controls')
    field('BTS FAKE LOVE MV')
    wait(lambda: '已打开来源页面' in texts(), 35)
    state = ax('return entire contents of window "Tom Music"')
    check('FAKE LOVE' in state and 'bilibili' in state.lower(), 'Real platform keyword search renders inside app without an Apple account or API key')
    capture('ui-web-search.png')
    field(report['source'])
    started = time.monotonic()
    wait(lambda: clock() and clock()[0] == '播放中' and clock()[1] >= 3, 35)
    first = clock()
    check(first[2] == 243 and '来源播放器静音' not in texts(), 'Selected real FAKE LOVE edited video plays unmuted in app; not a preview or another song', first)
    capture('ui-web-playing.png')
    ax('click (first button of group 1 of window "Tom Music" whose help is "暂停网页")')
    wait(lambda: clock() and clock()[0] == '已暂停', 5)
    at = clock()[1]
    time.sleep(2)
    check(clock()[1] == at, 'Native pause button actually stops the platform media clock', at)
    ax('click (first button of group 1 of window "Tom Music" whose help is "继续网页")')
    wait(lambda: clock() and clock()[0] == '播放中' and clock()[1] > at + 1, 8)
    check(True, 'Native continue resumes the same public video')
    ax('set size of window "Tom Music" to {980, 640}')
    time.sleep(.6)
    capture('ui-web-minimum.png')
    check('网页音频播放中' in texts(), 'Minimum 980x640 window keeps visible source player, status and native transport')
    ax('set size of window "Tom Music" to {1180, 820}')
    # No seeking: exercise actual playback beyond preview/trial boundaries to the natural end.
    samples = []
    deadline = started + 315
    while time.monotonic() < deadline:
        value = clock()
        if value:
            samples.append({'elapsed': round(time.monotonic() - started, 1), 'state': value[0], 'seconds': value[1], 'duration': value[2]})
            if value[1] >= 242:
                break
        time.sleep(4)
    final = clock()
    report['actual_playback_samples'] = samples
    report['elapsed_seconds'] = round(time.monotonic() - started, 2)
    check(final and final[1] >= 242 and report['elapsed_seconds'] >= 235, 'Actual 243-second selected video reaches the end without seeking or substituting audio', final)
    capture('ui-web-ended.png')
    check((profile / 'Library.json').read_bytes() == original_bytes, 'Online web listening does not import a file or mutate old tracks, favorites, playlists or volume')
    check((original / 'Library.json').read_bytes() == original_bytes, 'Original test profile remains byte-for-byte untouched')
    field('https://127.0.0.1/private.mp3')
    wait(lambda: '这里只接受' in texts(), 3)
    check(True, 'Native web URL field rejects private/unsupported targets without navigating')
    ax('click radio button 1 of radio group "发现方式" of group 1 of window "Tom Music"')
    wait(lambda: '站内网页播放器 · 使用上方' not in texts(), 5)
    check(True, 'Leaving web mode stops/removes its player and restores native local controls')
    report['passed'] = True
finally:
    if not report['passed']:
        try:
            capture('ui-web-failure.png')
            (evidence / 'ui-web-failure-tree.txt').write_text(ax('return entire contents of window "Tom Music"'))
        except Exception:
            pass
    command([helper, 'input-source', previous_input])
    (evidence / 'web-ui-test-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
    m['web_ui_data'] = str(profile)
    (evidence / 'acceptance-path.json').write_text(json.dumps(m, indent=2))
