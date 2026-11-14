#!/usr/bin/env python3
"""Real-source native UI + migration + network-denied offline acceptance.
Requires a stopped TomMusic, a built ui-input helper, Accessibility permission,
and a v1.0 isolated fixture profile. Never mutates the supplied old profile or
system network/audio settings. Each operation has a deadline; no infinite retry.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('--old-profile', required=True)
parser.add_argument('--fixtures', required=True)
options = parser.parse_args()
project = Path(__file__).resolve().parent.parent
manifest_path = project / 'evidence/acceptance-path.json'
m = json.loads(manifest_path.read_text())
profile = Path(m['root']) / 'OnlineUIUpgradeLibrary'
assert not profile.exists(), 'Use a fresh acceptance root; never overwrite an existing test library'
old = json.loads((Path(options.old_profile) / 'Library.json').read_text())
shutil.copytree(options.old_profile, profile)
m.update(ui_data=str(profile), ui_fixtures=options.fixtures, migration_original=options.old_profile)
manifest_path.write_text(json.dumps(m, indent=2))
helper = project / '.build/ui-input'
checks = []
report = {'passed': False, 'binary_sha256': m['binary_sha256'], 'profile': str(profile), 'checks': checks}
sandbox = None

def cmd(args, timeout=12):
    result = subprocess.run([str(a) for a in args], capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f'{args}: {result.stderr}')
    return result.stdout.strip()

def ax(s):
    return cmd(['osascript', '-e', 'tell application "System Events" to tell process "TomMusic"\n' + s + '\nend tell'])

def check(condition, label, detail=None):
    if not condition:
        raise AssertionError(f'{label}: {detail}')
    checks.append({'check': label, 'detail': detail})
    print('PASS:', label, detail or '', flush=True)

def wait(predicate, seconds=35):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        result = predicate()
        if result:
            return result
        time.sleep(0.4)
    raise TimeoutError('UI wait exceeded ' + str(seconds) + ' seconds')

def data():
    return json.loads((profile / 'Library.json').read_text())

def texts():
    return ax('return value of static texts of group 1 of window "Tom Music"')

def tree():
    return ax('return entire contents of window "Tom Music"')

def field(query, submit=True):
    x, y = [float(x.strip()) for x in ax('return position of text field 1 of group 1 of window "Tom Music"').split(',')]
    cmd([helper, 'double', x + 40, y + 6])
    ax('keystroke "a" using command down\nkey code 51\nkeystroke ' + json.dumps(query, ensure_ascii=False) + ('\nkey code 36' if submit else ''))

def control(label):
    ax('click (first button of group 1 of window "Tom Music" whose help is ' + json.dumps(label, ensure_ascii=False) + ')')

def help_contains(label):
    return ax('return exists (first button of group 1 of window "Tom Music" whose help is ' + json.dumps(label, ensure_ascii=False) + ')') == 'true'

def online_page():
    x, y = map(float, ax('return position of window "Tom Music"').split(','))
    cmd([helper, 'click', x + 55, y + 189])
    wait(lambda: '在线免费音乐' in texts(), 5)

def play_local(query):
    field(query, submit=False)
    wait(lambda: '找到 1 首歌曲' in texts(), 5)
    position = ax('return position of static text 1 of group 1 of UI element 1 of scroll area 2 of group 1 of window "Tom Music"')
    x, y = map(float, position.split(','))
    cmd([helper, 'double', x + 25, y + 6])

def capture(name):
    lines = cmd([helper, 'windows']).splitlines()
    line = next(x for x in lines if x.endswith('Tom Music'))
    cmd(['screencapture', '-x', '-l', line.split()[0], '-t', 'png', project / 'evidence' / name])

def launch():
    cmd(['open', '-n', m['app'], '--args', '--data-dir', profile])
    time.sleep(0.8)
    wait(lambda: ax('return exists window "Tom Music"') == 'true', 10)
    ax('set size of window "Tom Music" to {1180, 820}')

current = cmd([helper, 'input-source'])
try:
    cmd([helper, 'input-source', 'com.apple.keylayout.ABC'])
    launch()
    check(data() == old, 'Upgrade loads v1.0 library with no data loss before any writes')
    online_page()
    field("Fleurs d'Hiver")
    wait(lambda: ax('return count of buttons of UI element 1 of scroll area 2 of group 1 of window "Tom Music"') != '0')
    ax('click button 1 of UI element 1 of scroll area 2 of group 1 of window "Tom Music"')
    wait(lambda: 'Thin ice' in tree())
    check('Felliri' in texts() and 'Fleurs' in texts(), 'Native online search and real release/track selection')
    capture('ui-online-search.png')
    ax('click button 2 of UI element 1 of scroll area 3 of group 1 of window "Tom Music"')
    wait(lambda: len(data()['tracks']) == len(old['tracks']) + 1, 145)
    wait(lambda: help_contains('暂停'), 5)
    time.sleep(0.8)
    online = next(t for t in data()['tracks'] if t.get('origin'))
    check(online['title'] == 'Thin ice' and online['duration'] > 300, 'Download/play button saves full real MP3, not a preview', online['duration'])
    check(float(ax('return value of slider 2 of group 1 of window "Tom Music"')) > 0.2, 'Downloaded song actually plays via UI')
    check(online['origin']['licenseName'] == 'CC BY-NC-ND 3.0' and online['origin']['pageURL'].startswith('https://archive.org/'), 'Source, license and creator recorded for online song')
    check(data()['tracks'][:len(old['tracks'])] == old['tracks'] and data()['playlists'] == old['playlists'] and data()['volume'] == old['volume'], 'Upgrade preserves old tracks, favorites, playlists and volume after new online import')
    capture('ui-online-playing.png')
    cmd([helper, 'media-play']); time.sleep(0.4)
    check(help_contains('播放'), 'Synthesized macOS system media Play/Pause pauses actual online track (not physical key test)')
    cmd([helper, 'media-play']); time.sleep(0.4)
    check(help_contains('暂停'), 'Synthesized system media Play/Pause resumes actual track')
    control('暂停')
    ax('click button 3 of UI element 1 of scroll area 3 of group 1 of window "Tom Music"')
    wait(lambda: '正在下载完整音频' in texts(), 5)
    # Root button indices change when sidebar items/layout change. Locate the
    # actual cancel control on the visible progress row, not a navigation button.
    cancelled = ax('''set p to position of (first static text of group 1 of window "Tom Music" whose value starts with "正在下载完整音频")
repeat with i from 1 to count of buttons of group 1 of window "Tom Music"
    set b to button i of group 1 of window "Tom Music"
    set q to position of b
    if item 1 of q > item 1 of p and item 2 of q > (item 2 of p) - 14 and item 2 of q < (item 2 of p) + 14 then
        click b
        return i
    end if
end repeat
error "No visible cancel control found on download progress row"''')
    wait(lambda: '正在下载完整音频' not in texts() and '在线免费音乐' in texts(), 8)
    time.sleep(1.5)
    check(len(data()['tracks']) == len(old['tracks']) + 1 and help_contains('播放') and 'Thin ice' in texts(), 'Actual cancel button stops pending download without autoplay or delayed library insertion', cancelled)
    field('TomMusicNoSuchRelease9f78fa7b2')
    wait(lambda: '没有找到开放授权音乐' in tree())
    check('无法搜索在线音乐' not in texts(), 'Online no-result UI explicitly reports empty results, no demo fallback')
    # Import own music through the same native file panel used by a real user.
    ax('keystroke "o" using command down')
    wait(lambda: ax('return exists window "导入音乐"') == 'true', 10)
    ax('keystroke "g" using {command down, shift down}')
    wait(lambda: ax('return count of sheets of window "导入音乐"') == '1', 10)
    artwork = Path(m['data']) / 'ExtendedGeneratedFixtures/Embedded Artwork.m4a'
    ax('set value of text field 1 of sheet 1 of window "导入音乐" to ' + json.dumps(str(artwork)) + '\nkey code 36\ndelay 0.4')
    if ax('return count of sheets of window "导入音乐"') != '0':
        ax('key code 36\ndelay 0.3')
    ax('click button "导入" of window "导入音乐"')
    wait(lambda: len(data()['tracks']) == len(old['tracks']) + 2, 10)
    art = next(t for t in data()['tracks'] if t['title'] == 'Generated Artwork Fixture')
    check(bool(art['artworkName']) and not art.get('origin'), 'Native local import still works alongside online music, including actual embedded artwork')
    cmd(['osascript', '-e', 'tell application id "com.tommusic.desktop" to quit'])
    time.sleep(0.5)
    logfile = open(project / 'evidence/offline-sandbox.log', 'w')
    sandbox = subprocess.Popen(['/usr/bin/sandbox-exec', '-p', '(version 1) (allow default) (deny network*)',
                                m['app'] + '/Contents/MacOS/TomMusic', '--data-dir', str(profile)],
                               cwd='/tmp', stdout=logfile, stderr=subprocess.STDOUT)
    time.sleep(0.8)
    wait(lambda: ax('return exists window "Tom Music"') == 'true', 10)
    play_local('Thin ice')
    time.sleep(0.8)
    p1 = float(ax('return value of slider 2 of group 1 of window "Tom Music"'))
    time.sleep(0.7)
    p2 = float(ax('return value of slider 2 of group 1 of window "Tom Music"'))
    check(p2 > p1 + 0.3, 'Quit/restart with network denied: downloaded full MP3 plays offline', [p1, p2])
    control('暂停')
    play_local('Generated Artwork Fixture')
    time.sleep(0.4)
    check('Diagnostic Test Artist' in texts(), 'Reopened local artwork file displays real embedded artist/title')
    capture('ui-embedded-artwork.png')
    control('暂停')
    online_page(); field('piano')
    wait(lambda: '无法搜索在线音乐' in texts())
    offline_error = texts()
    check(('Operation not permitted' in offline_error or '无法解析公开域名' in offline_error) and '曲源请求未完成' in tree(), 'Network-denied search gives actual DNS/network error and empty source results instead of substitute songs', offline_error)
    capture('ui-network-denied.png')
    (project / 'evidence/ui-network-denied-state.txt').write_text(texts())
    cmd(['osascript', '-e', 'tell application id "com.tommusic.desktop" to quit'])
    sandbox.wait(timeout=8); sandbox = None
    launch()
    check(len(data()['tracks']) == len(old['tracks']) + 2 and data()['playlists'] == old['playlists'], 'Final normal restart retains online songs, local import and old playlists')
    report['online_song'] = online
    report['passed'] = True
finally:
    if sandbox and sandbox.poll() is None:
        sandbox.terminate()
        sandbox.wait(timeout=8)
    cmd([helper, 'input-source', current])
    (project / 'evidence/online-ui-test-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
