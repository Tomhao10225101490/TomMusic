import AVFoundation
import Foundation
import SwiftUI

struct NativeAudioEntry: Identifiable, Sendable {
    let id: String
    let title: String
    let uploader: String
    let seconds: Double
    var page: URL { URL(string: "https://www.bilibili.com/video/\(id)/")! }
    var version: String { DiscoveryRanking.version(title) }
    var audioTitle: String {
        if let range = title.range(of: "《[^》]{1,100}》", options: .regularExpression) { return String(title[range].dropFirst().dropLast()) }
        return title.replacingOccurrences(of: "^【[^】]*(?:4K|Hi-?Res|1080P|120帧|无损音质)[^】]*】\\s*", with: "", options: [.regularExpression, .caseInsensitive])
    }
}

struct NativeAudioClip: Sendable {
    let file: URL
    let entry: NativeAudioEntry
    let duration: Double
    let bytes: Int
}

enum NativeAudioPolicy {
    static func validID(_ id: String) -> Bool { id.range(of: "^BV[0-9A-Za-z]{10}$", options: .regularExpression) != nil }
    static func cdn(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
        return ["bilivideo.com", "bilivideo.cn", "akamaized.net"].contains { host == $0 || host.hasSuffix("." + $0) }
    }
    static func permits(_ value: [String: Any]) -> Bool {
        guard let rights = value["rights"] as? [String: Any] else { return false }
        return ["pay", "ugc_pay", "arc_pay", "no_background"].allSatisfy { (rights[$0] as? Int) == 0 }
            && (rights["download"] as? Int) == 1 && (value["is_upower_exclusive"] as? Bool) != true && (value["state"] as? Int ?? 0) == 0
    }
    static func ownCache(_ url: URL) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL == FileManager.default.temporaryDirectory.appendingPathComponent("TomMusicAudio", isDirectory: true).standardizedFileURL
            && UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil && url.pathExtension == "m4a"
    }
    static func remove(_ url: URL) { if ownCache(url) { try? FileManager.default.removeItem(at: url) } }
    static func cache(_ source: URL) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TomMusicAudio", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
        var total = 0
        for file in files where ownCache(file) {
            let attributes = try file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            if let date = attributes.contentModificationDate, Date().timeIntervalSince(date) > 86400 { remove(file) }
            else { total += attributes.fileSize ?? 0 }
        }
        let incoming = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard total + incoming <= 500 * 1024 * 1024 else { throw CatalogFailure(message: "音频临时缓存已达 500 MB；请关闭其他 Tom Music 播放会话后重试。") }
        let destination = directory.appendingPathComponent(UUID().uuidString + ".m4a")
        try FileManager.default.moveItem(at: source, to: destination)
        return destination
    }
}

// A normal anonymous platform session. Cookies come ONLY from its public home response;
// no browser/account cookies, generated fingerprints, WBI signatures or paid access.
actor NativeAudioService {
    static let shared = NativeAudioService()
    private let cookies = URLSessionConfiguration.ephemeral.httpCookieStorage
    private var bootstrapped = false
    private var lastRequest = Date.distantPast

    private func fetch(_ url: URL, source: URL, headersOnly: Bool = false) async throws -> Data {
        guard ["www.bilibili.com", "api.bilibili.com"].contains(url.host ?? "") else { throw CatalogFailure(message: "拒绝非曲源 API 地址。") }
        try await PublicWeb.validate(url)
        while Date().timeIntervalSince(lastRequest) < 0.5 { try await Task.sleep(nanoseconds: 200_000_000) }
        try Task.checkCancellation(); lastRequest = Date()
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = cookies; config.urlCredentialStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 25
        let delegate = NativeAudioRedirect()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue("TomMusic/1.4 (native public audio)", forHTTPHeaderField: "User-Agent")
        request.setValue(source.absoluteString, forHTTPHeaderField: "Referer")
        request.mainDocumentURL = source
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw CatalogFailure(message: "曲源请求失败（HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)）；未绕过验证。") }
        if headersOnly { return Data() }
        let limit = 2 * 1024 * 1024
        guard response.expectedContentLength <= limit else { throw CatalogFailure(message: "曲源响应超过 2 MB。") }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw CatalogFailure(message: "曲源响应超过 2 MB。") }
            data.append(byte)
        }
        try Task.checkCancellation()
        return data
    }
    private func object(_ url: URL, source: URL) async throws -> [String: Any] {
        if !bootstrapped {
            _ = try await fetch(URL(string: "https://www.bilibili.com/")!, source: URL(string: "https://www.bilibili.com/")!, headersOnly: true)
            bootstrapped = true
        }
        let data = try await fetch(url, source: source)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], (object["code"] as? Int) == 0, let payload = object["data"] as? [String: Any] else {
            throw CatalogFailure(message: "公开曲源未返回可用数据；可能有验证、登录或服务限制，未更换身份绕过。")
        }
        return payload
    }
    func search(_ text: String) async throws -> [NativeAudioEntry] {
        let text = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(256))
        if NativeAudioPolicy.validID(text) { return [try await details(text)] }
        if let url = URL(string: text), text.contains("://") || ["file", "data", "javascript"].contains(url.scheme ?? "") {
            guard WebMusicRoute.allowed(url), url.host == "www.bilibili.com", let id = url.path.split(separator: "/").last.map(String.init), NativeAudioPolicy.validID(id) else { throw CatalogFailure(message: "请输入歌名或标准 B站 BV 视频链接；不访问任意网页、私有地址或其他协议。") }
            let part = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "p" })?.value
            guard part == nil || part == "1" else { throw CatalogFailure(message: "当前直接音轨不支持非第一分 P，未改播其他分 P。") }
            return [try await details(id)]
        }
        guard !text.isEmpty else { return [] }
        var url = URLComponents(string: "https://api.bilibili.com/x/web-interface/search/type")!
        url.queryItems = [URLQueryItem(name: "search_type", value: "video"), URLQueryItem(name: "keyword", value: text), URLQueryItem(name: "page", value: "1")]
        let payload = try await object(url.url!, source: WebMusicRoute.search(text, youtube: false))
        var seen = Set<String>()
        return ((payload["result"] as? [[String: Any]]) ?? []).prefix(30).compactMap { item in
            guard let id = item["bvid"] as? String, NativeAudioPolicy.validID(id), seen.insert(id).inserted else { return nil }
            let duration = (item["duration"] as? String ?? "").split(separator: ":").compactMap { Double($0) }.reduce(0) { $0 * 60 + $1 }
            return NativeAudioEntry(id: id, title: HTMLAudioParser.plain(item["title"] as? String ?? "未标注标题"), uploader: item["author"] as? String ?? "未标注上传者", seconds: duration)
        }
    }
    private func metadata(_ id: String) async throws -> [String: Any] {
        guard NativeAudioPolicy.validID(id) else { throw CatalogFailure(message: "无效音轨编号。") }
        return try await object(URL(string: "https://api.bilibili.com/x/web-interface/view?bvid=\(id)")!, source: URL(string: "https://www.bilibili.com/video/\(id)/")!)
    }
    private func entry(_ item: [String: Any], id: String) -> NativeAudioEntry {
        NativeAudioEntry(id: id, title: HTMLAudioParser.plain(item["title"] as? String ?? "未标注标题"), uploader: (item["owner"] as? [String: Any])?["name"] as? String ?? "未标注上传者", seconds: item["duration"] as? Double ?? 0)
    }
    func details(_ id: String) async throws -> NativeAudioEntry { entry(try await metadata(id), id: id) }
    func audio(_ id: String, progress: @escaping @Sendable (Double) -> Void) async throws -> NativeAudioClip {
        let item = try await metadata(id)
        guard (item["videos"] as? Int ?? 1) == 1 else { throw CatalogFailure(message: "此结果是多分 P 合集；请选单曲来源，未把第一分 P 冒充整份合集。") }
        guard NativeAudioPolicy.permits(item), let cid = item["cid"] as? Int else { throw CatalogFailure(message: "来源有付费、专享、禁止后台/保存或未知权限标记；不提取音轨。") }
        let track = entry(item, id: id)
        let play = try await object(URL(string: "https://api.bilibili.com/x/player/playurl?bvid=\(id)&cid=\(cid)&fnval=16")!, source: track.page)
        guard (play["is_preview"] as? Bool) != true, (play["is_drm"] as? Bool) != true,
              let dash = play["dash"] as? [String: Any], let audios = dash["audio"] as? [[String: Any]],
              let selected = audios.filter({ ($0["codecs"] as? String ?? "").hasPrefix("mp4a.") && ($0["mimeType"] as? String ?? $0["mime_type"] as? String) == "audio/mp4" && $0["ContentProtection"] == nil }).sorted(by: { ($0["bandwidth"] as? Int ?? 0) > ($1["bandwidth"] as? Int ?? 0) }).first else {
            throw CatalogFailure(message: "来源未提供可用的公开独立 AAC 音轨；未下载视频或使用试听替代。")
        }
        // At most two exact same-audio locations published in THIS response, not guessed mirrors/signatures.
        let primary = selected["baseUrl"] as? String ?? selected["base_url"] as? String
        let backups = selected["backupUrl"] as? [String] ?? selected["backup_url"] as? [String] ?? []
        let urls = ([primary].compactMap { $0 } + backups).compactMap(URL.init(string:)).filter(NativeAudioPolicy.cdn).prefix(2)
        guard !urls.isEmpty else { throw CatalogFailure(message: "来源音频地址不符合公开 HTTPS CDN 策略。") }
        var result: URL?
        var failure: Error?
        for url in urls {
            try Task.checkCancellation()
            do { result = try await PublicAudioDownload.download(url, obeyRobots: false, sourcePage: track.page, nativeBiliAudio: true, progress: progress); break }
            catch { try Task.checkCancellation(); failure = error }
        }
        guard let downloaded = result else { throw failure ?? CatalogFailure(message: "同一独立音轨节点不可用，未换歌。") }
        defer { try? FileManager.default.removeItem(at: downloaded) }
        try Task.checkCancellation()
        let asset = AVURLAsset(url: downloaded)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let video = try await asset.loadTracks(withMediaType: .video)
        let protected = try await asset.load(.hasProtectedContent)
        let duration = try await asset.load(.duration).seconds
        guard !audio.isEmpty, video.isEmpty, !protected, duration.isFinite, duration > 0, abs(duration - track.seconds) < 3 else { throw CatalogFailure(message: "音频轨道/完整时长核验失败；不把视频、DRM 或短试听传给播放器。") }
        let bytes = try downloaded.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        try Task.checkCancellation()
        let file = try NativeAudioPolicy.cache(downloaded)
        return NativeAudioClip(file: file, entry: track, duration: duration, bytes: bytes)
    }
}

private final class NativeAudioRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private var redirects = 0
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        redirects += 1
        guard redirects <= 3, let url = request.url, ["www.bilibili.com", "api.bilibili.com"].contains(url.host ?? "") else { completionHandler(nil); return }
        Task { do { try await PublicWeb.validate(url); completionHandler(request) } catch { completionHandler(nil) } }
    }
}

@MainActor final class NativeAudioCatalog: ObservableObject {
    @Published var query = ""
    @Published var entries: [NativeAudioEntry] = []
    @Published var searching = false
    @Published var busyID: String?
    @Published var progress: Double = 0
    @Published var message = "搜索歌名或艺人，选择结果即可用原生播放条直接听音频。"
    private var searchTask: Task<Void, Never>?
    private var playTask: Task<Void, Never>?
    private var searchID = UUID()
    private var playID = UUID()
    func search() {
        searchTask?.cancel(); searchID = UUID(); let token = searchID, text = query
        entries = []; searching = true; message = "正在检索公开音轨…"
        searchTask = Task { [weak self] in
            do {
                let entries = try await NativeAudioService.shared.search(text)
                try Task.checkCancellation()
                guard let self, self.searchID == token else { return }
                self.entries = entries; self.searching = false; self.message = entries.isEmpty ? "没有匹配结果；没有使用演示音乐替代。" : "找到 \(entries.count) 个来源结果；翻唱、剪辑、上传者和完整性以来源核验为准。"
            } catch {
                guard let self, self.searchID == token else { return }
                self.searching = false; self.message = "搜索未完成：\(error.localizedDescription)"
            }
        }
    }
    func cancel() { playTask?.cancel(); playTask = nil; playID = UUID(); busyID = nil; progress = 0; message = "已取消音频缓冲；不会延迟自动播放。" }
    func play(_ entry: NativeAudioEntry, player: MusicPlayer) {
        cancel(); playID = UUID(); let token = playID; busyID = entry.id; message = "正在缓冲独立音轨（仅音频，不加载 MV / 网页）…"
        playTask = Task { [weak self, weak player] in
            var clip: NativeAudioClip?
            var adopted = false
            defer { if !adopted, let clip { NativeAudioPolicy.remove(clip.file) } }
            do {
                clip = try await NativeAudioService.shared.audio(entry.id) { [weak self] value in
                    Task { @MainActor in if self?.playID == token { self?.progress = value } }
                }
                try Task.checkCancellation()
                guard let self, let player, self.playID == token, let clip else { return }
                adopted = player.playTemporaryAudio(clip)
                self.busyID = nil; self.progress = 0
                self.message = adopted ? "独立音频已交给原生播放器 · \(timeLabel(clip.duration)) · \(clip.bytes / 1024) KB · 0 个视频轨道 · 临时缓存，不写入资料库" : "独立音频未能启动原生播放。"
            } catch {
                guard let self, self.playID == token else { return }
                self.busyID = nil; self.progress = 0; self.message = "无法直接播放：\(error.localizedDescription)"
            }
        }
    }
}

struct NativeAudioView: View {
    @EnvironmentObject var player: MusicPlayer
    @StateObject private var catalog = NativeAudioCatalog()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("搜索歌名 / 歌手，或粘贴 B站 BV 链接", text: $catalog.query).textFieldStyle(.roundedBorder).accessibilityLabel("直接听歌搜索").onSubmit { catalog.search() }
                Button("搜索音轨") { catalog.search() }.help("搜索音轨").accessibilityLabel("搜索音轨").disabled(catalog.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if catalog.searching { ProgressView().controlSize(.small) }
            }
            Text("原生音频播放，不打开视频或网页。来源为公开视频提供的独立音轨；不保证官方专辑原版，不把翻唱/剪辑冒充原版。公开可播与版权归属分开标注。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if catalog.busyID != nil {
                HStack { ProgressView(value: catalog.progress).frame(maxWidth: 250); Text("音频缓冲 \(Int(catalog.progress * 100))%").font(.caption); Button("取消缓冲") { catalog.cancel() }.help("取消音频缓冲").accessibilityLabel("取消音频缓冲") }
            }
            Text(catalog.message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(catalog.entries) { entry in
                        HStack(spacing: 15) {
                            Image(systemName: "music.note").font(.title2).foregroundStyle(.secondary).frame(width: 30)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.audioTitle).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                                Text("来源标题：" + entry.title).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1).help(entry.title)
                                Text("上传者：\(entry.uploader) · \(timeLabel(entry.seconds))\(entry.version.isEmpty ? " · 版本未独立核验" : " · " + entry.version)").font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Button("播放音频") { catalog.play(entry, player: player) }.buttonStyle(.bordered).help("播放音频 " + entry.id).accessibilityLabel("播放音频 " + entry.title).disabled(catalog.busyID != nil)
                            Link("来源 ↗", destination: entry.page).font(.caption)
                        }.padding(.vertical, 13)
                        Divider().opacity(0.4)
                    }
                }
            }
        }.onDisappear { catalog.cancel() }
    }
}
