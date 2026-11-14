# Tom Music checkpoint — 1.4.0 verified TRUE native audio-only listening

## Final 1.4 acceptance (authoritative current release)
- App **dist/Tom Music.app**, **1.4.0/build 5**. ZIP **dist/Tom Music-1.4.0-macOS-arm64.zip**; SHA-256 **9acd43f7afa685c2eecab68314f128c5e56fb3b4c19e387248f5dc7494468253**. Executable SHA-256 **1ba582cd8bbae04670dcc98c27a3fe31ac45463fcf2ece0727d96167113158d9**.
- Exact final bytes passed **167 core/model/audio/live checks + 81 native UI checks**: 17 audio-only, 11 retained optional web, 23 discovery, 15 local, 15 legacy online/upgrade/offline. Independently ZIP-extracted outside project, every bundle file hash matches; local ad-hoc signature verified, not notarized, arm64 only. Current paths: `evidence/acceptance-path.json`.
- TRUE audio-only: standalone AAC cache **6,373,337 bytes, 242.302333 seconds, one audio track, ZERO video tracks**, no DRM, actual AVAudioPlayer clock, not a hidden MV/WebView. OS `afinfo` independently confirms AAC stereo/48kHz. Complete native no-seek playback reached natural end in **243.6 wall seconds** including pause/resume. Source explicitly **剪辑版**; not verified official album master/ownership.
- Native UI verified real search, exact source selection/version, pause/resume, actual seek drag near 120 s, 980x640, cancel with no late autoplay/cache insertion, local-file switch, cache deletion on normal quit, no JSON/library mutation. Evidence `native-audio-ui-test-report.json`, `native-audio-afinfo.txt`, `ui-native-audio-*.png`.
- Separate non-hardcoded real workflow: typed **周杰伦 晴天**, clicked first actual native result **BV1BZbSzZEGT**, native standalone AAC **4:29**, advancing clock **5.566625 s**, uploader **VV音乐局**, video tracks 0. No pasted/preselected BV ID, no WebView. This does not certify uploader's fidelity/official claims. Evidence `native-audio-search-click-report.json`, `ui-native-second-song.png`.
- Final dist App independently opened against DEFAULT real profile: real keyword search followed by explicit canonical lookup of requested known edited source (not an unverified substitute), actual pure native audio started, no web player/video tracks. Default `Library.json` and Media/Artwork file fingerprints unchanged. Original input source restored. Evidence `default-launch-1.4.json`, `ui-final-native-audio.png`.
- Full old local/import/playlist/favorite/volume/upgrade/download/cancel/offline and optional web regressions passed on these same bytes. README/package/final-validation synchronized. Current final validation: `evidence/final-validation.json`, `package-report-1.4.json`.
- Harness failures retained: first native AX role scan hit a stale changing 0:01 text reference after 6 passing checks; skip only stale role reads while still checking AXWebArea + independently verified media tracks. Next run showed a focus/input race after 2 checks; preserved `native-audio-ui-input-focus-failure.*`. Native and old discovery input helpers now verify focus, cleared value and typed value BEFORE Return, with bounded waits. Old offline discovery failure was an empty/unsubmitted field, not a service outage; `discovery-ui-offline-input-focus-failure.json` retained. No production code/test assertion removed or timeout increased to conceal failures. Fresh complete runs passed.
- Reproduce: `./scripts/build.sh`; `python3 scripts/verify-release.py --network --discovery` (240 s diagnostic bound); `python3 scripts/package-release.py`; `python3 scripts/verify-native-audio-ui.py` (300 s natural-audio loop, outer bound 420 s); retained web/discovery/local/legacy scripts as below. Helper/old profiles recorded in prior checkpoints. Rebuild means new bytes must be retested.
- **Unmet universal/original criteria remain explicit:** not every song/platform available; no verified official album BTS original/permanent download/offline playback. New AAC has edited-source provenance. Native cache is not a permanent library download. Physical keys/unconnected hardware/subjective sound quality/notarization/Intel still not verified. No invisible background implementation claim.

## Historical 1.4 implementation work (before final checks)
- User clarifies that MV/web playback is NOT the desired deliverable: wants native song search + native audio transport, no video. Added default **直接听歌** view; old visible webpage feature now explicitly **网页 / MV**.
- New `NativeAudio.swift`: normal anonymous platform session (server-issued public homepage cookies, private ephemeral jar), public search/view/play APIs, strict paid/exclusive/background/download permission checks, independent AAC selection, same-response published CDN locations only, 80 MB bound, actual AVFoundation validation of audio>0/video=0/no DRM/full duration. No browser cookies, private accounts, generated fingerprints, WBI signatures, CAPTCHA bypass, hidden video player or media proxy.
- Public API search previously returned 412 without ordinary client context; a NORMAL fresh anonymous homepage session received `b_nut` + `buvid3` via Set-Cookie and actual search then returned code 0. No copied/generated cookie values. Source view/play APIs provide explicit public standalone DASH audio for selected clip.
- REAL file proof: selected FAKE LOVE **剪辑版** source `BV1JV62BaEVo`, standalone AAC **6,373,337 bytes**, **242.302333 s**, **one audio track, ZERO video tracks**, 48 kHz stereo (~209 kb/s, not lossless). `afinfo` independently confirms audio-only MP4/AAC; no video page/media loaded by this adapter. Still NOT verified official album mastering or ownership.
- Core/live test initially passed **166 checks**, including actual native AVAudioPlayer start, clock, pause, seek/resume, no WebView session, no library write and owned-cache deletion on switch. After improving short song-title display and preserving raw title/version provenance, final rebuild/retest required (expected 167 checks).
- MusicPlayer now owns explicitly bounded UUID audio cache, cleans it on switch/deinit/app quit, and uses normal native seek/volume/media controls. Search metadata does not import files. Cache is temporary; no permanent download/official-original claim. Existing local/favorites/playlists unaffected.
- Rollback `.build/checkpoints/Tom Music-1.3.app`, previous evidence `final-validation-1.3.json`. Current dist is 1.4.0/build 5; do NOT claim current-package UI acceptance until new audio-only end-to-end and old regressions finish. Native source actor can search typed song names or BV links/IDs; multi-P/paid/unknown/restricted sources fail explicitly, not silently switch tracks.
- Next concrete steps: build; `python3 scripts/verify-release.py --network --discovery`; package identical bytes; new native audio UI test for search→play→natural finish WITHOUT VIDEO, pause/resume/seek/cancel/local/quit cleanup; rerun discovery/local/online regressions and retained optional web flow; update README/final hashes/evidence; leave final app in true audio-only playback with default data fingerprint unchanged.

## Historical verified 1.3 status
- App `dist/Tom Music.app`, version **1.3.0/build 4**. ZIP `dist/Tom Music-1.3.0-macOS-arm64.zip`, SHA-256 **f204942ab0f126acdc7018856225d11a56b5545055ae8310a7fddcb2fa4a3255**.
- Executable SHA-256 **ddf36b91e2a70e01279112ade1eb5893d9dc41c299c42c9d12d418a23b5fccb5**. Local ad-hoc signature and all extracted bundle file hashes verified; not notarized, arm64 only.
- Final independently extracted bundle passed **144 core/model/audio/live checks + 64 native UI checks**: 11 new web, 23 discovery, 15 local, 15 legacy online/upgrade/offline. This does not mean 208 separate product features or every song available.
- Real selected BTS FAKE LOVE public **剪辑版** played unmuted in app, from opening to natural end without seeking: **251.18 seconds elapsed** including pause/resume, source about **243 seconds**. Not a verified official album-original master and not downloaded/offline.
- Additional real workflow: typed **周杰伦 晴天 MV**, clicked actual rendered platform result **【4K修复】周杰伦 - 晴天MV 2160P修复版**; same selected platform video opened inside app and actual media clock advanced to **0:15 / 5:18**. No pasted/hardcoded ID in that workflow; no authenticity/mastering endorsement of uploader's claims. Evidence `web-search-click-report.json`.
- The final `dist` app was independently opened with the DEFAULT profile, selected FAKE LOVE edited public video and actually began unmuted playback; `Library.json` and managed Media/Artwork file fingerprints stayed unchanged. Source input restored to user's original IME. Evidence `default-launch-1.3.json`, `ui-final-web-playing.png`.
- Current evidence/paths authoritative: `evidence/final-validation.json`, `acceptance-path.json`, `package-report-1.3.json`. README updated for native core plus WKWebView platform surfaces and their privacy/network limits.
- Bounds honored. One old discovery UI run raced the SwiftUI mode transition and typed into the replaced field (empty resolver URL, not a source outage). Preserve `discovery-ui-mode-transition-failure.json`; harness now waits up to 5 s for actual resolver field description and 0.2 s hit-test layout. Full fresh-profile rerun passed, no app code changed and no assertion removed. Missing accessible names on new buttons were fixed before final rebuild/full run.
- Reproduction: `./scripts/build.sh`; `python3 scripts/verify-release.py --network --discovery` (240 s bound); `python3 scripts/package-release.py`; `python3 scripts/verify-web-ui.py` (315 s playback bound); `python3 scripts/verify-discovery-ui.py`; prepare old isolated fixture copy and run local/legacy scripts as documented in prior checkpoint. Do not rebuild after claiming these hashes passed without repeating final-byte acceptance.
- **Still not complete for universal requests:** not every song/platform available; no verified BTS official album-original full download/offline playback; YouTube official BTS playback in this environment requires sign-in/bot verification and remains unverified. Do not conflate a working Bilibili edited-video choice with those original criteria. No bypasses, account credentials, media extraction or hidden mirrors introduced. No claim of invisible ongoing background implementation.

## Implementation 1.3 milestone (history)
- User explicitly rejects Apple Music dependency and wants direct listening inside Tom Music. Added `站内听歌` to discovery with Bilibili/YouTube platform-owned visible WKWebView playback/search, no Apple API keys or developer account needed.
- REAL native result: `https://www.bilibili.com/video/BV1JV62BaEVo/` plays **243 s** in Tom Music with muted=false, advancing clock and actual visible frames. Its source explicitly says **剪辑版**, uploader **HiRes音源体验**. This is not verified official album mastering/ownership, not a downloaded file, not a preview. Screenshot `evidence/ui-web-playing.png`; runtime readiness probes `bilibili-embed-probe.json` etc.
- Do not substitute it for earlier original-album/offline acceptance. It is an explicitly chosen public edited video version satisfying a narrower in-app listening workflow.
- YouTube official BTS MV normal page requires `Sign in to confirm you're not a bot`; embedded player gave error 150/auth. Did not bypass verification, collect cookies, guess signatures or remove platform restrictions. Bilibili raw API returned 412; final app does not use that API or scrape search HTML. It displays normal platform web search and redirects user-selected Bilibili videos to the same video's documented visible platform player.
- Native WebKit's default incomplete browser marker triggered Bilibili's unsupported-browser page. Declare supported Safari/WebKit compatibility baseline + TomMusic identity; does not change authentication/region/paid access or system settings.
- Native transport pauses local audio before web playback; selecting local/AVPlayer audio pauses web. Mode exit pauses/removes web content. URLs restrict main-frame navigation to platform hosts and HTTPS, no arbitrary/private URLs, no media extraction/download. Cookies are per-view ephemeral, not taken from browsers. Platform pages may include ads/recommendations/login; do not claim ad-free platform content or run hidden audio-only YouTube.
- Final-byte model/live check currently passes **144** assertions; independent ZIP extraction verified. A first native test found missing accessibility names on new text buttons after 3 successful checks; fixed names/help and return-to-search query retention. Rebuild/repackage and rerun full 243-second native playback + current-byte discovery/local/legacy regressions next. Use `python3 scripts/verify-web-ui.py` (315-second source-playback bound, process outer bound 420 s). Snapshot 1.2 rollback: `.build/checkpoints/Tom Music-1.2.app`; old release evidence: `evidence/final-validation-1.2.json`.

## Previous verified 1.2 status (historical, not final 1.3 acceptance)
- Current app: `dist/Tom Music.app` 1.2.0/build 3; ZIP: `dist/Tom Music-1.2.0-macOS-arm64.zip`.
- Current executable SHA-256: `e8d31633f8569d2bfd47131de872ee6973e56fedc7b12606693a80d2e715dc1c`.
- ZIP SHA-256: `307770a8eba1070dc4523fd72ace884a2a1bdeb643e4e40e3ea8f71d65818def`.
- Final bytes passed **130 model/audio/live/recovery/ranking checks + 23 discovery/BTS/upgrade/offline UI checks + 15 local UI checks + 15 legacy online/upgrade/offline UI checks**. All UI runs used the independently ZIP-extracted bundle and isolated profiles. See current `evidence/acceptance-path.json` / `final-validation.json`.
- User's stronger universal criterion remains **NOT MET**: every song downloadable, especially verified full BTS FAKE LOVE original. Official metadata/242.334-second catalog entry verified; no authorized original download or original offline playback verified. Never report cover/repost/preview as that acceptance passing.
- No ads, recommendation feed or telemetry added. Local files are not restricted by artist/song-name whitelist; source/codec/access availability still matters. User states private noncommercial use; do not misstate it as a commercial publishing request.

## Historical 1.1.0 checkpoint (not current release evidence)

## User request / implemented scope
User requested expanded verification of previously untested features, free online music search/listening, and continued own-music import.

Implemented a native SwiftUI/AppKit/AVFoundation app with:
- Local files/folders/Finder drop import, SHA-256 deduplication, metadata/artwork, favorites, playlists, search, queue, playback, seek, shuffle/repeat, system Now Playing/media controls and saved volume.
- New **在线免费音乐** section using the real Internet Archive Netlabels API, explicit recognized Creative Commons / CC0 / public-domain declarations, MP3 releases and verified per-release metadata.
- Explicit **下载并播放** downloads a full MP3, imports to managed library and plays. No 30-second previews or subscription bypass; not a complete commercial-pop catalogue.
- Source/creator/license saved as optional `origin` metadata and available in song context menus. Existing v1.0 libraries remain readable.
- Search/browse, pagination, empty results, error states, size/progress/cancel, cached-song replay. Max 80 MB per MP3; restricted/private/unknown-license files are rejected. HTTPS download redirects confined to archive.org and subdomains.
- No default background catalogue fetch: network only on user search, selection, download or opening source/terms.

## Environment / deliverables
- Project: `/Users/a1/Documents/商业项目库/Tom Music` (no git repository).
- macOS 15.1, Apple M4 arm64; Swift 6.0.3 Command Line Tools, no full Xcode.
- App: `dist/Tom Music.app` (v1.1.0, bundle build 2).
- Package: `dist/Tom Music-1.1.0-macOS-arm64.zip`, adjacent `.zip.sha256`.
- Final executable SHA-256: `0220db5210f20130fbeb98be23cf55edb460b0d661ec47e6b658128ba8473d02`.
- `evidence/package-report.json` has ZIP hash, all bundle member hashes, extraction path and packaged user-facing checks.
- Local ad-hoc signature verified. No notarization, no Intel/universal build and no public publishing.
- v1.0 executable checkpoint: `.build/checkpoints/Tom Music-1.0.app`.

## Final-byte executed acceptance
**56 extended audio/data/live-service checks + 15 local UI checks + 15 online/upgrade/offline UI checks passed.** Counts include safety/data assertions, not 86 independent product features. Two additional synthesized media next/previous checks passed.

Commands:
```sh
./scripts/build.sh
python3 scripts/verify-release.py --network
swiftc -vfsoverlay "$PWD/.build/sdk-compat/overlay.json" scripts/ui-input.swift -o .build/ui-input
# OLD_PROFILE / FIXTURES taken from evidence/acceptance-1.0.json; do not use user profile:
python3 scripts/verify-online-ui.py --old-profile "$OLD_PROFILE" --fixtures "$FIXTURES"
python3 scripts/verify-ui.py
codesign --verify --deep --strict "dist/Tom Music.app"
shasum -a 256 "dist/Tom Music.app/Contents/MacOS/TomMusic"
ditto -c -k --sequesterRsrc --keepParent "dist/Tom Music.app" "dist/Tom Music-1.1.0-macOS-arm64.zip"
```
All diagnostics run against independent app copies outside source/build trees and isolated temporary profiles. Self-test refuses default-profile use. `verify-release.py` bounds network+extended diagnostics to 240 seconds (120 extended-only, 35 basic); afconvert operations bounded to 12 seconds. UI commands have deadlines and finite polling, not infinite retries.

### Audio, metadata, system and output devices
- Actual generated audio decoded/played as PCM WAV, AAC/M4A, raw AAC, ALAC/M4A, FLAC, AIFF, AIF, CAF, AAC/MP4. MP3 uses an actual openly licensed full Internet Archive song, not fake audio.
- Duration, play clock, pause, seek, next/previous, repeat-one actual completion, repeat-all selected context verified.
- Actual M4A contains generated PNG cover and title/artist/album metadata; extracted, persisted/reopened, visibly rendered and published to system Now Playing with artwork.
- CoreAudio enumerated all **three currently available** output paths: P2768T (HDMI), 外置耳机, Mac mini扬声器. Each was explicitly selected on the AVAudioPlayer, with requested UID and advancing playback clock checked. No global/default output setting changed; before/after default ID equality asserted. No microphone recording or subjective listening test.
- Actual macOS system-defined synthesized media-key events exercised remote play/pause and next/previous handlers. Next/previous test starts a fresh A→B playback context; previous context-menu tests had deliberately prepended A to the queue, so a first naive expectation of immediate B was a test setup mistake, not a product failure. Reset queue and verified B→A.

### Real online service / user-level workflow
- Live search `Fleurs d'Hiver` → actual `fell013` release → full `Thin ice` MP3 (309.8906 seconds), creator Fellirium, declared CC BY-NC-ND 3.0.
- Actual native UI: type search, select release, click download/play, wait for full file, observe progress/playing state. License/source persisted and original files/playlists/volume retained.
- Actual cancel button stops pending download with no insertion or autoplay.
- Real empty-result query stays empty; real missing audio returns explicit HTTP 404. No synthetic fallback.
- Source page and Creative Commons terms verified with normal HTTP GET (both 200); initial generic HEAD request was rejected 403, not counted as success. Evidence `source-links-report.json`.
- Native ⌘O panel imported own local M4A with embedded artwork alongside downloaded music. Local regression reverified text spaces, result/no-result states, double-click play, pause, mouse seek, next/previous, favorites, playlist context menu, queue and volume saving.

### Genuine offline and upgrade/recovery
- Copied **v1.0 isolated test profile** (not real user data) and opened with final v1.1. Initially identical JSON; after online additions, all original track fields/favorites/playlists/volume still identical. No fake schema migration claim.
- Quit/relaunch retained old library plus downloaded MP3 and new local import.
- Started final standalone app with process-only policy:
  `/usr/bin/sandbox-exec -p '(version 1) (allow default) (deny network*)' APP/Contents/MacOS/TomMusic --data-dir ISOLATED_PROFILE`
- Under real denied networking, the downloaded full MP3 still played and advanced from 0.6079→1.6079 seconds. Online search explicitly reported Operation not permitted, with no substitute catalogue/audio. This did not change the computer's global network settings.
- Corrupt library cannot overwrite its original bytes. Managed deletion persists and preserves original input files. Duplicate audio from online/local paths shares SHA-256 deduplication.
- Queue/playback position intentionally do not restore; music/favorites/playlists/volume do.

### Final package itself
- Created ZIP, extracted outside project, verified ad-hoc signature and **all bundle file hashes** identical to the tested app.
- Launched the extracted ZIP app with another isolated library, exercised local MP3 playback, live catalogue search, selection and immediate saved-song playback.
- No fixture audio or test catalogue is bundled in the app or default user library.

## Evidence map
Final reports:
- `evidence/acceptance-path.json`: final independent app/data/UI profile and binary hash.
- `test-report.json`, `extended-release.log`, `self-test.log`: 56 checks.
- `network-report.json`: real source/license/file URL, audio duration/hash and live tests.
- `audio-route-report.json`, `audio-devices.txt`: device route assertions/inventory.
- `online-ui-test-report.json`, `online-ui-test.log`: 15 online/migration/denied-network UI checks.
- `ui-test-report.json`, `ui-test.log`: 15 local UI regression checks on the same final binary.
- `media-routing-test-report.json`: synthesized next/previous events, explicitly not physical hardware presses.
- `package-report.json`: final ZIP, extraction, signature/file equality and packaged UI checks.
- `ui-online-search.png`, `ui-online-playing.png`, `ui-embedded-artwork.png`, `ui-network-denied.png`: final screenshots personally inspected.
Older 1.0 reports and intermediate 1.1 evidence remain for history; only the reports tied to the final executable hash are used for current acceptance. In particular old `ui-supplemental-report.json` is historical, not added to current counts.

## Important implementation / environment decisions
- Direct swiftc build avoids broken CLT SwiftPM manifest combinations. This CLT contains duplicate SwiftBridging maps. `build.sh` detects them and creates a local Swift-level `-vfsoverlay` masking only the legacy duplicate. No system SDK/security changes.
- Initial SDK import runs timed out and were stopped. SDK 14.5 fallback and Clang-only overlay failed; Swift-level overlay works. Final `build-1.1.log` has no compiler warnings.
- No extra dependencies/paid services/keys installed: native afconvert generated codecs; its MP3 encoder is unavailable, so real licensed MP3 is tested instead.
- CoreAudio CFString property ownership follows documented caller-release semantics via `takeRetainedValue`.
- Native search testing uses actual CGEvent focus and typing, not AX set-value alone, which can change display without updating SwiftUI. Original Chinese input source is restored at delivery.
- Previous space-input symptom was initially misdiagnosed; controlled ABC input A/B showed IME candidate commit confounded it. No original shortcut defect proven. Explicit focus-aware space handling remains and passes editor/non-editor tests.
- User granted Accessibility permission; no TCC bypass. Tests restore appearance to system and preserve default audio output.

## Honest remaining limits
- **Physical media-key press not performed.** OS event/command chain passes; this is not the same as pressing a hardware key.
- No unconnected Bluetooth/USB or other future devices tested, no subjective audible-quality confirmation. All output devices currently enumerated on this machine were exercised.
- Supported codec/container representatives tested; not every codec profile, bit rate, malformed stream or DRM file. ALAC supported inside M4A; nonstandard raw `.alac` extension no longer advertised/accepted.
- Source licenses are uploader declarations, not an ownership guarantee. Respect attribution/NC/ND/SA terms; this app cannot provide unauthorized mainstream songs.
- Third-party service can be blocked/unavailable in some networks; errors are shown, not concealed. Download-first, not instant streaming.
- No public notarization, universal build, online lyrics or cloud sync.

## Delivery / next step
Current requested local + open-music workflow is implemented and verified. Delivery state: official `dist/Tom Music.app` is open (not the isolated test copy), showing the live Fleurs d'Hiver release with six available songs, without automatically downloading/playing or importing any fixture into the default profile. Chinese input source restored. Open `dist/Tom Music.app`, use 在线免费音乐 for online search or 导入音乐 / ⌘O / Finder drop for own files. ZIP is ready to copy locally. Remaining hardware checks require actual hardware/user interaction and cannot be claimed automatically; otherwise next work should follow user feedback rather than inventing a paid catalogue.


## 1.2 implementation in progress — wider discovery and public webpage extraction
- User requests widest practical coverage, not one source. Add a separate multi-source view while preserving the verified 1.1 free-library path.
- Real probes succeeded: Apple catalog (Chinese pop metadata), ccMixter published Query API (CC full MP3), Audius public search (explicit availability/stream-gating flags), Wikimedia Commons media API, existing Internet Archive.
- Reviewed provider docs: Apple preview assets are promotional-only/not entertainment, streamed-only with badges. Therefore use Apple metadata + official links only; DO NOT turn its previews into full songs or downloadable library entries. Audius authorized public streams only, never download-gated content. ccMixter has a published remote JSON API despite robots excluding API indexing; web crawler separately respects robots.
- Plan bounded concurrent adapters, partial errors, 5-minute metadata cache, throttling/retries, exact-link dedup; single-page HTML audio/OpenGraph/JSON-LD extraction with robots, HTTPS/private-network checks and payload/redirect limits. No login/cookie/DRM bypass, no false all-web promise. Full CC files can save; provider streams remain streaming; generic unknown-rights links require explicit rights confirmation.
- Rollback app saved at `.build/checkpoints/Tom Music-1.1.app`; manifest preserved `evidence/acceptance-1.1.json`. Next: implement + verify final installed workflow, existing regression and crawler edge cases.

### 1.2 implementation milestone (not final acceptance yet)
- Added `PublicNetwork.swift`, `MusicDiscovery.swift`, `PublicAudioResolver.swift`, `DiscoveryView.swift`, `DiscoveryDiagnostics.swift`; native AVPlayer public streaming integrated without persisting remote files/tracks. Existing local AVAudioPlayer path remains.
- Pre-final real run: 77 checks passed (`evidence/discovery-test.log`, isolated path `evidence/discovery-path.txt`). All five live APIs returned results; Chinese Jay Chou query returned official metadata only; ccMixter Observations full MP3 saved/decoded; Audius Piano Fala stream advanced, paused, sought and resumed with library bytes unchanged; Archive page exposed six MP3 + six FLAC links.
- Diagnosed ordinary failures rather than masking them: system VPN resolves public domains to 198.18/15 Fake-IP. Added bounded, fixed Cloudflare DNS-over-HTTPS public-domain A/AAAA validation for Fake-IP only; no proxy/DNS/security setting changes and no blanket private-address allowance. DNS preflight remains defense-in-depth, not a DNS-pinning sandbox.
- ccMixter returns HTTP 403 without its genuine source-page Referer. Its public, explicitly CC-licensed HTML player uses the same API file. Add the actual attribution page as Referer only for known ccMixter licensed downloads, never arbitrary referrer spoofing or credentials. Real MP3 then downloaded successfully.
- Corrected test assumption: Archive page legitimately has 12 supported links (6 FLAC + 6 MP3), not only six. Keep both encodings, show format labels rather than deleting valid sources to satisfy test.
- Added five browser-only official search entries (网易云/QQ/酷狗/B站/YouTube); do not claim these are in-app full-song providers.
- Next: build 1.2/build 3, run final isolated `python3 scripts/verify-release.py --network --discovery` (240s bound), real native new-view workflow, upgrade/offline regressions, package and independently exercise extracted final ZIP.

### Native ZIP acceptance found a recoverable streaming defect
- Final-byte model/live tests passed 124 checks, but actual native first Audius play later failed with AVPlayer `resource unavailable`. Captured `ui-discovery-failure.png`; did not count it as passed or replace the track.
- Same public track metadata subsequently chose another Audius content node and a real Range GET returned HTTP 206 + MP3 bytes. Public-source federation can return a temporarily bad node. Next: bounded same-track metadata/node recovery and explicit client identity, then rebuild/repackage/re-run final checks. Never bypass stream gates or substitute another song.
- Two earlier native test timeouts were harness observation errors: SwiftUI custom DisclosureGroup label is visual but not returned as root static text. Its AXDisclosureTriangle supports AXPress; tests now expand and inspect each real provider status instead of weakening assertions.

### User-requested regression: BTS FAKE LOVE
- User specifically asks to test “feak love of BTS”, then reiterates highest crawler quality. Interpret as BTS “FAKE LOVE”, preserve version/artist accuracy.
- Real API evidence: `evidence/requested-song-test.json`. Apple HK returns BTS/防彈少年團 original FAKE LOVE, 242.334 seconds, plus live/Japanese/remix editions. ccMixter returns zero. Audius returns unverified uploader Ciel with misleading “Official MV” title plus explicitly labeled covers/short cover and irrelevant matches. Did not download an Apple preview or claim these uploads are verified BTS originals.
- Follow-up: rank actual title/artist matches and show version hints; relabel public Audius streams as uploaded audio (not guaranteed original/full song), expose uploader identity/verification. Then exercise requested song in actual native UI and re-run final bytes.
- Previous final-byte checks before this follow-up: 127 model/live/recovery checks; 20 new-view ZIP UI checks; 15 local UI checks. Legacy online UI reached 13 checks; remaining old test incorrectly requires literal “Operation not permitted”, while new fail-closed DNS guard correctly reports “无法解析公开域名” under process network denial. Update assertion to verify the actual DNS/network failure + empty results, not a hard-coded English OS message.

### Latest acceptance requirement and honest blocker
- User now requires every song downloadable and explicitly includes BTS FAKE LOVE. This is a requested acceptance criterion, NOT implemented or passed. No verified authorized full-original BTS download URL/file is available in current adapters; Apple is catalog-only and Audius matching uploads are not verified BTS originals. Do not count original download/offline playback as successful.
- Latest app build passes 130 model/live/recovery/ranking checks. Final ZIP is `dist/Tom Music-1.2.0-macOS-arm64.zip`; latest manifest `evidence/acceptance-path.json`. Native requested-song checks passed: exact FAKE LOVE / 防彈少年團 official entry ranks first, alternate/cover versions and unverified uploads distinguished, no preview or unrelated upload saved. Evidence `ui-bts-fake-love.png`, `ui-bts-upload-warning.png`.
- Latest expanded native run stopped at the bounded 35-second unrelated Audius Piano Fala stream check after six checks; inspect `evidence/discovery-ui.log`, `ui-discovery-failure-tree.txt`. Previous 20-check complete native pass applies to earlier 1.2 bytes before ranking/source-label follow-up, not current bytes. Do not reuse it as current final acceptance.
- Latest legacy online run reached 13 checks; corrected its overly literal offline-error assertion to accept actual fail-closed DNS error + empty results. Full current-byte legacy rerun remains pending. README/final validation synchronization and final acceptance remain pending; no completion claim.
- Additional download integration must check `is_downloadable` + `!is_download_gated` + explicit `access.download` and an official download URL; `access.download=true` alone is NOT enough (Z Piano Medley says is_downloadable=false). Piano Fala has download purchase gate; never convert its public stream into an unrestricted download.

### Final 1.2 verification after continued implementation
- Fixed the recurring native stream failure at its actual routing layer: use Audius official `/v1/tracks/{id}/stream` router after fresh same-track permission checks, rather than a randomly selected federated node. Real official route returned HTTP 206 audio/mpeg from provider-issued storage URL. No mirror/signature guessing, credentials or alternative songs.
- Replaced HEAD preflight with Range GET that intentionally stops at final headers; public clients can differ by HTTP method. User cancellation, redirect rejection and byte limits remain distinct from intentional probe cancellation; metadata URL caching disabled at URLSession layer (bounded app cache remains).
- All current bytes passed 130 model/live checks, 23 discovery/native requested-song checks, 15 local UI checks and all 15 legacy online checks. One real ccMixter timeout was preserved in `release-ccmixter-timeout.log`; a single 3-second-backoff rerun succeeded, no test removed or timeout increased.
- Strengthened old cancellation harness: locate the actual visible progress-row cancel control, verify page stays online and no delayed insertion/autoplay. A prior fixed-index macro clicked navigation; its isolated failed profile/report was retained, not counted as passing. Native file panel now waits for its sheet instead of a fixed 0.3-second delay. Offline assertion checks actual DNS/network failure plus empty source results rather than one English OS message.
- Reproducible commands: `./scripts/build.sh`; `python3 scripts/verify-release.py --network --discovery` (240-second bound); `python3 scripts/package-release.py`; `python3 scripts/verify-discovery-ui.py`; prepare a copy of 1.0 `ui_data` and run `python3 scripts/verify-ui.py`; `python3 scripts/verify-online-ui.py --old-profile OLD_PROFILE --fixtures FIXTURES` (old paths retained in `evidence/acceptance-1.0.json`). Compile helper with `swiftc -vfsoverlay "$PWD/.build/sdk-compat/overlay.json" scripts/ui-input.swift -o .build/ui-input`.
- README and final validation synchronized. This is a verified incremental release, NOT completion of the user's universal-song or BTS-original-download criterion. Next substantive expansion needs a verifiable additional full-audio/download source; do not silently relabel subscription pages, missing files, covers or user uploads as successful original downloads.

## Official in-app online playback request — MusicKit readiness checkpoint
- User now explicitly requests official catalog songs playable online, not just official links. Target native Apple Music ApplicationMusicPlayer (available macOS 14+); preserve no-preview-as-full-song behavior. This feature is NOT implemented or verified in 1.2.
- Reviewed installed public MusicKit Swift interface and Apple docs: `https://developer.apple.com/help/account/services/musickit/`, `https://developer.apple.com/documentation/musickit/using-automatic-token-generation-for-apple-music-api`. Official app ID must enable MusicKit App Service and match the bundle identifier; full catalog playback must check MusicAuthorization + MusicSubscription.canPlayCatalogContent.
- Real isolated readiness probe, same bundle ID `com.tommusic.desktop`, local ad-hoc signature: `DefaultMusicTokenProvider().developerToken(options: [.ignoreCache])` failed with **MusicKit.MusicTokenRequestError code 1, Permission denied**. `security find-identity -v -p codesigning` lists **0 valid identities**. Evidence: `evidence/musickit-readiness.json`. No token bytes emitted or saved; no user authorization requested, no account/subscription inspected, no permission/security/network settings changed.
- Diagnostic source `.build/musickit-probe.swift`, standalone probe bundle `.build/MusicKitProbe.app`. Compile with `swiftc -swift-version 5 -vfsoverlay "$PWD/.build/sdk-compat/overlay.json" -parse-as-library -target arm64-apple-macos14.0 .build/musickit-probe.swift -o ".build/MusicKitProbe.app/Contents/MacOS/MusicKitProbe"`; ad-hoc codesign the diagnostic bundle; execution was bounded at 25 seconds. Released dist app and ZIP bytes are untouched.
- Genuine blocker: need an Apple Developer app/service configuration and usable signing identity for this app, plus user-authorized Apple Music catalog access/active subscription for real full-song acceptance. Do not ask for Apple ID password/private signing key in chat, do not buy membership or modify accounts without authorization. Ask user only for presence of their Apple Music subscription and a locally configurable developer team. Once available: implement native authorization/subscription states, catalog-ID lookup in account storefront, ApplicationMusicPlayer transport and switching, then test real BTS FAKE LOVE full official playback end to end.
- An external official Music app/browser handoff may be offered separately, but it must not be called Tom Music in-app playback or full-song acceptance.
