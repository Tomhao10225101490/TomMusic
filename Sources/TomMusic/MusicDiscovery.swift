import Foundation
import SwiftUI

// Capabilities describe what the provider actually permits, not a promise of
// universal availability. Apple catalog metadata never becomes a full-song URL.
enum DiscoveryCapability: String, CaseIterable {
    case download = "授权音频可保存"
    case stream = "公开音轨在线播放"
    case album = "发行 / 展开音轨"
    case official = "官方目录 · 前往来源"
    case page = "来源页面"
    case permission = "音频链接 · 需确认权限"
}

enum MusicProvider: String, CaseIterable, Identifiable {
    case archive = "Internet Archive", mixter = "ccMixter", audius = "Audius", commons = "Wikimedia Commons", apple = "Apple 目录"
    var id: String { rawValue }
}

struct DiscoveryEntry: Identifiable, Hashable {
    var id: String
    var provider: String
    var title: String
    var artist: String
    var album: String
    var pageURL: URL
    var mediaURL: URL?
    var capability: DiscoveryCapability
    var licenseURL: URL?
    var licenseName: String = ""
    var seconds: Double = 0
    var note: String = ""
    var release: OpenRelease?
    var remoteID: String?
    var uploaderVerified: Bool? = nil
    var versionHint: String { DiscoveryRanking.version(title + " " + album) }
    var origin: TrackOrigin {
        TrackOrigin(provider: provider, pageURL: pageURL.absoluteString, fileURL: mediaURL?.absoluteString ?? "",
                    licenseURL: licenseURL?.absoluteString ?? "", licenseName: licenseName.isEmpty ? "用户确认使用权限；未声明开放授权" : licenseName, creator: artist)
    }
    var dedupKey: String { PublicWeb.canonical(mediaURL ?? pageURL) + "|" + capability.rawValue }
}

struct DiscoveryProviderResult {
    var provider: MusicProvider
    var entries: [DiscoveryEntry]
    var error: String?
    var seconds: Double
}

enum DiscoveryRanking {
    static func normalized(_ value: String) -> String {
        var text = value.lowercased()
        // Widely used aliases, not a claim of uploader identity or copyright.
        for alias in ["防彈少年團", "防弹少年团", "방탄소년단", "bangtan boys"] { text = text.replacingOccurrences(of: alias, with: "bts") }
        return text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    static func version(_ value: String) -> String {
        var labels: [String] = []
        for (pattern, label) in [("\\bcover\\b|翻唱", "翻唱"), ("\\bshort\\b|短版|片段", "短版"), ("\\blive\\b|现场|現場", "现场版"), ("\\bjapanese\\b|日语|日語", "日语版"), ("\\bremix\\b|\\brework\\b|\\bmix\\b|混音", "混音版"), ("剪辑|剪輯|\\bedited\\b", "剪辑版"), ("伴奏|\\binstrumental\\b", "伴奏"), ("AI音乐|AI合成|AI翻唱", "AI 合成"), ("加长|加長|\\bextended\\b", "加长版"), ("降调|降調|变速|變速|\\bslowed\\b", "变调/变速")] {
            if value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil { labels.append(label) }
        }
        return labels.joined(separator: " / ")
    }
    static func score(_ entry: DiscoveryEntry, query: String) -> Int {
        let terms = normalized(query).split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return 0 }
        let title = normalized(entry.title), artist = normalized(entry.artist), combined = title + " " + artist
        let matches = terms.filter { combined.contains($0) }.count
        var score = matches * 30 + (matches == terms.count ? 100 : 0)
        let songTerms = terms.filter { !artist.split(separator: " ").map(String.init).contains($0) }
        if !songTerms.isEmpty, title == songTerms.joined(separator: " ") { score += 60 }
        if entry.capability == .official, matches > 0 { score += 20 }
        if !entry.versionHint.isEmpty { score -= 25 }
        if entry.provider == MusicProvider.audius.rawValue { score -= 15 }
        return score
    }
}

enum MusicDiscoveryService {
    static func url(_ base: String, _ query: [String: String]) -> URL {
        var parts = URLComponents(string: base)!
        parts.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return parts.url!
    }
    static func officialSearches(_ query: String) -> [(String, URL)] {
        let clean = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        let encoded = clean.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        return [
            ("网易云音乐", URL(string: "https://music.163.com/#/search/m/?s=\(encoded)&type=1")!),
            ("QQ 音乐", url("https://y.qq.com/n/ryqq/search", ["w": clean, "t": "song"])),
            ("酷狗音乐", URL(string: "https://www.kugou.com/yy/html/search.html#searchType=song&searchKeyWord=\(encoded)")!),
            ("B站", url("https://search.bilibili.com/all", ["keyword": clean])),
            ("YouTube", url("https://www.youtube.com/results", ["search_query": clean]))
        ]
    }
    static func string(_ value: Any?) -> String { ArchiveMusicService.text(value) }
    static func safeURL(_ value: Any?) -> URL? { try? PublicWeb.checkedURL(string(value)) }
    static func seconds(_ value: String) -> Double { value.split(separator: ":").compactMap { Double($0) }.reduce(0) { $0 * 60 + $1 } }
    static func search(_ provider: MusicProvider, query: String, country: String) async -> DiscoveryProviderResult {
        let start = Date()
        do {
            let entries: [DiscoveryEntry]
            switch provider {
            case .apple: entries = try await apple(query, country: country)
            case .mixter: entries = try await mixter(query)
            case .audius: entries = try await audius(query)
            case .commons: entries = try await commons(query)
            case .archive: entries = try await archive(query)
            }
            try Task.checkCancellation()
            return DiscoveryProviderResult(provider: provider, entries: entries, seconds: Date().timeIntervalSince(start))
        } catch {
            return DiscoveryProviderResult(provider: provider, entries: [], error: error.localizedDescription, seconds: Date().timeIntervalSince(start))
        }
    }
    static func apple(_ query: String, country: String) async throws -> [DiscoveryEntry] {
        let country = ["hk", "cn", "us", "gb", "jp"].contains(country) ? country : "hk"
        let object = try await PublicHTTP.shared.json(url("https://itunes.apple.com/search", ["term": query, "entity": "song", "limit": "20", "country": country])) as? [String: Any]
        guard let results = object?["results"] as? [[String: Any]] else { throw CatalogFailure(message: "Apple 目录响应不完整。") }
        return results.compactMap { value in
            guard let id = value["trackId"] as? Int, let page = safeURL(value["trackViewUrl"]),
                  ["music.apple.com", "itunes.apple.com"].contains(page.host ?? "") else { return nil }
            return DiscoveryEntry(id: "apple:\(country):\(id)", provider: MusicProvider.apple.rawValue, title: string(value["trackName"]), artist: string(value["artistName"]), album: string(value["collectionName"]), pageURL: page, capability: .official, seconds: (value["trackTimeMillis"] as? Double ?? 0) / 1000,
                                  note: "仅目录与官方链接；此时长是原曲时长，不表示本应用能播放整曲。试听素材不下载、不充当免费整曲。")
        }
    }
    static func mixter(_ query: String) async throws -> [DiscoveryEntry] {
        let value = try await PublicHTTP.shared.json(url("https://ccmixter.org/api/query", ["f": "json", "search_type": "all", "search": query, "tags": "remix", "limit": "10"]))
        guard let uploads = value as? [[String: Any]] else { throw CatalogFailure(message: "ccMixter 响应不完整。") }
        return uploads.compactMap { upload in
            guard let license = ArchiveMusicService.license(upload["license_url"]), let page = safeURL(upload["file_page_url"]), page.host == "ccmixter.org",
                  let files = upload["files"] as? [[String: Any]], let file = files.first(where: { file in
                      let bytes = file["file_rawsize"] as? Int64 ?? Int64(string(file["file_rawsize"])) ?? 0
                      return safeURL(file["download_url"])?.pathExtension.lowercased() == "mp3" && bytes > 0 && bytes <= ArchiveMusicService.maximumBytes
                  }), let media = safeURL(file["download_url"]), media.host == "ccmixter.org" else { return nil }
            let format = file["file_format_info"] as? [String: Any] ?? [:]
            return DiscoveryEntry(id: "mixter:\(upload["upload_id"] ?? "")", provider: MusicProvider.mixter.rawValue,
                                  title: HTMLAudioParser.plain(string(upload["upload_name"])), artist: HTMLAudioParser.plain(string(upload["user_real_name"])), album: "ccMixter", pageURL: page, mediaURL: media, capability: .download,
                                  licenseURL: license.0, licenseName: license.1, seconds: seconds(string(format["ps"])), note: "来源声明 Creative Commons 授权；保留署名及具体授权条款。")
        }
    }
    static func audius(_ query: String) async throws -> [DiscoveryEntry] {
        let object = try await PublicHTTP.shared.json(url("https://discoveryprovider.audius.co/v1/tracks/search", ["query": query, "app_name": "TomMusic", "limit": "10"])) as? [String: Any]
        guard let tracks = object?["data"] as? [[String: Any]] else { throw CatalogFailure(message: "Audius 响应不完整。") }
        return tracks.compactMap(audiusEntry)
    }
    static func audiusEntry(_ value: [String: Any]) -> DiscoveryEntry? {
        let id = string(value["id"]), permalink = string(value["permalink"])
        guard id.range(of: "^[a-zA-Z0-9]+$", options: .regularExpression) != nil, permalink.hasPrefix("/"), !permalink.hasPrefix("//"),
              let page = URL(string: "https://audius.co" + permalink), page.host == "audius.co" else { return nil }
        let user = value["user"] as? [String: Any] ?? [:]
        let access = value["access"] as? [String: Any] ?? [:]
        let allowed = ArchiveMusicService.flag(value["is_available"]) && ArchiveMusicService.flag(value["is_streamable"]) && !ArchiveMusicService.flag(value["is_stream_gated"]) && (access["stream"] as? Bool != false)
        return DiscoveryEntry(id: "audius:" + id, provider: MusicProvider.audius.rawValue, title: string(value["title"]), artist: string(user["name"]), album: "Audius", pageURL: page,
                              capability: allowed ? .stream : .page, seconds: value["duration"] as? Double ?? 0,
                              note: allowed ? "公开用户上传 · \(ArchiveMusicService.flag(user["is_verified"]) ? "平台认证上传者" : "未认证上传者") @\(String(string(user["handle"]).prefix(80)))。可播标记不等于已核验原唱、完整版或版权归属；仅流播，不保存音频。" : "来源标记为不可公开播放或需要额外授权，请前往来源。", remoteID: id, uploaderVerified: ArchiveMusicService.flag(user["is_verified"]))
    }
    static func audiusStream(_ id: String) async throws -> URL {
        guard id.range(of: "^[a-zA-Z0-9]+$", options: .regularExpression) != nil else { throw CatalogFailure(message: "无效的 Audius 音轨。") }
        // Use the provider's official stream router, not a randomly selected node.
        // Probe the real GET method with Range, stopping at response headers.
        // Recheck stream gates each attempt; never guess mirrors or signatures.
        for attempt in 0...1 {
            let object = try await PublicHTTP.shared.json(url("https://discoveryprovider.audius.co/v1/tracks/" + id, ["app_name": "TomMusic"]), cached: false) as? [String: Any]
            guard let track = object?["data"] as? [String: Any], audiusEntry(track)?.capability == .stream else { throw CatalogFailure(message: "来源不允许公开播放，未尝试绕过授权。") }
            let audio = url("https://discoveryprovider.audius.co/v1/tracks/\(id)/stream", ["app_name": "TomMusic"])
            do {
                let probe = try await PublicHTTP.shared.audioProbe(audio)
                let status = probe.response.statusCode, mime = probe.response.mimeType ?? ""
                if [200, 206].contains(status), mime.hasPrefix("audio/") || mime == "application/octet-stream" { return probe.response.url ?? audio }
                if attempt == 1 { throw CatalogFailure(message: "同一音轨的公开节点仍不可用（HTTP \(status)），未换歌或绕过权限。") }
            } catch {
                try Task.checkCancellation()
                if attempt == 1 { throw error }
            }
            try await Task.sleep(nanoseconds: 900_000_000)
        }
        throw CatalogFailure(message: "来源音频暂时不可用。")
    }
    static func commons(_ query: String) async throws -> [DiscoveryEntry] {
        let escaped = query.replacingOccurrences(of: "\"", with: " ")
        let object = try await PublicHTTP.shared.json(url("https://commons.wikimedia.org/w/api.php", ["action": "query", "generator": "search", "gsrsearch": escaped + " filetype:audio", "gsrnamespace": "6", "gsrlimit": "10", "prop": "imageinfo", "iiprop": "url|mime|extmetadata|size", "format": "json"])) as? [String: Any]
        if let error = object?["error"] as? [String: Any] { throw CatalogFailure(message: string(error["info"])) }
        let pages = (object?["query"] as? [String: Any])?["pages"] as? [String: [String: Any]] ?? [:]
        return pages.values.compactMap { value in
            guard let info = (value["imageinfo"] as? [[String: Any]])?.first, let media = safeURL(info["url"]), media.host == "upload.wikimedia.org", let page = safeURL(info["descriptionurl"]), page.host == "commons.wikimedia.org" else { return nil }
            let metadata = info["extmetadata"] as? [String: [String: Any]] ?? [:]
            let license = ArchiveMusicService.license(metadata["LicenseUrl"]?["value"])
            let supported = MusicLibrary.supported.contains(media.pathExtension.lowercased())
            let title = HTMLAudioParser.plain(string(metadata["ObjectName"]?["value"]))
            return DiscoveryEntry(id: "commons:\(value["pageid"] ?? "")", provider: MusicProvider.commons.rawValue, title: title.isEmpty ? string(value["title"]) : title, artist: HTMLAudioParser.plain(string(metadata["Artist"]?["value"])), album: "Wikimedia Commons", pageURL: page,
                                  mediaURL: supported && license != nil ? media : nil, capability: supported && license != nil ? .download : .page,
                                  licenseURL: license?.0, licenseName: license?.1 ?? HTMLAudioParser.plain(string(metadata["LicenseShortName"]?["value"])),
                                  note: supported && license != nil ? "来源声明开放授权；保留作者与原始条款。" : "来源可能提供 OGG 等当前解码器不支持的格式，或授权需人工核对；请前往文件页。")
        }.sorted { $0.title < $1.title }
    }
    static func archive(_ query: String) async throws -> [DiscoveryEntry] {
        // Reuses the verified adapter. Album expansion is explicit, not an unbounded fan-out.
        let (releases, _) = try await ArchiveMusicService.search(query)
        return releases.map { release in
            DiscoveryEntry(id: "archive:" + release.id, provider: MusicProvider.archive.rawValue, title: release.title, artist: release.creator, album: release.title, pageURL: release.pageURL, capability: .album,
                           licenseURL: release.licenseURL, licenseName: release.licenseName, note: "先展开音轨，再选择可保存的完整音频。", release: release)
        }
    }
    static func expand(_ release: OpenRelease) async throws -> [DiscoveryEntry] {
        try await ArchiveMusicService.songs(release).map { song in
            DiscoveryEntry(id: "archive-track:" + song.id, provider: MusicProvider.archive.rawValue, title: song.title, artist: song.release.creator, album: song.release.title, pageURL: song.release.pageURL, mediaURL: song.downloadURL, capability: .download,
                           licenseURL: song.release.licenseURL, licenseName: song.release.licenseName, seconds: song.seconds, note: "来源声明开放授权；完整音频，不是试听片段。")
        }
    }
}

@MainActor
final class DiscoveryCatalog: ObservableObject {
    @Published var query = ""
    @Published var country = "hk"
    @Published var filter = "全部"
    @Published var resultQuery = ""
    @Published var entries: [DiscoveryEntry] = []
    @Published var statuses: [DiscoveryProviderResult] = []
    @Published var searching = false
    @Published var hasSearched = false
    @Published var error: String?
    @Published var busyID: String?
    @Published var progress: Double = 0
    @Published var publicURL = ""
    @Published var resolved: [DiscoveryEntry] = []
    @Published var resolving = false
    @Published var resolverMessage = ""
    @Published var confirmRights = false
    private var searchTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?
    private var resolveTask: Task<Void, Never>?
    private var generation = UUID()
    var filtered: [DiscoveryEntry] {
        let selected = filter == "全部" ? entries : entries.filter { $0.provider == filter }
        // A source filter retains that provider's own semantic/tag ranking.
        guard filter == "全部" else { return selected }
        let ranked: [(index: Int, entry: DiscoveryEntry, score: Int)] = selected.enumerated().map { item in
            (index: item.offset, entry: item.element, score: DiscoveryRanking.score(item.element, query: resultQuery))
        }
        let ordered = ranked.sorted { a, b in a.score == b.score ? a.index < b.index : a.score > b.score }
        return ordered.map { $0.entry }
    }
    var uniqueCount: Int { entries.count }
    func search() {
        let clean = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        guard !clean.isEmpty else { error = "请输入歌曲、歌手或专辑关键词。"; return }
        searchTask?.cancel(); generation = UUID()
        let token = generation, country = country
        searching = true; hasSearched = true; resultQuery = clean; entries = []; statuses = []; error = nil
        searchTask = Task {
            let providers = MusicProvider.allCases
            await withTaskGroup(of: DiscoveryProviderResult.self) { group in
                var next = 0
                // Bounded concurrency: at most 3 provider searches in flight.
                for _ in 0..<min(3, providers.count) {
                    let provider = providers[next]; next += 1
                    group.addTask { await MusicDiscoveryService.search(provider, query: clean, country: country) }
                }
                while let result = await group.next() {
                    guard !Task.isCancelled, token == self.generation else { group.cancelAll(); return }
                    statuses.append(result)
                    var seen = Set(entries.map(\.dedupKey))
                    entries += result.entries.filter { seen.insert($0.dedupKey).inserted }
                    if next < providers.count {
                        let provider = providers[next]; next += 1
                        group.addTask { await MusicDiscoveryService.search(provider, query: clean, country: country) }
                    }
                }
            }
            guard token == self.generation else { return }
            searching = false
        }
    }
    func cancelSearch() { searchTask?.cancel(); generation = UUID(); searching = false }
    func resolve() {
        resolveTask?.cancel(); resolving = true; resolved = []; resolverMessage = ""; confirmRights = false
        let input = publicURL
        resolveTask = Task {
            do {
                let report = try await PublicAudioResolver.resolve(input)
                try Task.checkCancellation()
                resolved = report.entries; resolverMessage = report.message; resolving = false
            } catch {
                guard !Task.isCancelled else { return }
                resolverMessage = "解析失败：\(error.localizedDescription)"; resolving = false
            }
        }
    }
    func cancelResolve() { resolveTask?.cancel(); resolving = false }
    func act(_ entry: DiscoveryEntry, library: MusicLibrary, player: MusicPlayer) {
        guard busyID == nil else { return }
        busyID = entry.id; progress = 0; error = nil
        actionTask = Task {
            defer { busyID = nil; actionTask = nil }
            do {
                if entry.capability == .album, let release = entry.release {
                    let children = try await MusicDiscoveryService.expand(release)
                    try Task.checkCancellation()
                    var seen = Set(entries.map(\.dedupKey))
                    entries += children.filter { seen.insert($0.dedupKey).inserted }
                    if children.isEmpty { error = "这条发行没有可用的公开 MP3（单首上限 80 MB）。" }
                } else if entry.capability == .stream, let id = entry.remoteID {
                    let url = try await MusicDiscoveryService.audiusStream(id)
                    try Task.checkCancellation()
                    player.playRemote(url, title: entry.title, artist: entry.artist, album: entry.album, source: entry.pageURL, provider: entry.provider, retry: { try await MusicDiscoveryService.audiusStream(id) })
                } else if [.download, .permission].contains(entry.capability), let url = entry.mediaURL {
                    guard entry.capability != .permission || confirmRights else { throw CatalogFailure(message: "请先确认你有权保存所选公开音频；公开链接本身不代表无版权。") }
                    if let saved = library.data.tracks.first(where: { $0.origin?.fileURL == url.absoluteString }), FileManager.default.fileExists(atPath: library.url(for: saved).path) {
                        player.play(saved, in: [saved]); return
                    }
                    let file = try await PublicAudioDownload.download(url, obeyRobots: entry.capability == .permission, sourcePage: entry.pageURL) { [weak self] fraction in
                        Task { @MainActor in if self?.busyID == entry.id { self?.progress = fraction } }
                    }
                    defer { try? FileManager.default.removeItem(at: file) }
                    try Task.checkCancellation()
                    guard let imported = await library.importFiles([file]).first else { throw CatalogFailure(message: library.error ?? "下载内容不是可导入的音频。") }
                    library.recordOrigin(entry.origin, title: entry.title, artist: entry.artist, album: entry.album, sourceName: url.lastPathComponent, for: imported)
                    try Task.checkCancellation()
                    if let saved = library.data.tracks.first(where: { $0.id == imported.id }) { player.play(saved, in: [saved]) }
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }
    }
    func cancelAction() { actionTask?.cancel() }
}
