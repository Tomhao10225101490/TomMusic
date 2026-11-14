import AppKit
import AVFoundation

/// Explicit diagnostic mode, always requires an isolated --data-dir. No sample music is shipped in the library.
@MainActor
enum SelfTest {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static func run(library: MusicLibrary) async {
        var checks: [String] = []
        func check(_ condition: Bool, _ label: String) throws {
            guard condition else { throw Failure(description: label) }
            checks.append(label)
            print("PASS: \(label)")
        }
        do {
            guard ProcessInfo.processInfo.arguments.contains("--data-dir"), library.data.tracks.isEmpty else { throw Failure(description: "Self-test requires an explicit empty isolated --data-dir") }
            let fixtures = library.root.appendingPathComponent("GeneratedFixtures")
            try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
            for (name, hz) in [("Test Tone A", 440.0), ("Test Tone B", 554.37)] {
                let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
                let frames: AVAudioFrameCount = 44100 * 8
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
                buffer.frameLength = frames
                for i in 0..<Int(frames) { buffer.floatChannelData![0][i] = Float(sin(Double(i) * 2 * .pi * hz / 44100) * 0.06) }
                let file = try AVAudioFile(forWriting: fixtures.appendingPathComponent(name + ".wav"), settings: format.settings)
                try file.write(from: buffer)
            }
            await library.importFiles([fixtures])
            try check(library.data.tracks.count == 2, "Folder import reads two generated WAV fixtures")
            await library.importFiles([fixtures])
            try check(library.data.tracks.count == 2, "SHA-256 import deduplication")
            let first = library.data.tracks[0], second = library.data.tracks[1]
            try check(first.duration > 7.9, "AVFoundation reads real audio duration")
            library.toggleFavorite(first)
            let playlist = library.createPlaylist("Diagnostic playlist")!
            library.add([first, second, first], to: playlist)
            try check(library.data.playlists[0].trackIDs.count == 2, "Playlist membership deduplicates")
            let reopened = MusicLibrary(root: library.root)
            try check(reopened.data.tracks.count == 2 && reopened.data.tracks[0].favorite && reopened.data.playlists[0].trackIDs.count == 2, "Library, favorites and playlists persist across new model instance")
            let player = MusicPlayer(library: reopened)
            player.volume = 0.05
            player.play(first, in: [first, second])
            try await Task.sleep(nanoseconds: 700_000_000)
            try check(player.isPlaying && player.position > 0.2, "Real AVAudioPlayer starts and advances")
            player.pause()
            let paused = player.position
            try await Task.sleep(nanoseconds: 350_000_000)
            try check(!player.isPlaying && abs(player.position - paused) < 0.3, "Pause stops audio clock")
            player.seek(3)
            try check(abs(player.position - 3) < 0.05, "Seek updates real audio position")
            player.resume()
            player.next()
            try check(player.current?.id == second.id && player.isPlaying, "Next track plays queued audio")
            player.previous()
            try check(player.current?.id == first.id, "Previous track restores playback history")
            player.repeatMode = 2
            player.seek(player.duration - 0.15)
            player.resume()
            try await Task.sleep(nanoseconds: 650_000_000)
            try check(player.isPlaying && player.position < 2, "Single-track repeat works at actual audio completion")
            player.pause()
            player.repeatMode = 1
            player.play(second, in: [second])
            player.next()
            try check(player.current?.id == second.id && player.queue.isEmpty, "Repeat-all stays within selected playlist, not entire library")
            player.pause()
            library.data.volume = 0.23
            library.save()
            try check(abs(MusicLibrary(root: library.root).data.volume - 0.23) < 0.001, "Volume persists in isolated library")
            let damagedRoot = library.root.appendingPathComponent("CorruptionTest")
            try FileManager.default.createDirectory(at: damagedRoot, withIntermediateDirectories: true)
            let damagedFile = damagedRoot.appendingPathComponent("Library.json")
            let damagedBytes = Data("deliberately invalid JSON for diagnostic test".utf8)
            try damagedBytes.write(to: damagedFile)
            let damaged = MusicLibrary(root: damagedRoot)
            damaged.save()
            try check(damaged.error != nil && (try? Data(contentsOf: damagedFile)) == damagedBytes, "Corrupt library reports error and cannot be overwritten by save")
            library.removeFromPlaylist(first, id: playlist)
            try check(library.data.playlists[0].trackIDs == [second.id], "Remove from playlist keeps other track")
            library.remove(first)
            try check(!FileManager.default.fileExists(atPath: library.url(for: first).path) && FileManager.default.fileExists(atPath: fixtures.appendingPathComponent("Test Tone A.wav").path), "Library removal deletes managed copy, preserves original")
            try check(MusicLibrary(root: library.root).data.tracks.count == 1, "Removal is durable")
            if ProcessInfo.processInfo.arguments.contains("--extended-test") || ProcessInfo.processInfo.arguments.contains("--network-test") {
                checks += try await ExtendedDiagnostics.run(library: library, network: ProcessInfo.processInfo.arguments.contains("--network-test"))
            }
            if ProcessInfo.processInfo.arguments.contains("--discovery-test") {
                checks += try await DiscoveryDiagnostics.run(library: library)
            }
            let report: [String: Any] = ["passed": true, "checks": checks, "fixture": "Generated diagnostic audio; --network-test also plays a real openly licensed Internet Archive MP3 (see network-report.json)", "date": ISO8601DateFormatter().string(from: Date())]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: library.root.appendingPathComponent("test-report.json"))
            print("SELF-TEST PASSED: \(checks.count) checks")
            fflush(stdout)
            exit(0)
        } catch {
            print("SELF-TEST FAILED: \(error)")
            fflush(stdout)
            exit(1)
        }
    }
}
