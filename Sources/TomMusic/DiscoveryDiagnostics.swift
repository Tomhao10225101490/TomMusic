import AppKit
import Foundation
import AVFoundation

@MainActor
enum DiscoveryDiagnostics {
    static func run(library: MusicLibrary) async throws -> [String] {
        var checks: [String] = []
        var report: [String: Any] = ["date": ISO8601DateFormatter().string(from: Date()), "fixtures": "Parser fixtures are synthetic and never shown as search results. Provider searches, downloads, webpage and AVPlayer stream are real network requests."]
        let reportURL = library.root.appendingPathComponent("discovery-report.json")
        defer {
            report["checks"] = checks
            try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: reportURL)
        }
        func check(_ value: Bool, _ label: String) throws {
            guard value else { throw SelfTest.Failure(description: label) }
            checks.append(label); print("PASS: \(label)"); fflush(stdout)
        }
        var audioPolicy: [String: Any] = ["rights": ["pay": 0, "ugc_pay": 0, "arc_pay": 0, "no_background": 0, "download": 1]]
        try check(NativeAudioPolicy.permits(audioPolicy), "Native audio requires explicit normal public/background/download markers (policy fixture, not rights ownership proof)")
        for (key, value) in [("pay", 1), ("ugc_pay", 1), ("arc_pay", 1), ("no_background", 1), ("download", 0)] {
            audioPolicy["rights"] = ["pay": 0, "ugc_pay": 0, "arc_pay": 0, "no_background": 0, "download": 1].merging([key: value]) { _, new in new }
            try check(!NativeAudioPolicy.permits(audioPolicy), "Native audio refuses restricted marker: \(key)")
        }
        try check(!NativeAudioPolicy.permits([:]) && !NativeAudioPolicy.permits(["rights": [:]]), "Unknown/missing platform permission fields fail closed")
        for bad in ["https://bilivideo.com.evil.test/a", "http://x.bilivideo.com/a", "https://127.0.0.1/a", "https://x.bilivideo.com:4483/a", "https://user:pass@x.bilivideo.com/a"] {
            try check(!NativeAudioPolicy.cdn(URL(string: bad)!), "Native audio rejects unsafe CDN: \(bad)")
        }
        try check(!NativeAudioPolicy.ownCache(library.root.appendingPathComponent("Media/Original.m4a")), "Native audio cleanup cannot delete managed/original music outside its owned UUID cache")
        try check(DiscoveryRanking.version("FAKE LOVE 剪辑版 Instrumental").contains("剪辑版") && DiscoveryRanking.version("FAKE LOVE 剪辑版 Instrumental").contains("伴奏"), "Native song results distinguish edited/instrumental variants")
        let titleFixture = NativeAudioEntry(id: "BV1JV62BaEVo", title: "【4K Hi-Res】BTS《FAKE LOVE》【剪辑版】", uploader: "Fixture", seconds: 243)
        try check(titleFixture.audioTitle == "FAKE LOVE" && titleFixture.version.contains("剪辑版"), "Native display extracts explicit song title while preserving edited-version provenance, not marketing fidelity claims")
        let biliVideo = URL(string: "https://www.bilibili.com/video/BV1JV62BaEVo/?p=2")!
        let embedded = WebMusicRoute.target(biliVideo)
        try check(embedded.host == "player.bilibili.com" && embedded.query?.contains("bvid=BV1JV62BaEVo") == true && embedded.query?.contains("p=2") == true, "Visible platform player uses the same selected Bilibili video and part, never a guessed media URL")
        for bad in ["https://bilibili.com.evil.test/", "https://youtube.com.evil.test/", "https://127.0.0.1/", "https://localhost/", "file:///etc/passwd", "javascript:alert(1)", "http://www.bilibili.com/", "https://user:pass@www.bilibili.com/", "https://www.bilibili.com:8443/"] {
            try check(URL(string: bad).map { !WebMusicRoute.allowed($0) } ?? true, "Web player rejects unsafe or unrelated navigation: \(bad)")
        }
        let webSearch = WebMusicRoute.search("BTS & FAKE LOVE 中", youtube: false)
        try check(URLComponents(url: webSearch, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "BTS & FAKE LOVE 中", "Platform search encodes user keywords without script or query injection")
        for bad in ["http://example.com/a.mp3", "file:///etc/passwd", "https://localhost/a", "https://127.0.0.1/a", "https://[::1]/a", "https://user:password@example.com/", "https://example.com:8443/", "https://router.local/a"] {
            try check((try? PublicWeb.checkedURL(bad)) == nil, "Reject unsafe URL: \(bad)")
        }
        for address in ["127.0.0.1", "10.1.2.3", "172.16.1.1", "192.168.1.1", "100.64.0.1", "169.254.169.254", "0.0.0.0", "::1", "::", "fc00::1", "fe80::1", "::ffff:192.168.0.1"] {
            try check(!PublicWeb.publicIP(address), "Reject private/reserved DNS address: \(address)")
        }
        try check(PublicWeb.publicIP("1.1.1.1") && PublicWeb.publicIP("2606:4700:4700::1111"), "Public IPv4 and IPv6 are accepted")
        try check(!PublicWeb.publicIP("198.18.0.2") && PublicWeb.fakeIP("198.18.0.2"), "VPN Fake-IP is recognized but is never blanket-allowed as public")
        try check(!PublicWeb.publicIP("64:ff9b::192.168.1.1") && !PublicWeb.publicIP("2002:c0a8:101::1"), "IPv6 translation/tunnel ranges cannot conceal private IPv4")
        let robots = RobotsPolicy("User-agent: *\nDisallow: /private\nAllow: /private/public\nDisallow: /*.mp3$\nAllow: /allowed.mp3$\n")
        try check(!robots.allows(URL(string: "https://example.com/private/a")!) && robots.allows(URL(string: "https://example.com/private/public/a")!), "Robots longest path wins")
        try check(!robots.allows(URL(string: "https://example.com/a.mp3")!) && robots.allows(URL(string: "https://example.com/allowed.mp3")!), "Robots wildcard, end anchor and allow precedence")
        try check(!robots.allows(URL(string: "https://example.com/%70rivate/a")!), "Robots normalizes percent-encoded unreserved characters")
        let specific = RobotsPolicy("User-agent: *\nDisallow: /\nUser-agent: TomMusic\nAllow: /music\nDisallow: /other\n")
        try check(specific.allows(URL(string: "https://example.com/music")!) && !specific.allows(URL(string: "https://example.com/other")!), "Robots uses matching agent group")
        let empty = RobotsPolicy("User-agent: TomMusic\nDisallow : \nUser-agent: *\nDisallow: /\n")
        try check(empty.allows(URL(string: "https://example.com/music")!), "Robots empty rule group does not inherit unrelated wildcard restrictions")
        try check(!RobotsPolicy.pathMatches("/*a*a*a*a*a*a*a*a*a*z$", target: "/" + String(repeating: "a", count: 8192)), "Adversarial robots wildcards do not execute a backtracking regex")
        let fixture = """
        <title>Parser &amp; metadata fixture</title>
        <audio src="/song.mp3?x=1&amp;y=2"></audio>
        <source src='/song.mp3?x=1&amp;y=2'>
        <meta property="og:audio" content="https://example.com/other.m4a">
        <a href="/third.flac">Audio</a><a href="javascript:alert(1)">No</a>
        <audio src="http://example.com/insecure.mp3"></audio>
        <audio src="https://127.0.0.1/private.mp3"></audio>
        <audio src="https://audio-ssl.itunes.apple.com/preview.m4a"></audio>
        <script>document.write('<audio src="/script-only.mp3">')</script>
        <script type="application/ld+json">{"@graph":[{"@type":"AudioObject","name":"JSON-LD title","contentUrl":"/fourth.mp3"}]}</script>
        """
        let parsed = HTMLAudioParser.parse(fixture, page: URL(string: "https://example.com/page")!)
        try check(parsed.entries.count == 4, "HTML audio/source/OpenGraph/anchor/JSON-LD extraction and exact-link dedup")
        try check(parsed.entries.allSatisfy { $0.capability == .permission && $0.licenseURL == nil }, "Public links never imply license or complete-song status")
        try check(parsed.entries.contains { $0.mediaURL?.absoluteString == "https://example.com/song.mp3?x=1&y=2" }, "HTML entities and relative URLs resolve correctly")
        try check(!parsed.entries.contains { $0.mediaURL?.path.contains("script-only") == true }, "HTML extraction never executes or scrapes script-generated markup")
        try check(HTMLAudioParser.parse("<html>No audio</html>", page: URL(string: "https://example.com/")!).entries.isEmpty, "Page with no audio has no synthetic fallback")
        try check(HTMLAudioParser.plain("<b>Artist</b> &amp; &#x4e2d;&#25991;") == "Artist & 中文", "Safe metadata HTML stripping and numeric entities")
        let original = DiscoveryEntry(id: "identity-fixture", provider: MusicProvider.apple.rawValue, title: "FAKE LOVE", artist: "防彈少年團", album: "Love Yourself", pageURL: URL(string: "https://music.apple.com/")!, capability: .official)
        var repost = original; repost.provider = MusicProvider.audius.rawValue; repost.title = "BTS 방탄소년단 FAKE LOVE Official MV"; repost.artist = "Ciel"; repost.capability = .stream
        var cover = repost; cover.title = "Fake Love Short Cover Orig. by BTS"
        try check(DiscoveryRanking.score(original, query: "BTS FAKE LOVE") > DiscoveryRanking.score(repost, query: "BTS FAKE LOVE") && DiscoveryRanking.score(original, query: "BTS FAKE LOVE") > DiscoveryRanking.score(cover, query: "BTS FAKE LOVE"), "Requested BTS original catalog match ranks above cover or misleading Official MV upload title")
        try check(cover.versionHint.contains("翻唱") && cover.versionHint.contains("短版") && DiscoveryRanking.version("FAKE LOVE (Japanese Version) Remix").contains("日语版"), "Cover, short, Japanese and remix editions are explicitly distinguished")
        try check(DiscoveryRanking.version("Olivia song").isEmpty, "Version detection does not confuse substrings with Live edition")
        let base: [String: Any] = ["id": "abc123", "permalink": "/artist/title", "title": "Gate fixture", "is_available": true, "is_streamable": true, "is_stream_gated": false, "is_download_gated": true, "access": ["stream": true, "download": false]]
        try check(MusicDiscoveryService.audiusEntry(base)?.capability == .stream, "Audius public stream is separate from download permission")
        var gated = base; gated["is_stream_gated"] = true
        try check(MusicDiscoveryService.audiusEntry(gated)?.capability == .page, "Audius stream gating is not bypassed")
        gated = base; gated["is_available"] = false
        try check(MusicDiscoveryService.audiusEntry(gated)?.capability == .page, "Audius unavailable tracks cannot be streamed")
        gated = base; gated["is_streamable"] = false
        try check(MusicDiscoveryService.audiusEntry(gated)?.capability == .page, "Audius non-streamable metadata does not imply playback")
        gated = base; gated["access"] = ["stream": false]
        try check(MusicDiscoveryService.audiusEntry(gated)?.capability == .page, "Audius explicit access denial takes precedence")
        do { try await PublicWeb.validate(URL(string: "https://localtest.me/music")!); throw SelfTest.Failure(description: "Private DNS target was accepted") }
        catch let error as CatalogFailure { try check(error.message.contains("内网"), "Real DNS/Fake-IP validation rejects domain resolving to loopback without fetching target") }
        let official = MusicDiscoveryService.officialSearches("周杰伦 & piano")
        try check(official.count == 5 && official.allSatisfy { $0.1.scheme == "https" && $0.1.host != nil }, "Additional mainstream platforms use encoded official browser search links only")
        print("DISCOVERY: starting five real provider probes"); fflush(stdout)
        var results: [DiscoveryProviderResult] = []
        await withTaskGroup(of: DiscoveryProviderResult.self) { group in
            for provider in MusicProvider.allCases { group.addTask { await MusicDiscoveryService.search(provider, query: "piano", country: "hk") } }
            for await result in group { results.append(result); print("SOURCE: \(result.provider.rawValue): \(result.entries.count); \(result.error ?? "OK")"); fflush(stdout) }
        }
        report["sources"] = results.map { result -> [String: Any] in
            ["provider": result.provider.rawValue, "count": result.entries.count, "seconds": result.seconds, "error": result.error ?? "", "sample": result.entries.prefix(3).map { ["title": $0.title, "artist": $0.artist, "page": $0.pageURL.absoluteString, "capability": $0.capability.rawValue] }]
        }
        for result in results {
            try check(result.error == nil, "Real \(result.provider.rawValue) API request succeeds")
            try check(!result.entries.isEmpty, "Real \(result.provider.rawValue) returns catalog entries")
        }
        let pop = try await MusicDiscoveryService.apple("周杰伦", country: "hk")
        try check(!pop.isEmpty && pop.allSatisfy { $0.capability == .official && $0.mediaURL == nil }, "Mainstream Chinese pop search returns official metadata, never preview downloads")
        report["chinese_pop"] = pop.prefix(3).map { ["title": $0.title, "artist": $0.artist, "page": $0.pageURL.absoluteString] }
        let cachedURL = MusicDiscoveryService.url("https://itunes.apple.com/search", ["term": "周杰伦", "entity": "song", "limit": "20", "country": "hk"])
        let cachedAt = Date(); _ = try await PublicHTTP.shared.get(cachedURL)
        try check(Date().timeIntervalSince(cachedAt) < 1, "Repeated metadata query uses bounded five-minute cache")
        do { _ = try await PublicHTTP.shared.get(cachedURL, limit: 32); throw SelfTest.Failure(description: "Oversized cached response was accepted") }
        catch is CatalogFailure { try check(true, "Cache respects per-request response size bound") }
        do { _ = try await PublicHTTP.shared.get(MusicDiscoveryService.url("https://ccmixter.org/api/query", ["f": "json", "limit": "1"]), limit: 32, cached: false); throw SelfTest.Failure(description: "Oversized live response was accepted") }
        catch is CatalogFailure { try check(true, "Real network response stops at configured byte limit") }
        do { try await RobotsCache.shared.requireAllowed(URL(string: "https://ccmixter.org/api/query")!); throw SelfTest.Failure(description: "Robots-denied webpage path was accepted") }
        catch is CatalogFailure { try check(true, "Web crawler refuses a real robots-disallowed path; documented API use remains separate") }
        guard let mixter = results.first(where: { $0.provider == .mixter })?.entries.first(where: { $0.capability == .download }), let media = mixter.mediaURL else { throw SelfTest.Failure(description: "No real ccMixter full audio available") }
        print("DISCOVERY: downloading licensed ccMixter audio \(mixter.title)"); fflush(stdout)
        let downloaded = try await PublicAudioDownload.download(media, obeyRobots: false, sourcePage: mixter.pageURL) { _ in }
        defer { try? FileManager.default.removeItem(at: downloaded) }
        guard let saved = await library.importFiles([downloaded]).first else { throw SelfTest.Failure(description: library.error ?? "Real ccMixter import failed") }
        library.recordOrigin(mixter.origin, title: mixter.title, artist: mixter.artist, album: mixter.album, sourceName: media.lastPathComponent, for: saved)
        let player = MusicPlayer(library: library); player.volume = 0.03
        player.play(saved, in: [saved]); try await Task.sleep(nanoseconds: 750_000_000)
        try check(player.isPlaying && player.position > 0.2 && player.duration > 30, "Real ccMixter full MP3 saves, decodes and plays locally")
        player.pause()
        var webCommands: [String] = []
        player.beginWebSession { webCommands.append($0) }
        player.toggle(); player.resume(); player.pause()
        try check(player.webPlaybackActive && !player.isPlaying && webCommands == ["toggle", "play", "pause"], "Web session pauses local audio and forwards native transport rather than double-playing local songs (command fixture)")
        let oldPosition = player.position
        player.seek(100); player.next(); player.previous()
        try check(player.position == oldPosition && player.webPlaybackActive, "Local seek/queue commands cannot silently substitute songs during web playback")
        player.play(saved, in: [saved]); try await Task.sleep(nanoseconds: 350_000_000)
        try check(!player.webPlaybackActive && webCommands.last == "pause" && player.isPlaying && player.position > 0, "Selecting local audio stops web transport and restores actual local playback")
        player.pause()
        print("DISCOVERY: requesting actual standalone audio, no WebView/video renderer"); fflush(stdout)
        let nativeBefore = try Data(contentsOf: library.root.appendingPathComponent("Library.json"))
        let nativeResults = try await NativeAudioService.shared.search("BTS FAKE LOVE")
        try check(!nativeResults.isEmpty && nativeResults.allSatisfy { NativeAudioPolicy.validID($0.id) }, "Normal anonymous platform session retrieves real native song-search results without browser/account cookies")
        let nativeClip = try await NativeAudioService.shared.audio("BV1JV62BaEVo") { _ in }
        defer { NativeAudioPolicy.remove(nativeClip.file) }
        let nativeAsset = AVURLAsset(url: nativeClip.file)
        let nativeVideoTracks = try await nativeAsset.loadTracks(withMediaType: .video)
        let nativeAudioTracks = try await nativeAsset.loadTracks(withMediaType: .audio)
        try check(nativeVideoTracks.isEmpty && !nativeAudioTracks.isEmpty && nativeClip.duration > 230 && nativeClip.bytes > 1_000_000, "Actual selected public edited FAKE LOVE cache has audio tracks, ZERO video tracks and full 242-second duration; not a hidden MV")
        try check(player.playTemporaryAudio(nativeClip), "Actual independent AAC file starts AVAudioPlayer rather than a web player")
        try await Task.sleep(nanoseconds: 650_000_000)
        try check(player.isTemporaryAudio && player.isRemote && !player.webPlaybackActive && player.isPlaying && player.position > 0.2, "Native audio clock advances with native transport, no WebView session and no library insertion")
        player.pause(); let nativePause = player.position; try await Task.sleep(nanoseconds: 450_000_000)
        try check(!player.isPlaying && abs(player.position - nativePause) < 0.3, "Independent native audio pause stops actual decoder clock")
        player.seek(12); player.resume(); try await Task.sleep(nanoseconds: 450_000_000)
        try check(player.isPlaying && player.position > 12.1, "Independent native audio seek/resume controls real decoder")
        player.play(saved, in: [saved]); try await Task.sleep(nanoseconds: 300_000_000)
        try check(!player.isTemporaryAudio && !FileManager.default.fileExists(atPath: nativeClip.file.path) && player.isPlaying, "Switching to local music releases and deletes only owned audio cache")
        player.pause()
        try check(nativeBefore == Data(contentsOf: library.root.appendingPathComponent("Library.json")), "Standalone online audio playback never writes signed URLs or tracks into library")
        report["native_audio"] = ["source": nativeClip.entry.page.absoluteString, "title": nativeClip.entry.title, "uploader": nativeClip.entry.uploader, "version": "public edited video-source independent AAC, not verified official album master", "duration": nativeClip.duration, "bytes": nativeClip.bytes, "audio_tracks": nativeAudioTracks.count, "video_tracks": nativeVideoTracks.count, "cache_deleted_on_switch": true]
        report["download"] = ["title": mixter.title, "artist": mixter.artist, "page": mixter.pageURL.absoluteString, "audio": media.absoluteString, "license": mixter.licenseURL?.absoluteString ?? "", "duration": player.duration, "sha256": saved.id]
        var unlicensed = mixter.origin; unlicensed.licenseURL = ""; unlicensed.licenseName = "Unknown"
        library.recordOrigin(unlicensed, title: "", artist: "", album: "", sourceName: "", for: saved)
        try check(library.data.tracks.first(where: { $0.id == saved.id })?.origin == mixter.origin, "Unknown webpage provenance cannot overwrite existing verified license declaration")
        let cancelledImport = Task { await library.importFiles([downloaded]) }; cancelledImport.cancel()
        let cancelledTracks = await cancelledImport.value
        try check(cancelledTracks.isEmpty, "Cancellation is checked before import commits or deduplicates a track")
        let reopened = MusicLibrary(root: library.root)
        try check(reopened.data.tracks.contains { $0.id == saved.id && $0.origin?.provider == "ccMixter" && $0.origin?.licenseURL == mixter.licenseURL?.absoluteString }, "Multi-source provenance and license persist across library reload")
        let webpage = "https://archive.org/details/fell013"
        let resolution = try await PublicAudioResolver.resolve(webpage)
        report["webpage"] = ["page": webpage, "count": resolution.entries.count, "message": resolution.message, "audio": resolution.entries.compactMap { $0.mediaURL?.absoluteString }]
        try check(resolution.entries.filter { $0.mediaURL?.pathExtension == "mp3" }.count == 6 && resolution.entries.allSatisfy { $0.capability == .permission }, "Real public Archive webpage resolves six MP3s plus separate lossless formats without executing scripts")
        guard let streamEntry = results.first(where: { $0.provider == .audius })?.entries.first(where: { $0.capability == .stream }), let remoteID = streamEntry.remoteID else { throw SelfTest.Failure(description: "No Audius public stream available") }
        let beforeStream = try Data(contentsOf: library.root.appendingPathComponent("Library.json"))
        print("DISCOVERY: streaming real Audius audio \(streamEntry.title)"); fflush(stdout)
        let streamURL = try await MusicDiscoveryService.audiusStream(remoteID)
        player.playRemote(streamURL, title: streamEntry.title, artist: streamEntry.artist, album: streamEntry.album, source: streamEntry.pageURL, provider: streamEntry.provider, retry: { try await MusicDiscoveryService.audiusStream(remoteID) })
        for _ in 0..<100 {
            if player.position > 0.4 || player.error != nil { break }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        report["stream"] = ["title": streamEntry.title, "page": streamEntry.pageURL.absoluteString, "host": streamURL.host ?? "", "duration": player.duration, "position": player.position, "error": player.error ?? ""]
        try check(player.isRemote && player.isPlaying && player.position > 0.4 && player.error == nil, "Real Audius AVPlayer public stream starts and audio clock advances")
        player.pause(); try await Task.sleep(nanoseconds: 400_000_000)
        let pause = player.position; try await Task.sleep(nanoseconds: 500_000_000)
        try check(!player.isPlaying && abs(player.position - pause) < 0.3, "Remote pause stops actual stream clock")
        player.seek(3)
        try await Task.sleep(nanoseconds: 400_000_000)
        try check(abs(player.position - 3) < 0.5, "Remote seek updates actual AVPlayer position")
        player.resume()
        for _ in 0..<40 { if player.position > 3.3 { break }; try await Task.sleep(nanoseconds: 250_000_000) }
        try check(player.position > 3.3, "Remote resume advances from requested seek")
        player.pause()
        // Explicit failure fixture: a nonexistent public file, never a fake song.
        // Recovery fetches the very same authorized Audius track, not a substitute.
        let missing = URL(string: "https://archive.org/download/fell013/TomMusicRecoveryFixtureMissing9f71.mp3")!
        var recoveries = 0
        player.playRemote(missing, title: streamEntry.title, artist: streamEntry.artist, album: streamEntry.album, source: streamEntry.pageURL, provider: streamEntry.provider, retry: {
            recoveries += 1; return try await MusicDiscoveryService.audiusStream(remoteID)
        })
        for _ in 0..<120 { if player.position > 0.4 || player.error != nil { break }; try await Task.sleep(nanoseconds: 250_000_000) }
        try check(recoveries == 1 && player.isPlaying && player.position > 0.4 && player.error == nil, "Explicit missing-file fixture recovers once to the same real authorized Audius track")
        player.pause()
        var failedRetries = 0
        player.playRemote(missing, title: "Bounded recovery diagnostic fixture", artist: "Diagnostic only", album: "Test fixture", source: streamEntry.pageURL, provider: streamEntry.provider, retry: { failedRetries += 1; return missing })
        for _ in 0..<80 { if player.error != nil { break }; try await Task.sleep(nanoseconds: 250_000_000) }
        try check(failedRetries == 1 && player.error != nil && !player.isPlaying, "Permanent failure stops after one AVPlayer recovery; no infinite retry or replacement")
        player.error = nil
        var cancelledRecovery = 0
        player.playRemote(missing, title: "Pause recovery diagnostic fixture", artist: "Diagnostic only", album: "Test fixture", source: streamEntry.pageURL, provider: streamEntry.provider, retry: {
            cancelledRecovery += 1; try await Task.sleep(nanoseconds: 2_000_000_000); return streamURL
        })
        for _ in 0..<60 { if cancelledRecovery == 1 { break }; try await Task.sleep(nanoseconds: 200_000_000) }
        player.pause(); try await Task.sleep(nanoseconds: 2_300_000_000)
        try check(cancelledRecovery == 1 && !player.isPlaying && player.error == nil, "Pause cancels pending remote recovery and cannot restart playback later")
        report["recovery_fixture"] = ["initial": missing.absoluteString, "synthetic": "Intentional nonexistent file; no synthetic audio or demo song", "recovered_same_audius_id": remoteID, "successful_recovery_count": recoveries, "permanent_failure_retry_count": failedRetries, "pause_cancelled": true]
        let afterStream = try Data(contentsOf: library.root.appendingPathComponent("Library.json"))
        try check(beforeStream == afterStream, "Streaming never persists a preview, signed URL or remote track to local library")
        player.play(saved, in: [saved]); try await Task.sleep(nanoseconds: 500_000_000)
        try check(!player.isRemote && player.remoteSource == nil && player.isPlaying && player.position > 0.1, "Switching remote stream back to local saved audio clears stream engine")
        player.pause()
        report["passed"] = true
        return checks
    }
}
