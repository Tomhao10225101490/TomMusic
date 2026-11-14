import AppKit
import SwiftUI
import WebKit

@main
struct TomMusicApp: App {
    @StateObject private var library: MusicLibrary
    @StateObject private var player: MusicPlayer
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        var root: URL?
        if let i = arguments.firstIndex(of: "--data-dir"), arguments.indices.contains(i + 1) { root = URL(fileURLWithPath: arguments[i + 1], isDirectory: true) }
        if arguments.contains("--self-test") && root == nil {
            fputs("Self-test requires an isolated --data-dir.\n", stderr)
            exit(2)
        }
        let library = MusicLibrary(root: root)
        _library = StateObject(wrappedValue: library)
        _player = StateObject(wrappedValue: MusicPlayer(library: library))
        if arguments.contains("--self-test") {
            Task { @MainActor in
                await SelfTest.run(library: library)
            }
        }
    }
    var body: some Scene {
        Window("Tom Music", id: "main") {
            ContentView().environmentObject(library).environmentObject(player)
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1140, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("导入音乐…") { library.chooseFiles() }.keyboardShortcut("o").disabled(library.importing)
                Button("导入文件夹…") { library.chooseFiles(folder: true) }.keyboardShortcut("o", modifiers: [.command, .shift]).disabled(library.importing)
                Divider()
                Button("新建播放列表") { NotificationCenter.default.post(name: .newPlaylist, object: nil) }.keyboardShortcut("n")
            }
            CommandMenu("播放控制") {
                Button(player.isPlaying ? "暂停（空格）" : "播放（空格）") { player.toggle() }
                Button("下一首") { player.next() }.keyboardShortcut(.rightArrow, modifiers: .command)
                Button("上一首") { player.previous() }.keyboardShortcut(.leftArrow, modifiers: .command)
                Divider()
                Button(player.shuffle ? "关闭随机播放" : "随机播放") { player.toggleShuffle() }
                Button("切换循环模式") { player.repeatMode = (player.repeatMode + 1) % 3 }
            }
            CommandGroup(replacing: .help) {
                Button("Tom Music 使用帮助") {
                    let alert = NSAlert()
                    alert.messageText = "你的音乐，自在聆听。"
                    alert.informativeText = "⌘O 导入音乐 · ⇧⌘O 导入文件夹\n⌘N 新建播放列表 · 空格 播放 / 暂停\n⌘→ 下一首 · ⌘← 上一首\n\n双击歌曲播放；右键歌曲可添加到播放列表或待播清单。拖入音乐文件或文件夹也可以导入。\n\n音乐会复制到本机资料库，原始文件不会被修改。本地音乐可离线听；在线免费音乐连接 Internet Archive，按来源授权下载整首后播放。\n\n全网音乐发现：五源并行搜索，Audius 公开音轨可在线播放；Apple 只显示目录及官方链接，不下载试听。另有网易云、QQ、酷狗、B站、YouTube 官方搜索入口（浏览器打开）。\n\n解析公开链接：读取单个公开 HTTPS 页面或直接音频，遵守 robots；未知权限内容须确认后保存。不保证任意歌曲都可获取，不绕过账号、付费或 DRM。请遵守署名、非商用等来源条款。"
                    alert.addButton(withTitle: "知道了")
                    alert.runModal()
                }
            }
        }
        Settings { SettingsView().environmentObject(library).environmentObject(player) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var spaceKeyMonitor: Any?
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Command-menu keyboard shortcuts consume Space before text editors can use it.
        // Handle it locally only when focus is not in an editable text control.
        spaceKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 49,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  let window = NSApp.keyWindow,
                  window.identifier?.rawValue == "main" || window.title == "Tom Music",
                  window.attachedSheet == nil else { return event }
            let responder = window.firstResponder
            if responder is NSTextView || responder is NSTextField || responder is NSComboBox { return event }
            // Let the platform webpage handle its own text input and video Space shortcut.
            var view = responder as? NSView
            while let current = view {
                if current is WKWebView { return event }
                view = current.superview
            }
            NotificationCenter.default.post(name: .togglePlayback, object: nil)
            return nil
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { sender.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil) }
        return true
    }
}

struct SettingsView: View {
    @EnvironmentObject var library: MusicLibrary
    @EnvironmentObject var player: MusicPlayer
    @AppStorage("appearance") private var appearance = "system"
    var body: some View {
        Form {
            Section("外观") {
                Picker("主题", selection: $appearance) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }
            }
            Section("音乐资料库") {
                Text("已收藏 \(library.data.tracks.count) 首歌曲").foregroundStyle(.secondary)
                LabeledContent("存储位置") { Text(library.root.path).font(.caption).textSelection(.enabled) }
                Button("在访达中打开") { NSWorkspace.shared.open(library.root) }
                Text("本地导入会复制文件，原始文件不变。仅主动搜索、解析、播放或下载时联网；无广告。官方平台可能要求账号/订阅；本应用不提供绕过。").font(.caption).foregroundStyle(.secondary)
                Text("若系统代理返回 198.18/15 Fake-IP，仅经 Cloudflare 公网 DNS-over-HTTPS 核验公开域名后访问；不修改系统代理或 DNS。网页解析不执行脚本，不读取登录 Cookie。").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Text("Tom Music 1.2.0 · 原生 macOS 音乐播放器").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).frame(width: 540, height: 440)
    }
}
