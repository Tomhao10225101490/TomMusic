import Foundation

struct AudioResolution {
    var entries: [DiscoveryEntry]
    var message: String
}

enum HTMLAudioParser {
    static let audioExtensions = MusicLibrary.supported
    static func matches(_ pattern: String, _ text: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).prefix(512).map { match in
            (0..<match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? "" : source.substring(with: match.range(at: $0)) }
        }
    }
    static func entities(_ text: String) -> String {
        var result = text
        let named = ["&amp;": "&", "&quot;": "\"", "&apos;": "'", "&#39;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " "]
        for (key, value) in named { result = result.replacingOccurrences(of: key, with: value) }
        for match in matches("&#(x[0-9a-f]+|[0-9]+);", result) {
            let raw = match[1], hex = raw.lowercased().hasPrefix("x")
            if let value = UInt32(hex ? String(raw.dropFirst()) : raw, radix: hex ? 16 : 10), let scalar = UnicodeScalar(value) {
                result = result.replacingOccurrences(of: match[0], with: String(scalar))
            }
        }
        return result
    }
    static func plain(_ text: String) -> String {
        let cleaned = text.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
        return String(entities(cleaned).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines).prefix(400))
    }
    static func attributes(_ tag: String) -> [String: String] {
        var output: [String: String] = [:]
        for match in matches("([a-z_:][a-z0-9_.:-]*)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))", tag) {
            output[match[1].lowercased()] = entities(match[2].isEmpty ? (match[3].isEmpty ? match[4] : match[3]) : match[2])
        }
        return output
    }
    static func blockedPromotionalURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == "audio-ssl.itunes.apple.com" || host.hasSuffix(".itunes.apple.com") || host.hasSuffix(".mzstatic.com") || host == "music.apple.com"
    }
    static func parse(_ html: String, page: URL) -> AudioResolution {
        let title = matches("<title\\b[^>]*>([\\s\\S]*?)</title\\s*>", html).first.map { plain($0[1]) } ?? page.host ?? "公开网页音频"
        var found: [(URL, String)] = []
        func add(_ raw: String, _ name: String) {
            guard found.count < 30, let url = URL(string: entities(raw), relativeTo: page)?.absoluteURL,
                  (try? PublicWeb.checkedURL(url.absoluteString)) != nil, !blockedPromotionalURL(url),
                  !["m3u8", "m3u", "mpd"].contains(url.pathExtension.lowercased()) else { return }
            if !found.contains(where: { PublicWeb.canonical($0.0) == PublicWeb.canonical(url) }) { found.append((url, name)) }
        }
        // One fetched page only: no recursive link following, no script execution.
        let withoutScripts = html.replacingOccurrences(of: "<script\\b[^>]*>[\\s\\S]*?</script\\s*>", with: "", options: [.regularExpression, .caseInsensitive])
        for match in matches("<(audio|source|meta|a)\\b[^>]{0,8192}>", withoutScripts) {
            let tag = match[1].lowercased(), attributes = attributes(match[0])
            if ["audio", "source"].contains(tag), let src = attributes["src"] { add(src, title) }
            if tag == "meta", ["og:audio", "og:audio:url", "og:audio:secure_url"].contains(attributes["property"]?.lowercased() ?? ""), let content = attributes["content"] { add(content, title) }
            if tag == "a", let href = attributes["href"], let url = URL(string: href, relativeTo: page), audioExtensions.contains(url.pathExtension.lowercased()) { add(href, url.deletingPathExtension().lastPathComponent) }
        }
        var nodes = 0
        func walk(_ value: Any, depth: Int) {
            guard depth < 9, nodes < 512 else { return }; nodes += 1
            if let array = value as? [Any] { for child in array.prefix(100) { walk(child, depth: depth + 1) } }
            if let object = value as? [String: Any] {
                let type = object["@type"] as? String ?? ""
                if type == "AudioObject", let content = object["contentUrl"] as? String { add(content, plain(object["name"] as? String ?? title)) }
                for child in object.values { if child is [String: Any] || child is [Any] { walk(child, depth: depth + 1) } }
            }
        }
        for match in matches("<script\\b[^>]*type\\s*=\\s*[\"']application/ld\\+json[\"'][^>]*>([\\s\\S]*?)</script\\s*>", html) {
            if let data = match[1].data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) { walk(value, depth: 0) }
        }
        let entries = found.map { url, name in
            DiscoveryEntry(id: "web:" + PublicWeb.canonical(url), provider: "公开网页", title: name.isEmpty ? title : name, artist: page.host ?? "未标注作者", album: title, pageURL: page, mediaURL: url, capability: .permission,
                           note: "网页公开音频链接，不等于版权许可；不保证原唱或完整歌曲。须确认使用权限，导入时仍会校验音频。")
        }
        return AudioResolution(entries: entries, message: entries.isEmpty ? "未在这个页面找到可直接导入的公开音频。未执行网页脚本、未递归抓站、未尝试登录、解密或提取受限流媒体。" : "本页找到 \(entries.count) 个公开音频链接（已去重，最多 30 个）。未验证版权归属、是否完整或是否为原唱；保存前请确认权限。")
    }
}

enum PublicAudioResolver {
    static func resolve(_ input: String) async throws -> AudioResolution {
        let url = try PublicWeb.checkedURL(input)
        try await PublicWeb.validate(url)
        guard !HTMLAudioParser.blockedPromotionalURL(url) else { throw CatalogFailure(message: "这个地址属于官方试听/宣传素材，不作为可保存的完整歌曲。请前往官方平台播放。") }
        try await RobotsCache.shared.requireAllowed(url)
        if MusicLibrary.supported.contains(url.pathExtension.lowercased()) {
            let entry = DiscoveryEntry(id: "web:" + PublicWeb.canonical(url), provider: "公开链接", title: url.deletingPathExtension().lastPathComponent, artist: url.host ?? "未标注作者", album: "公开音频链接", pageURL: url, mediaURL: url, capability: .permission, note: "尚未读取音频；公开可访问不代表无版权，也不保证整曲。请确认权限后保存。")
            return AudioResolution(entries: [entry], message: "识别到直接音频地址；没有预先下载。确认权限后才会请求音频（最大 80 MB）。")
        }
        let payload = try await PublicHTTP.shared.get(url, limit: 2 * 1024 * 1024, cached: false, webpage: true)
        guard ["text/html", "application/xhtml+xml"].contains(payload.response.mimeType?.lowercased() ?? "") else { throw CatalogFailure(message: "这个地址不是 HTML 网页或受支持的直接音频链接。") }
        guard let html = String(data: payload.data, encoding: .utf8) else { throw CatalogFailure(message: "网页不是受支持的 UTF-8 文本。") }
        let final = payload.response.url ?? url
        return HTMLAudioParser.parse(html, page: final)
    }
}

enum PublicAudioDownload {
    static func download(_ url: URL, obeyRobots: Bool, sourcePage: URL? = nil, nativeBiliAudio: Bool = false, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try await PublicWeb.validate(url)
        guard !HTMLAudioParser.blockedPromotionalURL(url) else { throw CatalogFailure(message: "不保存官方试听/宣传素材。") }
        if obeyRobots { try await RobotsCache.shared.requireAllowed(url) }
        if nativeBiliAudio {
            guard NativeAudioPolicy.cdn(url), let sourcePage, sourcePage.scheme == "https", sourcePage.host == "www.bilibili.com", sourcePage.user == nil, sourcePage.password == nil,
                  let id = sourcePage.path.split(separator: "/").last.map(String.init), NativeAudioPolicy.validID(id) else { throw CatalogFailure(message: "独立音频来源或 CDN 不符合策略。") }
        }
        let observer = PublicDownloadObserver(obeyRobots: obeyRobots, nativeBiliAudio: nativeBiliAudio, progress: progress)
        var request = URLRequest(url: url, timeoutInterval: 45)
        request.setValue("TomMusic/1.2 (public audio import)", forHTTPHeaderField: "User-Agent")
        // ccMixter's explicitly CC-licensed download links require their genuine
        // attribution/source page as referrer, just like its public HTML player.
        // No credentials, invented origin, cookies or generic referrer spoofing.
        if !obeyRobots, url.host == "ccmixter.org", let sourcePage, sourcePage.host == "ccmixter.org", sourcePage.path.hasPrefix("/files/") {
            request.setValue(sourcePage.absoluteString, forHTTPHeaderField: "Referer")
        }
        if nativeBiliAudio, let sourcePage { request.setValue(sourcePage.absoluteString, forHTTPHeaderField: "Referer") }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 120; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let temporary: URL, response: URLResponse
        do { (temporary, response) = try await session.download(for: request, delegate: observer) }
        catch { if let failure = observer.failure { throw failure }; throw error }
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Task.checkCancellation()
        if let failure = observer.failure { throw failure }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw CatalogFailure(message: "音频下载失败（HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)）。") }
        let bytes = (try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard bytes > 0, bytes <= ArchiveMusicService.maximumBytes else { throw CatalogFailure(message: "音频为空或超过 80 MB。") }
        let mime = response.mimeType?.lowercased() ?? ""
        guard !["text/html", "application/json", "application/xhtml+xml"].contains(mime) else { throw CatalogFailure(message: "来源返回网页/错误信息，而不是音频；未导入。") }
        let ext = url.pathExtension.lowercased()
        let mimeExtensions = ["audio/mpeg": "mp3", "audio/mp3": "mp3", "audio/mp4": "m4a", "audio/aac": "aac", "audio/flac": "flac", "audio/x-flac": "flac", "audio/wav": "wav", "audio/x-wav": "wav", "audio/aiff": "aiff", "video/mp4": "mp4"]
        guard let suffix = nativeBiliAudio ? "m4a" : (MusicLibrary.supported.contains(ext) ? ext : mimeExtensions[mime]) else { throw CatalogFailure(message: "音频格式不受当前系统解码器支持。") }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + suffix)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }
}

private final class PublicDownloadObserver: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var storedFailure: Error?
    private var redirects = 0
    private let obeyRobots: Bool
    private let nativeBiliAudio: Bool
    private let progress: @Sendable (Double) -> Void
    var failure: Error? { lock.lock(); defer { lock.unlock() }; return storedFailure }
    private func fail(_ error: Error) { lock.lock(); storedFailure = error; lock.unlock() }
    init(obeyRobots: Bool, nativeBiliAudio: Bool = false, progress: @escaping @Sendable (Double) -> Void) { self.obeyRobots = obeyRobots; self.nativeBiliAudio = nativeBiliAudio; self.progress = progress }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > ArchiveMusicService.maximumBytes || totalBytesExpectedToWrite > ArchiveMusicService.maximumBytes {
            fail(CatalogFailure(message: "音频超过 80 MB，已停止下载。")); downloadTask.cancel(); return
        }
        if totalBytesExpectedToWrite > 0 { progress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        lock.lock(); redirects += 1; let count = redirects; lock.unlock()
        guard count <= 5, let url = request.url else { fail(CatalogFailure(message: "音频重定向超过 5 次。")); completionHandler(nil); return }
        Task {
            do {
                try await PublicWeb.validate(url)
                if self.nativeBiliAudio && !NativeAudioPolicy.cdn(url) { throw CatalogFailure(message: "独立音频重定向离开来源 CDN，已停止。") }
                guard !HTMLAudioParser.blockedPromotionalURL(url) else { throw CatalogFailure(message: "重定向指向官方试听素材，未下载。") }
                if obeyRobots { try await RobotsCache.shared.requireAllowed(url) }
                completionHandler(request)
            } catch { self.fail(error); completionHandler(nil) }
        }
    }
}
