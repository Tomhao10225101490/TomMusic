#!/usr/bin/env python3
"""Exercise the ZIP-extracted native app against a copy of a 1.1 isolated profile.
Requires previously granted Accessibility permission and .build/ui-input.
Never changes original/user libraries, system routing, proxy, DNS or permissions.
"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

project = Path(__file__).resolve().parent.parent
evidence = project / 'evidence'
manifest = evidence / 'acceptance-path.json'
m = json.loads(manifest.read_text())
old_manifest = json.loads((evidence / 'acceptance-1.1.json').read_text())
old_profile = Path(old_manifest.get('ui_data', old_manifest['data']))
old_bytes = (old_profile / 'Library.json').read_bytes()
old = json.loads(old_bytes)
profile = Path(tempfile.mkdtemp(prefix='DiscoveryUI-', dir=m['root']))
shutil.copytree(old_profile, profile, dirs_exist_ok=True)
m['discovery_ui_data'] = str(profile)
manifest.write_text(json.dumps(m, indent=2))
helper = project / '.build/ui-input'
checks = []
report = {'passed': False, 'app': m['app'], 'binary_sha256': m['binary_sha256'], 'profile': str(profile), 'migration_original': str(old_profile), 'checks': checks}
sandbox = None

def command(args, timeout=12):
    r = subprocess.run([str(a) for a in args], capture_output=True, text=True, timeout=timeout)
    if r.returncode:
        raise RuntimeError(f'{args}: {r.stderr}')
    return r.stdout.strip()

def ax(script):
    return command(['osascript', '-e', 'tell application "System Events" to tell process "TomMusic"\n' + script + '\nend tell'])

def wait(predicate, seconds=40):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(.35)
    raise TimeoutError(f'Native UI wait reached {seconds}s bound')

def check(value, label, detail=None):
    if not value:
        raise AssertionError(f'{label}: {detail}')
    checks.append({'check': label, 'detail': detail})
    print('PASS:', label, detail or '', flush=True)

def data():
    return json.loads((profile / 'Library.json').read_text())

def texts():
    return ax('return value of static texts of group 1 of window "Tom Music"')

def tree():
    return ax('return entire contents of window "Tom Music"')

def point(description):
    return tuple(map(float, ax('return position of ' + description).split(',')))

def click(description):
    x, y = point(description)
    command([helper, 'click', x + 20, y + 9])

def input_text(value, submit=True):
    ax('set frontmost to true')
    click('text field 1 of group 1 of window "Tom Music"')
    wait(lambda: ax('return focused of text field 1 of group 1 of window "Tom Music"') == 'true', 3)
    time.sleep(.15)
    ax('keystroke "a" using command down\nkey code 51')
    wait(lambda: ax('return value of text field 1 of group 1 of window "Tom Music"') == '', 3)
    command([helper, 'type', value])
    wait(lambda: ax('return value of text field 1 of group 1 of window "Tom Music"') == value, 3)
    if submit:
        ax('key code 36')
        time.sleep(.3)

def sources_finished():
    selector = '(first UI element of group 1 of window "Tom Music" whose role is "AXDisclosureTriangle")'
    if ax('return exists ' + selector) != 'true':
        return False
    if ax('return value of ' + selector) == 'false':
        ax('perform action "AXPress" of ' + selector)
        time.sleep(.15)
    state = tree()
    return all(name in state for name in ['Internet Archive', 'ccMixter', 'Audius', 'Wikimedia Commons', 'Apple 目录']) and '等待 / 请求中' not in state

def pick(source):
    ax('click pop up button "结果来源" of group 1 of window "Tom Music"\ndelay 0.1\nclick menu item ' + json.dumps(source, ensure_ascii=False) + ' of menu 1 of pop up button "结果来源" of group 1 of window "Tom Music"')
    time.sleep(.2)

def control(help_text):
    ax('click (first button of group 1 of window "Tom Music" whose help is ' + json.dumps(help_text, ensure_ascii=False) + ')')

def playing():
    return ax('return exists (first button of group 1 of window "Tom Music" whose help is "暂停")') == 'true'

def position():
    return float(ax('return value of slider 2 of group 1 of window "Tom Music"'))

def discover():
    x, y = map(float, ax('return position of window "Tom Music"').split(','))
    command([helper, 'click', x + 65, y + 137])
    wait(lambda: '全网音乐发现' in texts(), 5)
    ax('click radio button 1 of radio group "发现方式" of group 1 of window "Tom Music"')
    wait(lambda: ax('return description of text field 1 of group 1 of window "Tom Music"') == '多源音乐搜索', 5)
    time.sleep(.2)

def songs_page():
    x, y = map(float, ax('return position of window "Tom Music"').split(','))
    command([helper, 'click', x + 65, y + 363])
    wait(lambda: '歌曲' in texts(), 5)

def result_button(index=1):
    return f'button {index} of UI element 1 of scroll area 2 of group 1 of window "Tom Music"'

def capture(name):
    line = next(line for line in command([helper, 'windows']).splitlines() if line.endswith('Tom Music'))
    command(['screencapture', '-x', '-l', line.split()[0], '-t', 'png', evidence / name])

def launch():
    command(['open', '-n', m['app'], '--args', '--data-dir', profile])
    time.sleep(.8)
    wait(lambda: ax('return exists window "Tom Music"') == 'true', 10)
    ax('set size of window "Tom Music" to {1180, 820}')

def quit_app():
    command(['osascript', '-e', 'tell application id "com.tommusic.desktop" to quit'])
    time.sleep(.5)

original_input = command([helper, 'input-source'])
try:
    command([helper, 'input-source', 'com.apple.keylayout.ABC'])
    launch()
    check((profile / 'Library.json').read_bytes() == old_bytes, 'Extracted 1.2 bundle loads a copy of 1.1 library without any startup mutation')
    discover()
    input_text('piano')
    wait(sources_finished, 55)
    check('失败：' not in tree(), 'Native five-source parallel search completes with actual results')
    capture('ui-discovery-search.png')
    pick('Apple 目录')
    input_text('周杰伦')
    wait(lambda: sources_finished() and '周杰' in tree(), 55)
    apple = tree()
    check('官方目录 · 前往来源' in apple and '授权音频可保存' not in apple and '公开音轨在线播放' not in apple, 'Chinese mainstream search displays official-only metadata, not free full-song/preview claims')
    capture('ui-discovery-pop.png')
    input_text('BTS FAKE LOVE')
    wait(lambda: sources_finished() and 'FAKE LOVE' in tree(), 55)
    pick('全部来源')
    first_title = ax('return value of static text 1 of UI element 1 of scroll area 2 of group 1 of window "Tom Music"')
    first_artist = ax('return value of static text 2 of UI element 1 of scroll area 2 of group 1 of window "Tom Music"')
    check(first_title == 'FAKE LOVE' and '防彈少年團' in first_artist, 'User-requested BTS FAKE LOVE: exact official catalog original ranks above uploads and cover/alternate versions')
    capture('ui-bts-fake-love.png')
    pick('Audius')
    bts_uploads = tree()
    check('未认证上传者' in bts_uploads and '不等于已核验原唱' in bts_uploads and '整曲在线播放' not in bts_uploads, 'Misleading Official MV title is accompanied by real uploader identity and no verified-original/full-song claim')
    check('尚未播放' in texts() and (profile / 'Library.json').read_bytes() == old_bytes, 'BTS test does not substitute a cover/unverified repost or save a promotional preview')
    capture('ui-bts-upload-warning.png')
    report['requested_song'] = {'title': first_title, 'artist_row': first_artist, 'original_full_playback': 'not verified/provided in app; official catalog link only', 'unverified_reposts_not_substituted': True}
    input_text('piano')
    wait(sources_finished, 55)
    pick('Audius')
    wait(lambda: 'Piano Fala' in tree(), 5)
    before_stream = (profile / 'Library.json').read_bytes()
    before_media = sorted(p.name for p in (profile / 'Media').iterdir())
    click(result_button())
    wait(lambda: playing() and position() > .4, 35)
    check('在线 · 不保存' in texts() and (profile / 'Library.json').read_bytes() == before_stream and before_media == sorted(p.name for p in (profile / 'Media').iterdir()), 'Native Audius play button streams actual audio without creating library entries/files')
    capture('ui-discovery-stream.png')
    command([helper, 'media-play']); time.sleep(.7)
    paused = position(); time.sleep(.6)
    check(not playing() and abs(position() - paused) < .3, 'Synthesized macOS media pause stops actual remote audio clock (not physical key test)')
    command([helper, 'media-play'])
    wait(lambda: playing() and position() > paused + .3, 12)
    check(True, 'System media resume advances the public stream again')
    control('暂停')
    pick('ccMixter')
    before_count = len(data()['tracks'])
    click(result_button())
    wait(lambda: len(data()['tracks']) == before_count + 1, 145)
    wait(lambda: playing() and position() > .3, 8)
    cc = next(t for t in data()['tracks'] if t.get('origin', {}).get('provider') == 'ccMixter')
    check(cc['duration'] > 30 and cc['origin']['licenseURL'].startswith('https://creativecommons.org/'), 'Native save/play button imports complete real ccMixter audio with license and provenance', cc['duration'])
    check('在线 · 不保存' not in texts(), 'Switching from stream to saved audio returns to the local player')
    capture('ui-discovery-saved.png')
    control('暂停')
    ax('click radio button 2 of radio group "发现方式" of group 1 of window "Tom Music"')
    wait(lambda: ax('return description of text field 1 of group 1 of window "Tom Music"') == '公开音乐链接', 5)
    time.sleep(.2)  # Wait for the replacement field's actual hit-test layout, not the old search field.
    count = len(data()['tracks'])
    input_text('https://archive.org/details/fell013')
    wait(lambda: '本页找到' in texts(), 45)
    check('12 个' in texts() and ax('return value of checkbox 1 of group 1 of window "Tom Music"') == '0' and len(data()['tracks']) == count, 'Real webpage resolves 6 MP3 plus 6 FLAC links without auto-download or implied rights')
    check(ax('return enabled of ' + result_button()) == 'false', 'Unknown-rights save button is disabled until explicit confirmation')
    ax('click checkbox 1 of group 1 of window "Tom Music"')
    check(ax('return enabled of ' + result_button()) == 'true', 'Rights confirmation enables the selected public-link save action')
    capture('ui-public-audio.png')
    direct = 'https://archive.org/download/fell013/01_-_invisible_companion.mp3'
    input_text(direct)
    wait(lambda: '识别到直接音频地址' in texts(), 15)
    check(ax('return value of checkbox 1 of group 1 of window "Tom Music"') == '0' and len(data()['tracks']) == count, 'New direct URL resets consent and does not pre-download audio')
    ax('click checkbox 1 of group 1 of window "Tom Music"')
    click(result_button())
    wait(lambda: len(data()['tracks']) == count + 1, 145)
    wait(lambda: playing() and position() > .3, 8)
    web = next(t for t in data()['tracks'] if t.get('origin', {}).get('fileURL') == direct)
    check(web['duration'] > 200 and web['origin']['provider'] == '公开链接' and not web['origin']['licenseURL'], 'Confirmed direct full audio imports/plays without inventing an open-license declaration', web['duration'])
    control('暂停')
    input_text('https://127.0.0.1/private.mp3')
    wait(lambda: '解析失败' in texts(), 5)
    check('不访问本机' in texts() and len(data()['tracks']) == count + 1, 'Native resolver rejects local/private targets with explicit error and no substitute')
    check(data()['tracks'][:len(old['tracks'])] == old['tracks'] and data()['playlists'] == old['playlists'] and data()['volume'] == old['volume'], 'Adding two real sources preserves all old tracks, favorites, playlists and volume')
    old_after = (old_profile / 'Library.json').read_bytes()
    check(old_after == old_bytes, 'Original 1.1 profile remains byte-for-byte untouched')
    quit_app()
    log = open(evidence / 'discovery-offline.log', 'w')
    sandbox = subprocess.Popen(['/usr/bin/sandbox-exec', '-p', '(version 1) (allow default) (deny network*)', str(Path(m['app']) / 'Contents/MacOS/TomMusic'), '--data-dir', str(profile)], stdout=log, stderr=subprocess.STDOUT, cwd='/tmp')
    time.sleep(.8)
    wait(lambda: ax('return exists window "Tom Music"') == 'true', 10)
    songs_page(); input_text('Observations', submit=False)
    wait(lambda: '找到 1 首歌曲' in texts(), 8)
    x, y = point('static text 1 of group 1 of UI element 1 of scroll area 2 of group 1 of window "Tom Music"')
    command([helper, 'double', x + 25, y + 6])
    wait(lambda: playing() and position() > .3, 6)
    p1 = position(); time.sleep(.7); p2 = position()
    check(p2 > p1 + .3, 'Restarted extracted app plays saved ccMixter full music while its network is denied', [p1, p2])
    control('暂停')
    discover(); input_text('piano')
    wait(sources_finished, 55)
    check(tree().count('失败：') == 5 and '没有匹配的可展示结果' in texts(), 'Offline multi-source search shows five real source errors and no cached/demo fallback after restart')
    capture('ui-discovery-offline.png')
    (evidence / 'ui-discovery-offline-tree.txt').write_text(tree())
    quit_app(); sandbox.wait(timeout=8); sandbox = None
    launch()
    check(len(data()['tracks']) == len(old['tracks']) + 2 and data()['playlists'] == old['playlists'], 'Normal final restart retains both new songs and previous user data')
    discover()
    # Exercise the intended minimum window, not only the enlarged test window.
    ax('set size of window "Tom Music" to {980, 640}')
    check(ax('return count of text fields of group 1 of window "Tom Music"') == '1', 'Discovery controls remain available at 980×640 minimum window')
    capture('ui-discovery-minimum.png')
    report['ccmixter_song'] = cc
    report['public_song'] = web
    report['passed'] = True
except Exception as error:
    report['error'] = repr(error)
    try:
        (evidence / 'ui-discovery-failure-tree.txt').write_text(tree())
        capture('ui-discovery-failure.png')
    except Exception:
        pass
    raise
finally:
    if sandbox and sandbox.poll() is None:
        sandbox.terminate(); sandbox.wait(timeout=8)
    command([helper, 'input-source', original_input])
    (evidence / 'discovery-ui-test-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
