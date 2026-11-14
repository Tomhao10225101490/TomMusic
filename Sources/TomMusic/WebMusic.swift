import AppKit
import SwiftUI
import WebKit

// Platform-owned visible players; no media URL extraction, proxy, signature code or download.
enum WebMusicRoute {
    static func allowed(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
        return ["bilibili.com", "b23.tv", "youtube.com", "youtube-nocookie.com", "youtu.be"].contains { host == $0 || host.hasSuffix("." + $0) } || host == "accounts.google.com"
    }
    static func search(_ text: String, youtube: Bool) -> URL {
        var components = URLComponents(string: youtube ? "https://www.youtube.com/results" : "https://search.bilibili.com/all")!
        components.queryItems = [URLQueryItem(name: youtube ? "search_query" : "keyword", value: String(text.prefix(512)))]
        return components.url!
    }
    static func target(_ url: URL) -> URL {
        guard allowed(url), let host = url.host?.lowercased() else { return url }
        let parts = url.path.split(separator: "/").map(String.init)
        if (host == "bilibili.com" || host.hasSuffix(".bilibili.com")), parts.count >= 2, parts[0] == "video",
           parts[1].range(of: "^BV[0-9A-Za-z]{10}$", options: .regularExpression) != nil {
            var c = URLComponents(string: "https://player.bilibili.com/player.html")!
            let part = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "p" })?.value.flatMap(Int.init) ?? 1
            c.queryItems = [URLQueryItem(name: "bvid", value: parts[1]), URLQueryItem(name: "p", value: String(min(1000, max(1, part)))), URLQueryItem(name: "autoplay", value: "1")]
            return c.url!
        }
        return url
    }
}

@MainActor final class WebMusicSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    @Published var input = ""
    @Published var youtube = false
    @Published var lastQuery = ""
    @Published var status = "搜索歌名，然后直接点选来源结果；音频在 Tom Music 内播放。"
    @Published var source: URL?
    @Published var loading = false
    weak var webView: WKWebView?
    var mediaBegan: (() -> Void)?
    private var timeout: Task<Void, Never>?
    private(set) var loadID = UUID()
    private(set) var pendingURL: URL?

    func search() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if text.contains("://") {
            guard let url = URL(string: text), WebMusicRoute.allowed(url) else { status = "这里只接受 B站 / YouTube 的公开 HTTPS 链接，不打开本机、任意网站或自定义协议。"; return }
            navigate(url)
        } else { lastQuery = text; navigate(WebMusicRoute.search(text, youtube: youtube)) }
    }
    func returnToSearch() {
        guard !lastQuery.isEmpty else { return }
        input = lastQuery; navigate(WebMusicRoute.search(lastQuery, youtube: youtube))
    }
    func navigate(_ url: URL) {
        guard WebMusicRoute.allowed(url) else { status = "站外跳转未打开；请使用来源页面提供的账户或浏览器入口。"; return }
        source = url
        pendingURL = WebMusicRoute.target(url)
        loadID = UUID()
        loading = true; status = "正在打开来源播放器…"
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled, let self, self.loading else { return }
            self.webView?.stopLoading(); self.loading = false; self.status = "来源页面连接超时；没有替换歌曲。可以手动重试或更换来源。"
        }
        objectWillChange.send()
    }
    func command(_ command: String) {
        guard let webView else { return }
        if command == "pause" { webView.pauseAllMediaPlayback(completionHandler: {}); return }
        let script = command == "toggle" ? "if(v.paused){v.play().catch(()=>{})}else{v.pause()}" : "v.play().catch(()=>{})"
        webView.evaluateJavaScript("(()=>{let v=document.querySelector('video,audio');if(v){\(script)}})()", completionHandler: nil)
    }
    func close() {
        timeout?.cancel(); timeout = nil; command("pause"); webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "tomMusicMedia")
        webView?.navigationDelegate = nil; webView?.uiDelegate = nil; webView = nil
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Subframes belong to the platform player (ads, authentication and CDN). Do not alter them.
        guard action.targetFrame?.isMainFrame != false else { decisionHandler(.allow); return }
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        guard WebMusicRoute.allowed(url) else {
            if url.absoluteString != "about:blank" { status = "站外跳转已停止：\(url.host ?? url.scheme ?? "未知地址")。" }
            decisionHandler(.cancel); return
        }
        let target = WebMusicRoute.target(url)
        if target != url {
            decisionHandler(.cancel); navigate(url); return
        }
        if action.targetFrame == nil { decisionHandler(.cancel); navigate(url); return }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url, WebMusicRoute.allowed(url) { navigate(url) }
        return nil
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading = false; timeout?.cancel(); status = "已打开来源页面；请使用页面内播放键。登录、验证或地区限制以平台提示为准。"
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
    private func failed(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        loading = false; timeout?.cancel(); status = "来源页面未能打开：\(error.localizedDescription)"
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { loading = false; status = "来源播放器进程已退出；请手动重试。" }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let url = message.frameInfo.request.url, WebMusicRoute.allowed(url),
              let value = message.body as? [String: Any], let time = value["time"] as? Double,
              let duration = value["duration"] as? Double, time.isFinite, duration.isFinite,
              time >= 0, duration > 0, duration < 604800 else { return }
        let paused = value["paused"] as? Bool ?? true
        let muted = value["muted"] as? Bool ?? true
        let volume = value["volume"] as? Double ?? 0
        if !paused { mediaBegan?() }
        status = "网页音频\(paused ? "已暂停" : "播放中") · \(timeLabel(time)) / \(timeLabel(duration))\(muted || volume == 0 ? " · 来源播放器静音" : "") · 视频版本与上传者以页面为准"
    }
}

private struct PlatformWebView: NSViewRepresentable {
    @ObservedObject var session: WebMusicSession
    final class Coordinator { var loadID: UUID? }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> WKWebView {
        let c = WKWebViewConfiguration()
        // Per-view ephemeral cookies: no reading Safari/Chrome accounts or default profile.
        c.websiteDataStore = .nonPersistent()
        c.mediaTypesRequiringUserActionForPlayback = []
        // Declare the supported Safari/WebKit compatibility baseline, retaining app identity.
        c.applicationNameForUserAgent = "Version/17.0 Safari/605.1.15 TomMusic/1.3"
        c.userContentController.add(session, name: "tomMusicMedia")
        c.userContentController.addUserScript(WKUserScript(source: """
        setInterval(function(){let v=document.querySelector('video,audio');if(v&&Number.isFinite(v.duration)&&v.duration>0){window.webkit.messageHandlers.tomMusicMedia.postMessage({time:v.currentTime,duration:v.duration,paused:v.paused,muted:v.muted,volume:v.volume})}},1000);
        """, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: c)
        view.navigationDelegate = session; view.uiDelegate = session
        session.webView = view
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loadID != session.loadID, let url = session.pendingURL else { return }
        context.coordinator.loadID = session.loadID
        var request = URLRequest(url: url, timeoutInterval: 30)
        // YouTube's documented native WebView identity, not a forged third-party referrer.
        request.setValue("https://\(Bundle.main.bundleIdentifier ?? "com.tommusic.desktop")/", forHTTPHeaderField: "Referer")
        view.load(request)
    }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.pauseAllMediaPlayback(completionHandler: {}); view.stopLoading()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "tomMusicMedia")
        view.navigationDelegate = nil; view.uiDelegate = nil
    }
}

struct WebMusicView: View {
    @EnvironmentObject var player: MusicPlayer
    @StateObject private var session = WebMusicSession()
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Picker("网页曲源", selection: $session.youtube) { Text("B站").tag(false); Text("YouTube").tag(true) }.frame(width: 125)
                TextField("输入歌名，或粘贴 B站 / YouTube 链接", text: $session.input).textFieldStyle(.roundedBorder).onSubmit { session.search() }.accessibilityLabel("站内听歌搜索")
                Button("搜索 / 打开") { session.search() }.help("搜索 / 打开网页音乐").accessibilityLabel("搜索 / 打开网页音乐").disabled(session.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            HStack {
                Button("返回搜索") { session.returnToSearch() }.help("返回网页搜索").accessibilityLabel("返回网页搜索").disabled(session.lastQuery.isEmpty)
                Button("重试") { if let source = session.source { session.navigate(source) } }.help("重试网页").accessibilityLabel("重试网页").disabled(session.source == nil)
                if let source = session.source { Link("来源 ↗", destination: source) }
                Spacer()
                if session.loading { ProgressView().controlSize(.small) }
            }.font(.caption)
            Text("平台原生网页 / 可见视频播放器，不提取音频、不下载。原版、翻唱、剪辑与上传者以来源页面为准；网页可能包含平台广告或登录要求。")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            PlatformWebView(session: session).frame(minHeight: 270).accessibilityLabel("站内网页播放器")
            Text(session.status).font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled).accessibilityIdentifier("网页播放状态")
        }
        .onAppear {
            player.beginWebSession { [weak session] in session?.command($0) }
            session.mediaBegan = { [weak session, weak player] in
                guard let session, let player, !player.webPlaybackActive else { return }
                player.beginWebSession { [weak session] in session?.command($0) }
            }
        }
        .onDisappear { session.close(); player.endWebSession() }
    }
}
