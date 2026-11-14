import AppKit
import AVFoundation
import CryptoKit
import SwiftUI

struct Track: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var fileName: String
    var artworkName: String?
    var addedAt: Date
    var favorite = false
    var trackNumber = 0
    var sourceName: String
    var origin: TrackOrigin?
    var albumKey: String { album + "\u{1f}" + artist }
}

struct Playlist: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var trackIDs: [String] = []
}

struct LibraryData: Codable {
    var tracks: [Track] = []
    var playlists: [Playlist] = []
    var volume: Float = 0.7
}

@MainActor
final class MusicLibrary: ObservableObject {
    @Published var data = LibraryData()
    @Published var importing = false
    @Published var importStatus = ""
    @Published var error: String?
    let root: URL
    private var writable = true
    var mediaFolder: URL { root.appendingPathComponent("Media", isDirectory: true) }
    var artworkFolder: URL { root.appendingPathComponent("Artwork", isDirectory: true) }
    nonisolated static let supported: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "caf", "flac", "mp4"]

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TomMusic", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: mediaFolder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: artworkFolder, withIntermediateDirectories: true)
            let url = self.root.appendingPathComponent("Library.json")
            if FileManager.default.fileExists(atPath: url.path) {
                data = try JSONDecoder().decode(LibraryData.self, from: Data(contentsOf: url))
            }
        } catch {
            writable = false
            self.error = "无法读取音乐库：\(error.localizedDescription)。已禁止写入以保护原始资料，请先备份并修复资料库后重新打开应用。"
        }
    }

    func save() {
        guard writable else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(data).write(to: root.appendingPathComponent("Library.json"), options: .atomic)
        } catch { self.error = "保存失败：\(error.localizedDescription)" }
    }

    func url(for track: Track) -> URL { mediaFolder.appendingPathComponent(track.fileName) }
    func artwork(for track: Track) -> NSImage? {
        guard let name = track.artworkName else { return nil }
        return NSImage(contentsOf: artworkFolder.appendingPathComponent(name))
    }
    func toggleFavorite(_ track: Track) {
        guard let i = data.tracks.firstIndex(where: { $0.id == track.id }) else { return }
        data.tracks[i].favorite.toggle()
        save()
    }
    @discardableResult func createPlaylist(_ name: String) -> UUID? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let item = Playlist(name: clean)
        data.playlists.append(item)
        save()
        return item.id
    }
    func add(_ tracks: [Track], to id: UUID) {
        guard let i = data.playlists.firstIndex(where: { $0.id == id }) else { return }
        for track in tracks where !data.playlists[i].trackIDs.contains(track.id) { data.playlists[i].trackIDs.append(track.id) }
        save()
    }
    func removeFromPlaylist(_ track: Track, id: UUID) {
        guard let i = data.playlists.firstIndex(where: { $0.id == id }) else { return }
        data.playlists[i].trackIDs.removeAll { $0 == track.id }; save()
    }
    func deletePlaylist(_ id: UUID) { data.playlists.removeAll { $0.id == id }; save() }
    func remove(_ track: Track) {
        data.tracks.removeAll { $0.id == track.id }
        for i in data.playlists.indices { data.playlists[i].trackIDs.removeAll { $0 == track.id } }
        save()
        // Only delete our managed copy, never the user's original file.
        try? FileManager.default.removeItem(at: url(for: track))
        if let art = track.artworkName { try? FileManager.default.removeItem(at: artworkFolder.appendingPathComponent(art)) }
    }

    func chooseFiles(folder: Bool = false) {
        let panel = NSOpenPanel()
        panel.title = folder ? "导入音乐文件夹" : "导入音乐"
        panel.prompt = "导入"
        panel.canChooseFiles = !folder
        panel.canChooseDirectories = folder
        panel.allowsMultipleSelection = true
        if !folder { panel.allowedContentTypes = [.audio, .mpeg4Movie] }
        panel.begin { response in
            guard response == .OK else { return }
            Task { @MainActor in await self.importFiles(panel.urls) }
        }
    }

    @discardableResult func importFiles(_ urls: [URL]) async -> [Track] {
        guard writable, !importing else { return [] }
        importing = true
        defer { importing = false }
        let expanded: [URL] = await Task.detached(priority: .userInitiated) { () -> [URL] in
            var result: [URL] = []
            for url in urls {
                var directory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue {
                    if let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                        for case let child as URL in walker where Self.supported.contains(child.pathExtension.lowercased()) { result.append(child) }
                    }
                } else if Self.supported.contains(url.pathExtension.lowercased()) { result.append(url) }
            }
            return result.sorted { $0.path < $1.path }
        }.value
        var imported = 0, skipped = 0
        var accepted: [Track] = []
        var failures: [String] = []
        for (index, source) in expanded.enumerated() {
            importStatus = "正在导入 \(index + 1) / \(expanded.count) · \(source.lastPathComponent)"
            do {
                try Task.checkCancellation()
                let prepared = try await Self.prepare(source)
                try Task.checkCancellation()
                if let existing = data.tracks.first(where: { $0.id == prepared.0.id }) { skipped += 1; accepted.append(existing); continue }
                var track = prepared.0
                try FileManager.default.copyItem(at: source, to: url(for: track))
                if let image = prepared.1 {
                    let name = track.id + ".jpg"
                    try? image.write(to: artworkFolder.appendingPathComponent(name), options: .atomic)
                    track.artworkName = name
                }
                data.tracks.append(track)
                accepted.append(track)
                imported += 1
                save()
            } catch is CancellationError { break }
            catch { failures.append("\(source.lastPathComponent)：\(error.localizedDescription)") }
        }
        importStatus = "已导入 \(imported) 首" + (skipped > 0 ? "，跳过 \(skipped) 首重复歌曲" : "")
        if expanded.isEmpty { error = "未找到支持的音频文件。支持 MP3、M4A、AAC、WAV、AIFF 和 FLAC。" }
        else if !failures.isEmpty { error = "有 \(failures.count) 个文件未能导入：\n" + failures.prefix(5).joined(separator: "\n") }
        return accepted
    }

    func recordOrigin(_ song: OpenSong, for track: Track) {
        guard writable, let i = data.tracks.firstIndex(where: { $0.id == track.id }) else { return }
        data.tracks[i].origin = song.origin
        if track.title == URL(fileURLWithPath: track.sourceName).deletingPathExtension().lastPathComponent { data.tracks[i].title = song.title }
        if track.artist == "未知艺人" { data.tracks[i].artist = song.release.creator }
        if track.album == "未知专辑" { data.tracks[i].album = song.release.title }
        data.tracks[i].sourceName = song.fileName
        save()
    }

    func recordOrigin(_ origin: TrackOrigin, title: String, artist: String, album: String, sourceName: String, for track: Track) {
        guard writable, let i = data.tracks.firstIndex(where: { $0.id == track.id }) else { return }
        if let existing = data.tracks[i].origin, !existing.licenseURL.isEmpty, origin.licenseURL.isEmpty { return }
        data.tracks[i].origin = origin
        if track.title == URL(fileURLWithPath: track.sourceName).deletingPathExtension().lastPathComponent, !title.isEmpty { data.tracks[i].title = title }
        if track.artist == "未知艺人", !artist.isEmpty { data.tracks[i].artist = artist }
        if track.album == "未知专辑", !album.isEmpty { data.tracks[i].album = album }
        data.tracks[i].sourceName = sourceName
        save()
    }

    nonisolated private static func prepare(_ url: URL) async throws -> (Track, Data?) {
        let digest: String = try await Task.detached(priority: .utility) { () throws -> String in
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hash = SHA256()
            while let bytes = try handle.read(upToCount: 1024 * 1024), !bytes.isEmpty { hash.update(data: bytes) }
            let digest = hash.finalize()
            var hex = ""
            for byte in digest { hex += String(format: "%02x", byte) }
            return hex
        }.value
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw NSError(domain: "TomMusic", code: 1, userInfo: [NSLocalizedDescriptionKey: "文件不是有效音频"]) }
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else { throw NSError(domain: "TomMusic", code: 2, userInfo: [NSLocalizedDescriptionKey: "文件不包含音轨"]) }
        let metadata = (try? await asset.load(.commonMetadata)) ?? []
        var title = url.deletingPathExtension().lastPathComponent
        var artist = "未知艺人", album = "未知专辑"
        var image: Data?
        for item in metadata {
            switch item.commonKey {
            case .commonKeyTitle: if let value = try? await item.load(.stringValue), !value.isEmpty { title = value }
            case .commonKeyArtist: if let value = try? await item.load(.stringValue), !value.isEmpty { artist = value }
            case .commonKeyAlbumName: if let value = try? await item.load(.stringValue), !value.isEmpty { album = value }
            case .commonKeyArtwork:
                if let bytes = try? await item.load(.dataValue), let ns = NSImage(data: bytes), let tiff = ns.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) { image = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) }
            default: break
            }
        }
        return (Track(id: digest, title: title, artist: artist, album: album, duration: duration, fileName: digest + "." + url.pathExtension.lowercased(), addedAt: Date(), sourceName: url.lastPathComponent), image)
    }
}

func timeLabel(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "0:00" }
    let value = max(0, Int(seconds))
    return "\(value / 60):\(String(format: "%02d", value % 60))"
}
