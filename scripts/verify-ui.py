#!/usr/bin/env python3
"""Bounded native UI regression on the isolated running acceptance app.
Uses ui_data in the recorded evidence/acceptance-path.json. That profile must
contain imported UI Test Tone A/B fixtures and UI Acceptance Playlist, with A
favorited. Launch its standalone app with that profile and no current playback.
Never drives a production/default-library app. Requires user
Accessibility permission. Does not grant permissions or modify the system SDK.
"""
import json
from pathlib import Path
import subprocess
import time

project = Path(__file__).resolve().parent.parent
manifest = json.loads((project / 'evidence/acceptance-path.json').read_text())
profile = Path(manifest['ui_data'])
helper = project / '.build/ui-input'
checks = []

def command(args, timeout=12):
    return subprocess.run([str(a) for a in args], check=True, capture_output=True,
                          text=True, timeout=timeout).stdout.strip()

def ax(body):
    return command(['osascript', '-e', 'tell application "System Events" to tell process "TomMusic"\n' + body + '\nend tell'])

def check(condition, label, detail=None):
    if not condition:
        raise AssertionError(f'{label}: {detail}')
    checks.append({'check': label, 'detail': detail})
    print('PASS:', label, detail or '')

def data():
    return json.loads((profile / 'Library.json').read_text())

def texts():
    return ax('return value of static texts of group 1 of window "Tom Music"')

def point(expression):
    return [float(x.strip()) for x in ax('return position of ' + expression).split(',')]

def search(query):
    x, y = point('text field 1 of group 1 of window "Tom Music"')
    command([helper, 'double', x + 30, y + 6])
    ax('keystroke "a" using command down\nkey code 51\nkeystroke ' + json.dumps(query))
    time.sleep(0.3)

def control(help_text):
    ax('click (first button of group 1 of window "Tom Music" whose help is ' + json.dumps(help_text, ensure_ascii=False) + ')')

def row(n=1):
    return f'group {n} of UI element 1 of scroll area 2 of group 1 of window "Tom Music"'

def position():
    return float(ax('return value of slider 2 of group 1 of window "Tom Music"'))

processes = command(['ps', '-axo', 'command'])
check(any(str(manifest['app']).replace('/var/', '/private/var/', 1) in line and '--data-dir ' + str(profile) in line
          for line in processes.splitlines()), 'Safety: only isolated acceptance profile is being driven')
initial_source = command([helper, 'input-source'])
report = {'passed': False, 'checks': checks, 'profile': str(profile),
          'binary_sha256': manifest['binary_sha256'], 'audio': 'Generated 90-second sine-wave WAV fixtures only'}
try:
    # Test plain spaces separately from Chinese IME candidate-commit behavior.
    command([helper, 'input-source', 'com.apple.keylayout.ABC'])
    ax('set frontmost to true')
    search('Tone A')
    check('找到 1 首歌曲' in texts(), 'Focused search accepts spaces and filters to one song', texts())
    check('尚未播放' in texts(), 'Typing a space does not start playback')
    search('NoSuchTrack')
    check('没有找到这首旋律' in texts(), 'Search empty-result state')
    search('UI Test Tone')
    check('找到 2 首歌曲' in texts(), 'Search finds both imported tones')
    x, y = point('static text 1 of ' + row())
    command([helper, 'double', x + 30, y + 7])
    time.sleep(0.8)
    p1 = position()
    time.sleep(0.7)
    p2 = position()
    check(p2 > p1 + 0.3, 'Double-click row plays audio and UI progress advances', [p1, p2])
    control('暂停')
    p1 = position()
    time.sleep(0.7)
    p2 = position()
    check(abs(p2 - p1) < 0.3, 'Pause button holds UI progress', [p1, p2])
    sx, sy = point('slider 2 of group 1 of window "Tom Music"')
    width = float(ax('return item 1 of (get size of slider 2 of group 1 of window "Tom Music")'))
    command([helper, 'drag', sx + width * p2 / 90, sy + 6, sx + width * 0.5, sy + 6])
    time.sleep(0.3)
    check(38 < position() < 52, 'Mouse dragging seeks audio near midpoint', position())
    control('播放')
    control('下一首')
    time.sleep(0.3)
    check('UI Test Tone B' in texts(), 'Next button switches to second track')
    control('上一首')
    time.sleep(0.3)
    check('UI Test Tone A' in texts(), 'Previous button returns to first track')
    control('暂停')
    control('喜爱当前歌曲')
    check(not data()['tracks'][0]['favorite'], 'Favorite button can unset persisted favorite')
    control('喜爱当前歌曲')
    check(data()['tracks'][0]['favorite'], 'Favorite button persists favorite')
    # Open real context menu and add a song to an existing test playlist.
    x, y = point('static text 1 of ' + row())
    command([helper, 'right', x + 30, y + 7])
    ax('click menu item "UI Acceptance Playlist" of menu "添加到播放列表" of menu item "添加到播放列表" of menu 1 of group 1 of window "Tom Music"')
    check(len(data()['playlists'][0]['trackIDs']) == 1, 'Context menu adds to playlist without duplicates')
    command([helper, 'right', x + 30, y + 7])
    ax('click menu item "下一首播放" of menu 1 of group 1 of window "Tom Music"')
    control('待播清单')
    tree = ax('return entire contents of window "Tom Music"')
    check('关闭待播清单' in tree or '待播清单' in texts(), 'Queue panel opens after context-menu enqueue')
    control('待播清单')
    # Actual volume knob drag must persist after mouse-up.
    vx, vy = point('slider 1 of group 1 of window "Tom Music"')
    vw = float(ax('return item 1 of (get size of slider 1 of group 1 of window "Tom Music")'))
    v = float(ax('return value of slider 1 of group 1 of window "Tom Music"'))
    command([helper, 'drag', vx + vw * v, vy + 6, vx + vw * 0.3, vy + 6])
    time.sleep(0.3)
    check(0.15 < data()['volume'] < 0.45, 'Volume drag persists to isolated library', data()['volume'])
    report['passed'] = True
finally:
    command([helper, 'input-source', initial_source])
    (project / 'evidence/ui-test-report.json').write_text(json.dumps(report, indent=2, ensure_ascii=False))
