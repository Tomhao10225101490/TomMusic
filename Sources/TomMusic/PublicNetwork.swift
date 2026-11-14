import Darwin
import Foundation

struct PublicPayload {
    var data: Data
    var response: HTTPURLResponse
}

enum PublicWeb {
    static func checkedURL(_ string: String) throws -> URL {
        guard string.utf8.count <= 8192, let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), !host.isEmpty,
              url.user == nil, url.password == nil, url.port == nil || url.port == 443,
              !host.contains(":"), !host.contains("%"), !host.hasSuffix("."),
              !["localhost", "localhost.localdomain"].contains(host),
              ![".localhost", ".local", ".internal", ".lan", ".home", ".onion"].contains(where: host.hasSuffix),
              !host.allSatisfy({ $0.isNumber || $0 == "." }) else {
            throw CatalogFailure(message: "只接受不含账号密码的公开 HTTPS 域名链接；不访问本机、内网、IP 地址或非标准端口。")
        }
        return url
    }
    static func publicIP(_ text: String) -> Bool {
        var v4 = in_addr()
        if inet_pton(AF_INET, text, &v4) == 1 {
            let octets = withUnsafeBytes(of: &v4) { Array($0) }
            let a = Int(octets[0]), b = Int(octets[1]), c = Int(octets[2])
            return !(a == 0 || a == 10 || a == 127 || a >= 224 ||
                     (a == 169 && b == 254) || (a == 172 && (16...31).contains(b)) ||
                     (a == 192 && b == 168) || (a == 100 && (64...127).contains(b)) ||
                     (a == 198 && (b == 18 || b == 19)) ||
                     (a == 192 && b == 0) || (a == 198 && b == 51 && c == 100) ||
                     (a == 203 && b == 0 && c == 113))
        }
        var v6 = in6_addr()
        guard inet_pton(AF_INET6, text, &v6) == 1 else { return false }
        let bytes = withUnsafeBytes(of: &v6) { Array($0) }
        if bytes.prefix(12).allSatisfy({ $0 == 0 }) || bytes[0] & 0xfe == 0xfc || bytes[0] == 0xff ||
            (bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80) || (bytes[0] == 0xfe && bytes[1] & 0xc0 == 0xc0) ||
            (bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0d && bytes[3] == 0xb8) { return false }
        if bytes.prefix(10).allSatisfy({ $0 == 0 }) && bytes[10] == 0xff && bytes[11] == 0xff {
            return publicIP(bytes.suffix(4).map(String.init).joined(separator: "."))
        }
        // Only global-unicast IPv6; reject transition/tunnel ranges as well.
        return bytes[0] & 0xe0 == 0x20 && !(bytes[0] == 0x20 && bytes[1] == 0x02) && !(bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0 && bytes[3] == 0)
    }
    static func fakeIP(_ text: String) -> Bool {
        let bytes = text.split(separator: ".").compactMap { Int($0) }
        return bytes.count == 4 && bytes[0] == 198 && (bytes[1] == 18 || bytes[1] == 19) && bytes.allSatisfy { (0...255).contains($0) }
    }
    static func validate(_ url: URL) async throws {
        _ = try checkedURL(url.absoluteString)
        try Task.checkCancellation()
        guard let host = url.host else { throw CatalogFailure(message: "链接缺少域名。") }
        try await DNSGuard.shared.check(host)
        try Task.checkCancellation()
    }
    static func canonical(_ url: URL) -> String {
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        parts.fragment = nil
        parts.queryItems = parts.queryItems?.filter { !$0.name.lowercased().hasPrefix("utm_") }
        if parts.queryItems?.isEmpty == true { parts.queryItems = nil }
        return parts.string ?? url.absoluteString
    }
}

private actor DNSGuard {
    static let shared = DNSGuard()
    private var valid: [String: Date] = [:]
    func check(_ host: String) async throws {
        if let until = valid[host], until > Date() { return }
        let race = DNSCompletion()
        let fakeIP = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                race.start(continuation)
                DispatchQueue.global(qos: .utility).async {
                    var hints = addrinfo(); hints.ai_family = AF_UNSPEC; hints.ai_socktype = SOCK_STREAM
                    var result: UnsafeMutablePointer<addrinfo>?
                    guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else {
                        race.finish(.failure(CatalogFailure(message: "无法解析公开域名：\(host)"))); return
                    }
                    defer { freeaddrinfo(first) }
                    var cursor: UnsafeMutablePointer<addrinfo>? = first
                    var count = 0, fakeCount = 0
                    while let info = cursor {
                        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        if getnameinfo(info.pointee.ai_addr, info.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                            count += 1
                            let address = String(cString: buffer)
                            if PublicWeb.fakeIP(address) { fakeCount += 1 }
                            else if !PublicWeb.publicIP(address) {
                                race.finish(.failure(CatalogFailure(message: "拒绝访问解析到内网或保留地址的域名：\(host)"))); return
                            }
                        }
                        cursor = info.pointee.ai_next
                    }
                    guard count > 0, fakeCount == 0 || fakeCount == count else { race.finish(.failure(CatalogFailure(message: "域名包含混合的公开/保留地址。"))); return }
                    race.finish(.success(fakeCount > 0))
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                    race.finish(.failure(CatalogFailure(message: "域名解析超过 5 秒，请重试。")))
                }
            }
        } onCancel: { race.finish(.failure(CancellationError())) }
        if fakeIP {
            // VPN/TUN Fake-IP is not a public address. Confirm the original domain
            // with fixed-host, certificate-validated public DNS-over-HTTPS first;
            // never blanket-allow 198.18/15 or change the user's proxy/DNS settings.
            let addresses = try await withThrowingTaskGroup(of: [String].self) { group in
                for type in ["A", "AAAA"] {
                    group.addTask {
                        var components = URLComponents(string: "https://cloudflare-dns.com/dns-query")!
                        components.queryItems = [URLQueryItem(name: "name", value: host), URLQueryItem(name: "type", value: type)]
                        let payload = try await BoundedPublicRequest(url: components.url!, limit: 32 * 1024, webpage: false, accept: "application/dns-json").run()
                        guard payload.response.statusCode == 200,
                              let object = try JSONSerialization.jsonObject(with: payload.data) as? [String: Any], object["Status"] as? Int == 0 else {
                            throw CatalogFailure(message: "当前代理使用 Fake-IP，但公网 DNS 核验失败；未继续访问。")
                        }
                        return (object["Answer"] as? [[String: Any]] ?? []).filter { [1, 28].contains($0["type"] as? Int ?? 0) }.compactMap { $0["data"] as? String }
                    }
                }
                var addresses: [String] = []
                for try await values in group { addresses += values }
                return addresses
            }
            guard !addresses.isEmpty, addresses.allSatisfy(PublicWeb.publicIP) else {
                throw CatalogFailure(message: "公网 DNS 核验发现内网/保留地址，或没有公开记录：\(host)")
            }
        }
        if valid.count >= 64 { valid.removeAll() }
        valid[host] = Date().addingTimeInterval(120)
    }
}

private final class DNSCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Error>?
    private var result: Result<Bool, Error>?
    func start(_ continuation: CheckedContinuation<Bool, Error>) {
        lock.lock()
        if let result { lock.unlock(); continuation.resume(with: result) }
        else { self.continuation = continuation; lock.unlock() }
    }
    func finish(_ result: Result<Bool, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result; let continuation = self.continuation; self.continuation = nil
        lock.unlock(); continuation?.resume(with: result)
    }
}

actor PublicHTTP {
    static let shared = PublicHTTP()
    private var nextHostTime: [String: Date] = [:]
    private var cache: [String: (Date, PublicPayload)] = [:]
    func throttle(_ url: URL) async throws {
        let host = url.host ?? ""
        let previous = nextHostTime[host] ?? .distantPast
        let start = max(previous, Date())
        nextHostTime[host] = start.addingTimeInterval(host == "itunes.apple.com" ? 3.2 : 0.7)
        let delay = start.timeIntervalSinceNow
        if delay > 15 { throw CatalogFailure(message: "\(host) 请求过密，请稍后重试。") }
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
    }
    func get(_ url: URL, limit: Int = 4 * 1024 * 1024, cached: Bool = true, webpage: Bool = false) async throws -> PublicPayload {
        try await PublicWeb.validate(url)
        let key = url.absoluteString
        if webpage { try await RobotsCache.shared.requireAllowed(url) }
        if cached, let item = cache[key], item.0 > Date() {
            guard item.1.data.count <= limit else { throw CatalogFailure(message: "缓存响应超过大小上限。") }
            return item.1
        }
        for attempt in 0...1 {
            try Task.checkCancellation()
            try await throttle(url)
            do {
                let loader = BoundedPublicRequest(url: url, limit: limit, webpage: webpage)
                let result = try await loader.run()
                let status = result.response.statusCode
                if (status == 429 || (500...599).contains(status)) && attempt == 0 {
                    let retry = Double(result.response.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 1
                    guard retry <= 3 else { throw CatalogFailure(message: "来源限流，请稍后重试（HTTP \(status)）。") }
                    try await Task.sleep(nanoseconds: UInt64(max(1, retry) * 1_000_000_000)); continue
                }
                guard (200...299).contains(status) else { throw CatalogFailure(message: "来源请求失败（HTTP \(status)）。") }
                if cached {
                    if cache.count >= 32 { cache.removeAll() }
                    cache[key] = (Date().addingTimeInterval(300), result)
                }
                return result
            } catch let error as URLError where attempt == 0 && [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(error.code) {
                try await Task.sleep(nanoseconds: 700_000_000)
            }
        }
        throw CatalogFailure(message: "来源暂时不可用，重试次数已用完。")
    }
    func audioProbe(_ url: URL) async throws -> PublicPayload {
        try await PublicWeb.validate(url)
        try await throttle(url)
        return try await BoundedPublicRequest(url: url, limit: 1024, webpage: false, headersOnlyGET: true).run()
    }
    func json(_ url: URL, cached: Bool = true) async throws -> Any {
        let payload = try await get(url, cached: cached)
        return try JSONSerialization.jsonObject(with: payload.data)
    }
    func clearCache() { cache.removeAll() }
}

private final class BoundedPublicRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let url: URL
    private let limit: Int
    private let webpage: Bool
    private let accept: String
    private let method: String
    private let headersOnlyGET: Bool
    private var buffer = Data()
    private var response: HTTPURLResponse?
    private var continuation: CheckedContinuation<PublicPayload, Error>?
    private var task: URLSessionDataTask?
    private var session: URLSession?
    private var cancelled = false
    private var finished = false
    private var storedFailure: Error?
    private var failure: Error? {
        get { lock.lock(); defer { lock.unlock() }; return storedFailure }
        set { lock.lock(); storedFailure = newValue; lock.unlock() }
    }
    private var redirects = 0
    init(url: URL, limit: Int, webpage: Bool, accept: String = "application/json, text/html, text/plain;q=0.9, */*;q=0.5", method: String = "GET", headersOnlyGET: Bool = false) { self.url = url; self.limit = limit; self.webpage = webpage; self.accept = accept; self.method = method; self.headersOnlyGET = headersOnlyGET }
    func run() async throws -> PublicPayload {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if cancelled { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation
                let config = URLSessionConfiguration.ephemeral
                config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 30
                config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
                let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
                let session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
                self.session = session
                var request = URLRequest(url: url)
                request.httpMethod = method
                if headersOnlyGET { request.setValue("bytes=0-1023", forHTTPHeaderField: "Range") }
                request.setValue("TomMusic/1.2 (public music discovery; bounded client)", forHTTPHeaderField: "User-Agent")
                request.setValue(accept, forHTTPHeaderField: "Accept")
                let task = session.dataTask(with: request); self.task = task
                lock.unlock(); task.resume()
            }
        } onCancel: { self.cancel() }
    }
    private func cancel() {
        lock.lock(); cancelled = true; let task = task; lock.unlock(); task?.cancel()
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse else { failure = CatalogFailure(message: "来源未返回 HTTP 数据。"); completionHandler(.cancel); return }
        if headersOnlyGET { self.response = response; completionHandler(.cancel); return }
        guard method == "HEAD" || response.expectedContentLength <= Int64(limit) else { failure = CatalogFailure(message: "网页或 API 响应超过大小上限。"); completionHandler(.cancel); return }
        self.response = response; completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if buffer.count + data.count > limit { failure = CatalogFailure(message: "响应超过 \(limit / 1024) KB 上限，已停止读取。"); dataTask.cancel() }
        else { buffer.append(data) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        redirects += 1
        guard redirects <= 5, let url = request.url else { failure = CatalogFailure(message: "来源重定向次数过多。"); completionHandler(nil); return }
        Task {
            do {
                try await PublicWeb.validate(url)
                if webpage { try await RobotsCache.shared.requireAllowed(url) }
                completionHandler(request)
            } catch { self.failure = error; completionHandler(nil) }
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true; let continuation = continuation; self.continuation = nil
        let cancelled = cancelled; lock.unlock()
        defer { session.finishTasksAndInvalidate() }
        if cancelled { continuation?.resume(throwing: CancellationError()) }
        else if headersOnlyGET, let response, failure == nil, (error == nil || (error as? URLError)?.code == .cancelled) {
            // We intentionally stop the Range GET as soon as final headers arrive.
            // User cancellation and redirect-policy failures still take precedence.
            continuation?.resume(returning: PublicPayload(data: Data(), response: response))
        }
        else if let error = failure ?? error { continuation?.resume(throwing: error) }
        else if let response { continuation?.resume(returning: PublicPayload(data: buffer, response: response)) }
        else { continuation?.resume(throwing: CatalogFailure(message: "来源没有响应。")) }
    }
}

struct RobotsPolicy {
    struct Rule { var allow: Bool; var path: String }
    var rules: [Rule]
    init(_ text: String) {
        var groups: [([String], [Rule])] = []
        var agents: [String] = [], current: [Rule] = []
        var hasRules = false
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.components(separatedBy: "#")[0].trimmingCharacters(in: .whitespaces)
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased(), value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if key == "user-agent" {
                if hasRules { groups.append((agents, current)); agents = []; current = []; hasRules = false }
                agents.append(value.lowercased())
            } else if ["allow", "disallow"].contains(key), !agents.isEmpty {
                hasRules = true
                if !value.isEmpty { current.append(Rule(allow: key == "allow", path: value)) }
            }
        }
        if !agents.isEmpty { groups.append((agents, current)) }
        let specific = groups.flatMap { $0.0 }.filter { $0 != "*" && !$0.isEmpty && "tommusic".contains($0) }
        let length = specific.map(\.count).max() ?? 0
        rules = groups.filter { group in
            length == 0 ? group.0.contains("*") : group.0.contains(where: { $0.count == length && specific.contains($0) })
        }.flatMap { $0.1 }
    }
    static func pathMatches(_ rule: String, target: String) -> Bool {
        // Match literal chunks, never execute a website-supplied regex: repeated
        // wildcards cannot trigger catastrophic regular-expression backtracking.
        let end = rule.hasSuffix("$")
        let pattern = end ? String(rule.dropLast()) : rule
        if !pattern.contains("*") { return end ? target == pattern : target.hasPrefix(pattern) }
        let chunks = pattern.components(separatedBy: "*")
        guard let first = chunks.first, target.hasPrefix(first) else { return false }
        var cursor = target.index(target.startIndex, offsetBy: first.count)
        for chunk in chunks.dropFirst().dropLast() where !chunk.isEmpty {
            guard let range = target.range(of: chunk, range: cursor..<target.endIndex) else { return false }
            cursor = range.upperBound
        }
        let last = chunks.last ?? ""
        if end {
            guard target.hasSuffix(last) else { return false }
            return target.distance(from: cursor, to: target.endIndex) >= last.count
        }
        return last.isEmpty || target.range(of: last, range: cursor..<target.endIndex) != nil
    }
    static func normalize(_ text: String) -> String {
        var value = text.unicodeScalars.map { scalar in
            scalar.value > 127 ? String(scalar).utf8.map { String(format: "%%%02X", $0) }.joined() : String(scalar)
        }.joined()
        let regex = try! NSRegularExpression(pattern: "%[a-fA-F0-9]{2}")
        let source = value as NSString
        for match in regex.matches(in: value, range: NSRange(location: 0, length: source.length)).reversed() {
            let escaped = source.substring(with: match.range)
            guard let byte = UInt8(escaped.dropFirst(), radix: 16) else { continue }
            let decoded = String(UnicodeScalar(byte))
            let replacement = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~".contains(decoded) ? decoded : escaped.uppercased()
            if let range = Range(match.range, in: value) { value.replaceSubrange(range, with: replacement) }
        }
        return value
    }
    func allows(_ url: URL) -> Bool {
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let rawPath = parts?.percentEncodedPath ?? url.path
        let rawTarget = (rawPath.isEmpty ? "/" : rawPath) + (parts?.percentEncodedQuery.map { "?" + $0 } ?? "")
        let target = Self.normalize(rawTarget)
        let matching = rules.filter { Self.pathMatches(Self.normalize($0.path), target: target) }.sorted {
            let a = $0.path.filter { $0 != "*" && $0 != "$" }.utf8.count, b = $1.path.filter { $0 != "*" && $0 != "$" }.utf8.count
            return a == b ? $0.allow && !$1.allow : a > b
        }
        return matching.first?.allow ?? true
    }
}

actor RobotsCache {
    static let shared = RobotsCache()
    private var cache: [String: (Date, RobotsPolicy)] = [:]
    func requireAllowed(_ url: URL) async throws {
        guard let host = url.host else { throw CatalogFailure(message: "网页缺少域名。") }
        if let value = cache[host], value.0 > Date() {
            guard value.1.allows(url) else { throw CatalogFailure(message: "来源 robots.txt 不允许抓取这个路径。") }
            return
        }
        let robotsURL = URL(string: "https://\(host)/robots.txt")!
        try await PublicWeb.validate(robotsURL)
        let loader = BoundedPublicRequest(url: robotsURL, limit: 256 * 1024, webpage: false)
        let result = try await loader.run()
        let policy: RobotsPolicy
        if result.response.statusCode == 404 { policy = RobotsPolicy("") }
        else if (200...299).contains(result.response.statusCode), let text = String(data: result.data, encoding: .utf8) { policy = RobotsPolicy(text) }
        else { throw CatalogFailure(message: "无法确认来源 robots.txt 规则（HTTP \(result.response.statusCode)），未继续抓取。") }
        if cache.count >= 32 { cache.removeAll() }
        cache[host] = (Date().addingTimeInterval(600), policy)
        guard policy.allows(url) else { throw CatalogFailure(message: "来源 robots.txt 不允许抓取这个路径。") }
    }
}
