import AppKit
import Foundation
import SwiftUI

struct TrackOrigin: Codable, Hashable {
    var provider: String
    var pageURL: String
    var fileURL: String
    var licenseURL: String
    var licenseName: String
    var creator: String
}

struct OpenRelease: Identifiable, Hashable {
    var id: String
    var title: String
    var creator: String
    var licenseURL: URL
    var licenseName: String
    var pageURL: URL { ArchiveMusicService.url(path: ["details", id]) }
}

struct OpenSong: Identifiable, Hashable {
    var id: String { release.id + "/" + fileName }
    var release: OpenRelease
    var fileName: String
    var title: String
    var seconds: Double
    var bytes: Int64
    var downloadURL: URL { ArchiveMusicService.url(path: ["download", release.id, fileName]) }
    var origin: TrackOrigin {
        TrackOrigin(provider: "Internet Archive", pageURL: release.pageURL.absoluteString,
                    fileURL: downloadURL.absoluteString, licenseURL: release.licenseURL.absoluteString,
                    licenseName: release.licenseName, creator: release.creator)
    }
}

struct CatalogFailure: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

/// Only explicit recognized license declarations are accepted. This is not a
/// guarantee of uploader ownership; the UI links the source and original terms.
enum ArchiveMusicService {
    static let maximumBytes: Int64 = 80 * 1024 * 1024
    static func url(path: [String]) -> URL {
        var result = URL(string: "https://archive.org")!
        for part in path { result.appendPathComponent(part) }
        return result
    }
    static func text(_ value: Any?) -> String {
        if let s = value as? String { return s }
        if let list = value as? [String] { return list.joined(separator: " / ") }
        return ""
    }
    static func license(_ value: Any?) -> (URL, String)? {
        let candidates = (value as? [String]) ?? [text(value)]
        for string in candidates {
            guard var components = URLComponents(string: string),
                  ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
                  ["creativecommons.org", "www.creativecommons.org"].contains(components.host?.lowercased() ?? ""),
                  components.user == nil, components.password == nil, components.port == nil else { continue }
            let path = components.path.lowercased()
            let pattern = "^/licenses/(by|by-sa|by-nd|by-nc|by-nc-sa|by-nc-nd)/(1\\.0|2\\.0|2\\.5|3\\.0|4\\.0)(/[a-z-]+)?/?$"
            var name: String
            if path.range(of: pattern, options: .regularExpression) != nil {
                let parts = path.split(separator: "/")
                name = "CC " + parts[1].uppercased() + " " + parts[2]
            } else if ["/publicdomain/zero/1.0/", "/publicdomain/zero/1.0"].contains(path) { name = "CC0 1.0" }
            else if ["/publicdomain/mark/1.0/", "/publicdomain/mark/1.0"].contains(path) { name = "Public Domain Mark 1.0" }
            else { continue }
            components.scheme = "https"; components.query = nil; components.fragment = nil
            if let url = components.url { return (url, name) }
        }
        return nil
    }
    static func flag(_ value: Any?) -> Bool {
        (value as? Bool == true) || ["true", "1"].contains(text(value).lowercased())
    }
    static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("TomMusic/1.1 (native open-license music player)", forHTTPHeaderField: "User-Agent")
        return request
    }
    static func json(_ url: URL) async throws -> [String: Any] {
        let payload = try await PublicHTTP.shared.get(url, limit: 12 * 1024 * 1024, cached: url.path == "/advancedsearch.php")
        let data = payload.data
        let response = payload.response
        try Task.checkCancellation()
        guard response.statusCode == 200 else {
            throw CatalogFailure(message: "曲源暂时不可用（HTTP \(response.statusCode)），请稍后重试。")
        }
        guard data.count < 12 * 1024 * 1024,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CatalogFailure(message: "曲源返回了无法识别的数据。")
        }
        return object
    }
    static func search(_ query: String, page: Int = 1) async throws -> ([OpenRelease], Int) {
        var components = URLComponents(string: "https://archive.org/advancedsearch.php")!
        var q = "collection:netlabels AND mediatype:audio AND licenseurl:* AND (format:\"VBR MP3\" OR format:\"128Kbps MP3\" OR format:\"MP3\")"
        let clean = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        if !clean.isEmpty {
            let escaped = clean.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            q += " AND (\"" + escaped + "\")"
        }
        components.queryItems = [URLQueryItem(name: "q", value: q), URLQueryItem(name: "output", value: "json"),
                                URLQueryItem(name: "rows", value: "20"), URLQueryItem(name: "page", value: String(max(1, page)))]
            + ["identifier", "title", "creator", "licenseurl"].map { URLQueryItem(name: "fl[]", value: $0) }
        let object = try await json(components.url!)
        guard let response = object["response"] as? [String: Any], let docs = response["docs"] as? [[String: Any]] else {
            throw CatalogFailure(message: "曲源搜索数据不完整。")
        }
        let releases = docs.compactMap { doc -> OpenRelease? in
            let id = text(doc["identifier"])
            guard id.range(of: "^[a-zA-Z0-9_][a-zA-Z0-9_.-]*$", options: .regularExpression) != nil,
                  let (url, name) = license(doc["licenseurl"]) else { return nil }
            let creator = text(doc["creator"])
            return OpenRelease(id: id, title: text(doc["title"]), creator: creator.isEmpty ? "来源未标注艺人" : creator,
                               licenseURL: url, licenseName: name)
        }
        return (releases, response["numFound"] as? Int ?? 0)
    }
    static func songs(_ release: OpenRelease) async throws -> [OpenSong] {
        let object = try await json(url(path: ["metadata", release.id]))
        guard let metadata = object["metadata"] as? [String: Any], let files = object["files"] as? [[String: Any]],
              let (licenseURL, name) = license(metadata["licenseurl"]), !flag(object["is_dark"]),
              !flag(metadata["access-restricted-item"])  else {
            throw CatalogFailure(message: "这条来源没有明确的开放授权，或已限制访问，不能在此播放。")
        }
        var verified = release
        verified.licenseURL = licenseURL; verified.licenseName = name
        return files.compactMap { file -> OpenSong? in
            let filename = text(file["name"])
            let bytes = Int64(text(file["size"])) ?? (file["size"] as? Int64 ?? 0)
            guard filename.lowercased().hasSuffix(".mp3"), !filename.contains("/"), !filename.contains("\\"),
                  bytes > 0, bytes <= maximumBytes, !flag(file["private"]) else { return nil }
            let title = text(file["title"])
            let parts = text(file["length"]).split(separator: ":").compactMap { Double($0) }
            let seconds = parts.reduce(0) { $0 * 60 + $1 }
            return OpenSong(release: verified, fileName: filename,
                            title: title.isEmpty ? (filename as NSString).deletingPathExtension : title,
                            seconds: seconds, bytes: bytes)
        }.sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
    }
    static func download(_ song: OpenSong, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let observer = DownloadLimit(progress: progress)
        var req = request(song.downloadURL); req.timeoutInterval = 60
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 120
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let result: (URL, URLResponse)
        do { result = try await session.download(for: req, delegate: observer) }
        catch {
            if observer.exceededLimit { throw CatalogFailure(message: "音频超过 80 MB，下载已停止。请选择其他歌曲。") }
            throw error
        }
        let (temporary, response) = result
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            try? FileManager.default.removeItem(at: temporary)
            throw CatalogFailure(message: "音频下载失败（HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)）。")
        }
        let size = (try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0, size <= maximumBytes else {
            try? FileManager.default.removeItem(at: temporary)
            throw CatalogFailure(message: "只支持下载 80 MB 以内的单首音频。")
        }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp3")
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }
}

private final class DownloadLimit: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var exceeded = false
    var exceededLimit: Bool { lock.lock(); defer { lock.unlock() }; return exceeded }
    init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let host = request.url?.host?.lowercased() ?? ""
        completionHandler(request.url?.scheme == "https" && (host == "archive.org" || host.hasSuffix(".archive.org")) ? request : nil)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > ArchiveMusicService.maximumBytes || totalBytesExpectedToWrite > ArchiveMusicService.maximumBytes {
            lock.lock(); exceeded = true; lock.unlock()
            downloadTask.cancel(); return
        }
        if totalBytesExpectedToWrite > 0 { progress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))) }
    }
}

@MainActor
final class OnlineCatalog: ObservableObject {
    @Published var query = ""
    @Published var releases: [OpenRelease] = []
    @Published var songs: [OpenSong] = []
    @Published var selected: OpenRelease?
    @Published var searching = false
    @Published var hasSearched = false
    @Published var loadingSongs = false
    @Published var error: String?
    @Published var downloadID: String?
    @Published var progress: Double = 0
    @Published var page = 1
    @Published var total = 0
    private var searchTask: Task<Void, Never>?
    private var songsTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    func search(page: Int = 1) {
        searchTask?.cancel(); songsTask?.cancel()
        searching = true; hasSearched = true; loadingSongs = false; error = nil; releases = []; songs = []; selected = nil
        self.page = page; total = 0
        let query = self.query
        searchTask = Task {
            do {
                let (items, total) = try await ArchiveMusicService.search(query, page: page)
                try Task.checkCancellation()
                self.releases = items; self.total = total; searching = false
            } catch {
                guard !Task.isCancelled else { return }
                self.error = "无法搜索在线音乐：\(error.localizedDescription)"; searching = false
            }
        }
    }
    func select(_ release: OpenRelease) {
        songsTask?.cancel(); selected = release; songs = []; loadingSongs = true; error = nil
        songsTask = Task {
            do {
                let items = try await ArchiveMusicService.songs(release)
                try Task.checkCancellation()
                songs = items; selected = items.first?.release ?? release; loadingSongs = false
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription; loadingSongs = false
            }
        }
    }
    func play(_ song: OpenSong, library: MusicLibrary, player: MusicPlayer) {
        guard downloadID == nil else { return }
        if let existing = library.data.tracks.first(where: { $0.origin?.fileURL == song.downloadURL.absoluteString }),
           FileManager.default.fileExists(atPath: library.url(for: existing).path) {
            player.play(existing, in: [existing]); return
        }
        downloadID = song.id; progress = 0; error = nil
        downloadTask = Task {
            defer { downloadID = nil; downloadTask = nil }
            do {
                let file = try await ArchiveMusicService.download(song) { [weak self] amount in
                    Task { @MainActor in
                        guard self?.downloadID == song.id else { return }
                        self?.progress = amount
                    }
                }
                defer { try? FileManager.default.removeItem(at: file) }
                try Task.checkCancellation()
                let imported = await library.importFiles([file])
                guard let track = imported.first else { throw CatalogFailure(message: library.error ?? "无法将下载的音频导入资料库。") }
                library.recordOrigin(song, for: track)
                try Task.checkCancellation()
                if let saved = library.data.tracks.first(where: { $0.id == track.id }) { player.play(saved, in: [saved]) }
            } catch {
                guard !Task.isCancelled, (error as? URLError)?.code != .cancelled else { return }
                self.error = "下载或播放失败：\(error.localizedDescription)"
            }
        }
    }
    func cancelDownload() { downloadTask?.cancel() }
}

struct OnlineMusicView: View {
    @ObservedObject var catalog: OnlineCatalog
    @EnvironmentObject var library: MusicLibrary
    @EnvironmentObject var player: MusicPlayer
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("在线免费音乐").font(.system(size: 29, weight: .bold))
            Text("搜索 Internet Archive 开放授权音乐；以独立音乐为主，不是付费流行歌曲全集。")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                TextField("搜索免费音乐，例如 piano、jazz、ambient", text: $catalog.query)
                    .textFieldStyle(.roundedBorder).onSubmit { catalog.search() }.accessibilityLabel("搜索免费音乐")
                Button("搜索") { catalog.search() }.buttonStyle(.borderedProminent).disabled(catalog.searching)
                Button("浏览") { catalog.query = ""; catalog.search() }.disabled(catalog.searching)
            }
            Text("点击「下载并播放」会下载整首 MP3 并存入你的资料库，之后可离线听。授权以来源声明为准，请遵守署名、非商用等具体条款。")
                .font(.caption).foregroundStyle(.secondary)
            if let error = catalog.error {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(error).font(.callout).textSelection(.enabled)
                    Spacer()
                    Button("关闭提示") { catalog.error = nil }
                }.padding(10).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            if catalog.searching { HStack { ProgressView().controlSize(.small); Text("正在搜索真实曲源…").foregroundStyle(.secondary) } }
            if catalog.downloadID != nil {
                HStack {
                    ProgressView(value: catalog.progress).frame(width: 150)
                    Text("正在下载完整音频 \(Int(catalog.progress * 100))%").font(.caption)
                    Button("取消下载") { catalog.cancelDownload() }
                }
            }
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("音乐发行 / 专辑").font(.headline)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(catalog.releases) { release in
                                Button { catalog.select(release) } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(release.title).font(.system(size: 13, weight: .semibold)).lineLimit(3)
                                        Text(release.creator).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                        Text(release.licenseName).font(.system(size: 10)).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                        .background(catalog.selected?.id == release.id ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                                }.buttonStyle(.plain).accessibilityLabel("打开发行 \(release.title)")
                            }
                            if catalog.releases.isEmpty && !catalog.searching {
                                Text(catalog.error != nil ? "曲源请求未完成，请重试。" : !catalog.hasSearched ? "输入关键词搜索，或点击「浏览」。\n没有结果时可试试英文关键词。" : catalog.total == 0 ? "没有找到开放授权音乐。\n可试试 piano、jazz、ambient 等关键词。" : "本页没有符合开放授权条件的记录，请翻页或更换关键词。")
                                    .font(.callout).foregroundStyle(.secondary).padding(.vertical)
                            }
                        }
                    }
                    HStack {
                        Button("上一页") { catalog.search(page: catalog.page - 1) }.disabled(catalog.page <= 1 || catalog.searching)
                        Text("第 \(catalog.page) 页").font(.caption).foregroundStyle(.secondary)
                        Button("下一页") { catalog.search(page: catalog.page + 1) }.disabled(catalog.page * 20 >= catalog.total || catalog.searching)
                    }
                }.frame(width: 248).padding(.trailing, 18)
                Divider()
                songContent.padding(.leading, 20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }.frame(maxHeight: .infinity)
        }.padding(28)
    }
    @ViewBuilder private var songContent: some View {
        if let release = catalog.selected {
            VStack(alignment: .leading, spacing: 12) {
                Text(release.title).font(.title2.bold()).lineLimit(3)
                Text(release.creator).font(.callout).foregroundStyle(.secondary)
                HStack { Link("查看来源", destination: release.pageURL); Link(release.licenseName, destination: release.licenseURL) }.font(.caption)
                if catalog.loadingSongs { ProgressView("正在读取歌曲…").controlSize(.small) }
                else if catalog.songs.isEmpty { Text("这条发行暂无可播放的公开 MP3（单首需小于 80 MB）。请选其他发行。 ").foregroundStyle(.secondary) }
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(catalog.songs) { song in
                            VStack(alignment: .leading, spacing: 9) {
                                Text(song.title).font(.system(size: 14, weight: .medium)).lineLimit(2)
                                HStack {
                                    Text((song.seconds > 0 ? timeLabel(song.seconds) + " · " : "") + ByteCountFormatter.string(fromByteCount: song.bytes, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    let saved = library.data.tracks.contains { $0.origin?.fileURL == song.downloadURL.absoluteString }
                                    Button(saved ? "播放" : "下载并播放") { catalog.play(song, library: library, player: player) }
                                        .disabled(catalog.downloadID != nil || library.importing)
                                        .accessibilityLabel("\(saved ? "播放" : "下载并播放") \(song.title)")
                                }
                            }.padding(12).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "globe").font(.system(size: 35)).foregroundStyle(.secondary)
                Text("免费、合法，发现新的旋律。").font(.title3.bold())
                Text("先搜索，再选择左侧的音乐发行。来源不可用时会明确报错，不会用演示数据替代。\n\n你自己的音乐仍可通过左下角「导入音乐」、⌘O 或拖放导入。")
                    .font(.callout).foregroundStyle(.secondary).lineSpacing(5)
            }.padding(.top, 30)
        }
    }
}
