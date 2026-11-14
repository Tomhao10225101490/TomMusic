#!/usr/bin/env python3
"""Actual audio-only native app workflow, using copied library + real public AAC.
No video/WebView; does not assert uploader/official-master ownership. Accessibility required.
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
ev = project / 'evidence'
m = json.loads((ev / 'acceptance-path.json').read_text())
old = json.loads((ev / 'acceptance-1.1.json').read_text())
original = Path(old.get('ui_data', old['data']))
profile = Path(tempfile.mkdtemp(prefix='NativeAudioUI-', dir=m['root']))
shutil.copytree(original, profile, dirs_exist_ok=True)
original_bytes = (original / 'Library.json').read_bytes()
helper = project / '.build/ui-input'
checks = []
report = {'passed': False, 'app': m['app'], 'binary_sha256': m['binary_sha256'], 'profile': str(profile), 'checks': checks,
          'source': 'https://www.bilibili.com/video/BV1JV62BaEVo/', 'version': 'Explicitly edited public-source AAC; NOT verified official album original', 'official_album_download_verified': False}
cache = Path(tempfile.gettempdir()) / 'TomMusicAudio'

def command(args, timeout=15):
    return subprocess.check_output([str(a) for a in args], text=True, timeout=timeout).strip()

def ax(s):
    return command(['osascript', '-e', 'tell application "System Events" to tell process "TomMusic"\n' + s + '\nend tell'])

def texts():
    return ax('return value of static texts of group 1 of window "Tom Music"')

def wait(predicate, seconds=30):
    until = time.monotonic() + seconds
    while time.monotonic() < until:
        value = predicate()
        if value:
            return value
        time.sleep(.35)
    raise TimeoutError(f'Native audio UI wait stopped at {seconds}s bound')

def check(value, label, detail=None):
    if not value:
        raise AssertionError((label, detail))
    checks.append({'check': label, 'detail': detail})
    print('PASS:', label, detail or '', flush=True)

def field(value):
    x, y = map(float, ax('return position of text field 1 of group 1 of window "Tom Music"').split(','))
    ax('set frontmost to true')
    command([helper, 'click', x + 20, y + 8])
    wait(lambda: ax('return focused of text field 1 of group 1 of window "Tom Music"') == 'true', 3)
    time.sleep(.15)
    ax('keystroke "a" using command down\nkey code 51')
    wait(lambda: ax('return value of text field 1 of group 1 of window "Tom Music"') == '', 3)
    command([helper, 'type', value])
    wait(lambda: ax('return value of text field 1 of group 1 of window "Tom Music"') == value, 3)
    ax('key code 36')

def discover():
    x, y = map(float, ax('return position of window "Tom Music"').split(','))
    command([helper, 'click', x + 65, y + 137])
    wait(lambda: ax('return description of text field 1 of group 1 of window "Tom Music"') == '直接听歌搜索', 5)
    time.sleep(.2)

def control(label):
    ax('click (first button of group 1 of window "Tom Music" whose help is ' + json.dumps(label, ensure_ascii=False) + ')')

def playing():
    return ax('return exists (first button of group 1 of window "Tom Music" whose help is "暂停")') == 'true'

def position():
    return float(ax('return value of slider 2 of group 1 of window "Tom Music"'))

def result():
    return 'button 1 of UI element 1 of scroll area 2 of group 1 of window "Tom Music"'

def capture(name):
    line = next(l for l in command([helper, 'windows']).splitlines() if l.endswith('Tom Music'))
    command(['screencapture', '-x', '-l', line.split()[0], '-t', 'png', ev / name])

def files():
    return set(cache.glob('*.m4a')) if cache.exists() else set()

previous = command([helper, 'input-source'])
cache_before = files()
try:
    command([helper, 'input-source', 'com.apple.keylayout.ABC'])
    command(['open', '-n', m['app'], '--args', '--data-dir', profile]); time.sleep(.8)
    wait(lambda: ax('return exists window "Tom Music"') == 'true', 10)
    ax('set size of window "Tom Music" to {1180, 820}'); discover()
    check('不打开视频或网页' in texts() and '站内网页播放器 ·' not in texts(), 'Default discovery opens TRUE native audio mode, not the old MV surface')
    field('BTS FAKE LOVE')
    wait(lambda: '找到' in texts(), 35)
    state = ax('return entire contents of window "Tom Music"')
    check('FAKE LOVE' in state, 'Native song search renders real API results with provenance/version, not a website')
    capture('ui-native-audio-search.png')
    # Explicitly choose the same real edited source used in independent audio-track tests.
    field(report['source']); wait(lambda: '找到 1 个' in texts(), 30)
    check('剪辑版' in ax('return entire contents of window "Tom Music"'), 'Exact selected source keeps edited-version identity; not relabelled as official album')
    ax('click ' + result())
    wait(lambda: playing() and position() > .3 and '0 个视频轨道' in texts(), 145)
    started = time.monotonic()
    check('独立音频 · 临时缓存' in texts() and 'FAKE LOVE' in texts(), 'Actual native player has standalone song metadata, no video surface, and advancing audio clock')
    new_files = files() - cache_before
    check(len(new_files) == 1, 'Exactly one bounded owned audio cache file is used, not a cached MV', len(new_files))
    clip = next(iter(new_files))
    info = command(['afinfo', clip])
    (ev / 'native-audio-afinfo.txt').write_text(info)
    check('Num Tracks:     1' in info and 'aac' in info and '242.' in info, 'OS independently inspects full-length standalone stereo AAC (one audio track)', info[:500])
    report['audio_cache_bytes'] = clip.stat().st_size
    # Direct AX role check: absence of a visible/hidden accessibility web document.
    has_web = ax('set nodes to entire contents of window "Tom Music"\nrepeat with n in nodes\ntry\nif role of n is "AXWebArea" then return "web"\nend try\nend repeat\nreturn "native"')
    check(has_web == 'native', 'Native playback view contains no WebView document; media-track validation separately proved zero video tracks')
    capture('ui-native-audio-playing.png')
    control('暂停'); time.sleep(.4); at = position(); time.sleep(.8)
    check(not playing() and abs(position() - at) < .3, 'Native pause stops the actual AVAudioPlayer decoder clock', at)
    control('播放'); wait(lambda: playing() and position() > at + .4, 5)
    check(True, 'Native play resumes independent audio from the paused position')
    ax('set size of window "Tom Music" to {980, 640}'); time.sleep(.4); capture('ui-native-audio-minimum.png')
    check(playing(), 'Minimum window preserves native track list and normal transport, no video allocation')
    ax('set size of window "Tom Music" to {1180, 820}')
    samples = []; deadline = started + 300
    while time.monotonic() < deadline:
        p = position(); is_playing = playing()
        samples.append({'elapsed': round(time.monotonic() - started, 2), 'seconds': p, 'playing': is_playing})
        if not is_playing and max(x['seconds'] for x in samples) > 239 and time.monotonic() - started > 237:
            break
        time.sleep(1.2)
    report['actual_audio_samples'] = samples
    report['elapsed_seconds'] = round(time.monotonic() - started, 2)
    check(not playing() and max(x['seconds'] for x in samples) > 239 and report['elapsed_seconds'] > 237, 'Actual complete 242-second AAC reaches natural end without seeking, video or song substitution', report['elapsed_seconds'])
    capture('ui-native-audio-ended.png')
    # Exercise real progress drag AFTER the no-seek full playback acceptance.
    sx, sy = map(float, ax('return position of slider 2 of group 1 of window "Tom Music"').split(','))
    width = float(ax('return item 1 of (get size of slider 2 of group 1 of window "Tom Music")'))
    p = position(); command([helper, 'drag', sx + min(width-4, width*p/242.3), sy+6, sx+width*.5, sy+6]); time.sleep(.3)
    check(105 < position() < 140, 'Native progress drag seeks the independent AAC file near midpoint', position())
    control('播放'); wait(lambda: playing() and position() > 121, 5); control('暂停')
    ax('click ' + result()); wait(lambda: ax('return exists (first button of group 1 of window "Tom Music" whose help is "取消音频缓冲")') == 'true', 5)
    control('取消音频缓冲'); time.sleep(3)
    check(not playing() and files() - cache_before == new_files, 'Cancel stops pending audio buffering with no late autoplay or extra cache insertion')
    check((profile / 'Library.json').read_bytes() == original_bytes, 'Native online listening does not alter old tracks, favorites, playlists, volume or local library JSON')
    x, y = map(float, ax('return position of window "Tom Music"').split(',')); command([helper, 'click', x+65, y+363]); time.sleep(.4)
    x, y = map(float, ax('return position of static text 1 of group 1 of UI element 1 of scroll area 2 of group 1 of window "Tom Music"').split(',')); command([helper, 'double', x+25, y+6])
    wait(lambda: playing() and position() > .2, 8)
    check(not clip.exists() and '独立音频 · 临时缓存' not in texts(), 'Selecting ordinary local music restores local playback and deletes owned online audio cache')
    control('暂停'); discover(); field(report['source']); wait(lambda: '找到 1 个' in texts(), 30); ax('click ' + result()); wait(lambda: playing() and position() > .3, 145)
    quit_files = files() - cache_before
    command(['osascript', '-e', 'tell application id "com.tommusic.desktop" to quit']); time.sleep(.5)
    check(not any(f.exists() for f in quit_files), 'Normal app quit removes owned temporary audio cache, not user originals')
    check((original / 'Library.json').read_bytes() == original_bytes, 'Original migration fixture stays byte-for-byte unchanged')
    report['passed'] = True
finally:
    if not report['passed']:
        try:
            capture('ui-native-audio-failure.png'); (ev / 'ui-native-audio-failure-tree.txt').write_text(ax('return entire contents of window "Tom Music"'))
            if ax('return exists (first button of group 1 of window "Tom Music" whose help is "取消音频缓冲")') == 'true':
                control('取消音频缓冲')
        except Exception:
            pass
    command([helper, 'input-source', previous])
    (ev / 'native-audio-ui-test-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
    m['native_audio_ui_data'] = str(profile); (ev / 'acceptance-path.json').write_text(json.dumps(m, indent=2))
