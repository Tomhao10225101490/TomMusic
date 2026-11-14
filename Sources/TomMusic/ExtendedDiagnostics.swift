import AppKit
import AVFoundation
import MediaPlayer

@MainActor
enum ExtendedDiagnostics {
    static func run(library: MusicLibrary, network: Bool) async throws -> [String] {
        var passed: [String] = []
        func check(_ value: Bool, _ label: String) throws {
            guard value else { throw SelfTest.Failure(description: label) }
            passed.append(label); print("PASS: \(label)")
        }
        let folder = library.root.appendingPathComponent("ExtendedGeneratedFixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formats = [
            ("PCM WAV.wav", "WAVE", "LEI16"), ("AAC M4A.m4a", "m4af", "aac"),
            ("Raw AAC.aac", "adts", "aac"), ("ALAC M4A.m4a", "m4af", "alac"),
            ("FLAC.flac", "flac", "flac"), ("AIFF.aiff", "AIFF", "BEI16"),
            ("AIF.aif", "AIFF", "BEI16"), ("CAF.caf", "caff", "LEI16"),
            ("AAC MP4.mp4", "mp4f", "aac")
        ]
        for (index, spec) in formats.enumerated() {
            let input = folder.appendingPathComponent("input-\(index).wav")
            try tone(input, hz: Double(300 + index * 25))
            let destination = folder.appendingPathComponent(spec.0)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
            process.arguments = ["-f", spec.1, "-d", spec.2, input.path, destination.path]
            let output = Pipe(); process.standardError = output; process.standardOutput = output
            try process.run()
            let deadline = Date().addingTimeInterval(12)
            while process.isRunning && Date() < deadline { try await Task.sleep(nanoseconds: 100_000_000) }
            if process.isRunning { process.terminate(); throw SelfTest.Failure(description: "afconvert exceeded 12 seconds: \(spec.0)") }
            guard process.terminationStatus == 0 else {
                let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                throw SelfTest.Failure(description: "afconvert \(spec.0): \(text)")
            }
            let tracks = await library.importFiles([destination])
            try check(tracks.count == 1, "Import real generated \(spec.0)")
            let player = MusicPlayer(library: library)
            player.volume = 0.01
            player.play(tracks[0], in: [tracks[0]])
            try await Task.sleep(nanoseconds: 450_000_000)
            try check(player.isPlaying && player.position > 0.15 && player.duration > 2, "Actual decoder playback: \(spec.0)")
            player.pause()
        }
        // Embed metadata and image into a real M4A via AVFoundation, not sidecar mocks.
        let source = folder.appendingPathComponent("AAC M4A.m4a")
        let artworkURL = folder.appendingPathComponent("Embedded Artwork.m4a")
        guard let export = AVAssetExportSession(asset: AVURLAsset(url: source), presetName: AVAssetExportPresetPassthrough) else {
            throw SelfTest.Failure(description: "Create artwork metadata exporter")
        }
        export.outputURL = artworkURL; export.outputFileType = .m4a
        let image = NSImage(size: NSSize(width: 192, height: 192))
        image.lockFocus(); NSColor.systemTeal.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: 192, height: 192)).fill()
        ("TEST" as NSString).draw(at: NSPoint(x: 30, y: 80), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 40), .foregroundColor: NSColor.white])
        image.unlockFocus()
        let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        func item(_ id: AVMetadataIdentifier, _ value: NSCopying & NSObjectProtocol) -> AVMutableMetadataItem {
            let item = AVMutableMetadataItem(); item.identifier = id; item.value = value; return item
        }
        let art = item(.commonIdentifierArtwork, png as NSData); art.dataType = "public.png"
        export.metadata = [item(.commonIdentifierTitle, "Generated Artwork Fixture" as NSString),
                           item(.commonIdentifierArtist, "Diagnostic Test Artist" as NSString),
                           item(.commonIdentifierAlbumName, "Diagnostic Test Album" as NSString), art]
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { continuation.resume() }
        }
        guard export.status == .completed else { throw export.error ?? SelfTest.Failure(description: "Export embedded artwork fixture") }
        let artTracks = await library.importFiles([artworkURL])
        try check(artTracks.count == 1 && artTracks[0].title == "Generated Artwork Fixture" && artTracks[0].artist == "Diagnostic Test Artist" && artTracks[0].album == "Diagnostic Test Album", "Embedded title/artist/album metadata extraction")
        try check(library.artwork(for: artTracks[0]) != nil, "Embedded PNG artwork extracts to managed artwork")
        let reopened = MusicLibrary(root: library.root)
        try check(reopened.artwork(for: artTracks[0]) != nil, "Artwork survives library reopen")
        let player = MusicPlayer(library: reopened); player.volume = 0.01
        player.play(artTracks[0], in: [artTracks[0]])
        let now = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        try check(now[MPMediaItemPropertyTitle] as? String == "Generated Artwork Fixture" && now[MPMediaItemPropertyArtwork] is MPMediaItemArtwork, "System Now Playing publishes actual title and embedded artwork")
        player.pause()
        let originalOutput = AudioDiagnostics.defaultOutput()
        let outputs = AudioDiagnostics.outputs()
        try check(!outputs.isEmpty, "CoreAudio enumerates available output devices")
        for output in outputs {
            player.play(artTracks[0], in: [artTracks[0]], outputDeviceUID: output.uid)
            try await Task.sleep(nanoseconds: 500_000_000)
            try check(player.isPlaying && player.position > 0.15 && player.outputDeviceUID == output.uid, "Actual per-player output routing: \(output.name)")
            player.pause()
        }
        try check(AudioDiagnostics.defaultOutput() == originalOutput, "Output route tests preserve user's system default device")
        let routes = try JSONEncoder().encode(outputs)
        try routes.write(to: library.root.appendingPathComponent("audio-route-report.json"))
        try check(ArchiveMusicService.license("https://creativecommons.org/licenses/by/4.0/") != nil && ArchiveMusicService.license("http://creativecommons.org/licenses/by-nc-nd/3.0/") != nil && ArchiveMusicService.license("https://creativecommons.org/publicdomain/zero/1.0/") != nil, "Recognized CC / CC0 license declarations accepted")
        try check(ArchiveMusicService.license("https://creativecommons.org.evil.test/licenses/by/4.0/") == nil && ArchiveMusicService.license("https://example.com/free") == nil && ArchiveMusicService.license("https://creativecommons.org/not-a-license") == nil, "Unknown / spoofed license declarations rejected")
        if network { passed += try await liveNetwork(library: library) }
        return passed
    }
    private static func tone(_ url: URL, hz: Double) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let count: AVAudioFrameCount = 44100 * 3
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        buffer.frameLength = count
        for i in 0..<Int(count) { buffer.floatChannelData![0][i] = Float(sin(Double(i) * 2 * .pi * hz / 44100) * 0.02) }
        let file = try AVAudioFile(forWriting: url, settings: format.settings); try file.write(from: buffer)
    }
    private static func liveNetwork(library: MusicLibrary) async throws -> [String] {
        var passed: [String] = []
        func check(_ value: Bool, _ label: String) throws {
            guard value else { throw SelfTest.Failure(description: label) }
            passed.append(label); print("PASS: \(label)")
        }
        let (releases, _) = try await ArchiveMusicService.search("Fleurs d'Hiver")
        try check(!releases.isEmpty, "Live Internet Archive search returns real openly licensed releases")
        let songs = try await ArchiveMusicService.songs(releases[0])
        guard let song = songs.sorted(by: { $0.bytes < $1.bytes }).first else { throw SelfTest.Failure(description: "Live release has no MP3") }
        try check(!song.release.licenseName.isEmpty && song.bytes > 0, "Live source metadata verifies license and full MP3 file")
        let downloaded = try await ArchiveMusicService.download(song) { _ in }
        defer { try? FileManager.default.removeItem(at: downloaded) }
        let tracks = await library.importFiles([downloaded])
        try check(tracks.count == 1, "Download and import real full licensed MP3, not preview or generated fixture")
        library.recordOrigin(song, for: tracks[0])
        let saved = library.data.tracks.first { $0.id == tracks[0].id }!
        let player = MusicPlayer(library: library); player.volume = 0.01
        player.play(saved, in: [saved])
        try await Task.sleep(nanoseconds: 800_000_000)
        try check(player.isPlaying && player.position > 0.3 && player.duration > 30, "Actual AVAudioPlayer decodes downloaded full MP3")
        player.pause(); player.seek(30)
        try check(abs(player.position - 30) < 0.1, "Downloaded MP3 supports pause and seek")
        let reopened = MusicLibrary(root: library.root)
        try check(reopened.data.tracks.first(where: { $0.id == saved.id })?.origin?.licenseURL == song.origin.licenseURL, "Online source, creator and license persist across restart")
        let duplicate = await library.importFiles([downloaded])
        try check(duplicate.first?.id == saved.id, "Online and local import share SHA-256 deduplication")
        let (nothing, _) = try await ArchiveMusicService.search("TomMusicNoSuchRelease9f78fa7b2")
        try check(nothing.isEmpty, "Live no-result search stays empty, no synthetic fallback")
        var missing = song
        missing.fileName = "TomMusicMissingAudio9f78fa7b2.mp3"
        do {
            let file = try await ArchiveMusicService.download(missing) { _ in }
            try? FileManager.default.removeItem(at: file)
            throw SelfTest.Failure(description: "Missing remote audio unexpectedly downloaded")
        } catch let failure as CatalogFailure {
            try check(failure.message.contains("404"), "Live missing audio returns explicit HTTP error, no substitute audio")
        }
        let cancelled = Task { try await ArchiveMusicService.download(song) { _ in } }
        cancelled.cancel()
        do {
            let file = try await cancelled.value; try? FileManager.default.removeItem(at: file)
            throw SelfTest.Failure(description: "Cancelled network download unexpectedly completed")
        } catch is CancellationError { try check(true, "Cancelled download does not complete or autoplay") }
        catch let error as URLError where error.code == .cancelled { try check(true, "Cancelled download does not complete or autoplay") }
        let report: [String: Any] = ["provider": "Internet Archive (live network)", "release": song.release.title,
                                    "title": saved.title, "creator": song.release.creator, "source": song.release.pageURL.absoluteString,
                                    "audioURL": song.downloadURL.absoluteString, "license": song.release.licenseURL.absoluteString,
                                    "duration": saved.duration, "sha256": saved.id, "checks": passed]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: library.root.appendingPathComponent("network-report.json"))
        return passed
    }
}
