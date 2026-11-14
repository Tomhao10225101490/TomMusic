import AppKit
import SwiftUI

struct MusicDiscoveryView: View {
    @ObservedObject var catalog: DiscoveryCatalog
    @EnvironmentObject var library: MusicLibrary
    @EnvironmentObject var player: MusicPlayer
    @State private var mode = 3
    @State private var showStatus = false
    private let tint = Color(red: 0.96, green: 0.22, blue: 0.34)
    var body: some View {
        VStack(alignment: .leading, spacing: mode >= 2 ? 8 : 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("全网音乐发现").font(.system(size: mode >= 2 ? 24 : 30, weight: .bold))
                    if mode < 2 { Text("多源并行检索，真实标注可播放、可保存与官方页面。不是“所有歌曲都能免费获取”的承诺。")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 5)
            }
            Picker("发现方式", selection: $mode) {
                Text("多源搜索").tag(0); Text("解析公开链接").tag(1); Text("网页 / MV").tag(2); Text("直接听歌").tag(3)
            }.pickerStyle(.segmented).frame(width: 500).accessibilityLabel("发现方式")
            if mode == 0 { searchControls } else if mode == 1 { resolverControls }
            if let error = catalog.error {
                HStack(alignment: .top) {
                    Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                    Spacer(); Button { catalog.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("关闭发现提示")
                }
            }
            if catalog.busyID != nil {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(catalog.progress > 0 ? "正在保存完整音频 · \(Int(catalog.progress * 100))%" : "正在连接来源 / 核验音轨…").font(.caption)
                    Spacer(); Button("取消操作") { catalog.cancelAction() }
                }
            }
            Divider()
            if mode == 0 { searchResults } else if mode == 1 { resolverResults } else if mode == 2 { WebMusicView() } else { NativeAudioView() }
        }.padding(.horizontal, 30).padding(.top, mode >= 2 ? 12 : 25).padding(.bottom, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: mode) { _, value in if value >= 2 { catalog.cancelAction(); catalog.cancelSearch(); catalog.cancelResolve() } }
    }
    private var searchControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("搜索歌曲、歌手或专辑（支持中文）", text: $catalog.query).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("多源音乐搜索").onSubmit { catalog.search() }
                Button("并行搜索") { catalog.search() }.buttonStyle(.borderedProminent).disabled(catalog.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Menu("更多平台 ↗") {
                    Text("在浏览器打开官方搜索；不是本应用内抓流")
                    ForEach(MusicDiscoveryService.officialSearches(catalog.query), id: \.0) { name, url in Link(name, destination: url) }
                }.menuStyle(.borderlessButton).frame(width: 102).disabled(catalog.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("其他平台官方搜索")
                if catalog.searching { Button("停止搜索") { catalog.cancelSearch() } }
            }
            HStack {
                Picker("结果来源", selection: $catalog.filter) {
                    Text("全部来源").tag("全部")
                    ForEach(MusicProvider.allCases) { provider in Text(provider.rawValue).tag(provider.rawValue) }
                }.frame(maxWidth: 255).accessibilityLabel("筛选音乐来源")
                Spacer(minLength: 8)
                Picker("Apple 目录地区", selection: $catalog.country) {
                    Text("香港").tag("hk"); Text("中国大陆").tag("cn"); Text("美国").tag("us"); Text("英国").tag("gb"); Text("日本").tag("jp")
                }.frame(width: 210).accessibilityLabel("Apple 目录地区")
            }.font(.caption)
            if catalog.hasSearched {
                DisclosureGroup(isExpanded: $showStatus) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(MusicProvider.allCases) { provider in
                            HStack(alignment: .top) {
                                Text(provider.rawValue).frame(width: 135, alignment: .leading)
                                if let status = catalog.statuses.first(where: { $0.provider == provider }) {
                                    Text(status.error.map { "失败：" + $0 } ?? "\(status.entries.count) 条 · \(String(format: "%.1f", status.seconds)) 秒")
                                        .foregroundStyle(status.error == nil ? Color.secondary : .orange).textSelection(.enabled)
                                } else { Text(catalog.searching ? "等待 / 请求中" : "已停止").foregroundStyle(.secondary) }
                            }
                        }
                    }.font(.system(size: 11)).padding(.top, 7)
                } label: {
                    HStack(spacing: 7) {
                        if catalog.searching { ProgressView().controlSize(.mini) }
                        Text("已返回 \(catalog.statuses.count)/5 个来源 · \(catalog.uniqueCount) 条去重结果\(catalog.statuses.contains(where: { $0.error != nil }) ? " · 有来源失败（展开查看）" : "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    private var searchResults: some View {
        Group {
            if catalog.filtered.isEmpty {
                empty(catalog.searching ? "正在连接多个曲源" : catalog.hasSearched ? "没有匹配的可展示结果" : "从一首歌，发现更多音乐", subtitle: catalog.hasSearched ? "可更换关键词或来源筛选；个别来源失败不会被其他歌曲或演示数据掩盖。" : "Apple 官方目录、Audius、ccMixter、Wikimedia Commons、Internet Archive。\n平台公开音轨可播放（不保证原版或完整歌曲），开放授权音频可保存；订阅歌曲前往官方。")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) { ForEach(catalog.filtered) { entry in row(entry); Divider().opacity(0.4) } }
                }.accessibilityLabel("多源音乐结果")
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var resolverControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("粘贴公开 HTTPS 网页或音频链接", text: $catalog.publicURL).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("公开音乐链接").onSubmit { catalog.resolve() }
                Button("解析链接") { catalog.resolve() }.buttonStyle(.borderedProminent).disabled(catalog.publicURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if catalog.resolving { Button("停止解析") { catalog.cancelResolve() } }
            }
            Text("仅解析这一页的 audio / source、OpenGraph、AudioObject 和直接音频链接。尊重 robots.txt，不登录、不执行脚本、不递归抓取或绕过 DRM。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !catalog.resolved.isEmpty {
                Toggle("我已确认有权保存所选音频（公开链接不等于无版权或完整歌曲）", isOn: $catalog.confirmRights)
                    .toggleStyle(.checkbox).font(.caption).accessibilityLabel("确认音频使用权限")
            }
        }
    }
    private var resolverResults: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !catalog.resolverMessage.isEmpty { Text(catalog.resolverMessage).font(.caption).foregroundStyle(catalog.resolved.isEmpty ? .secondary : .primary).textSelection(.enabled) }
            if catalog.resolving { ProgressView("读取公开页面…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if catalog.resolved.isEmpty { empty("把公开音频带进资料库", subtitle: "最多读取 2 MB 网页、展示 30 个去重链接；每跳检查公开域名，拒绝本机/内网与官方试听素材。\n未知权限内容需确认后保存；单首 80 MB。无法读取的页面会明确报错。") }
            else { ScrollView { LazyVStack(spacing: 0) { ForEach(catalog.resolved) { entry in row(entry); Divider().opacity(0.4) } } } }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func empty(_ title: String, subtitle: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.circle").font(.system(size: 50, weight: .ultraLight)).foregroundStyle(tint)
            Text(title).font(.title3.weight(.semibold))
            Text(subtitle).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(15)
    }
    private func row(_ entry: DiscoveryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.title).font(.system(size: 14, weight: .semibold)).lineLimit(2).textSelection(.enabled)
                    Text([entry.artist, entry.album].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                action(entry)
            }
            HStack(spacing: 7) {
                Text(entry.provider).foregroundStyle(.secondary)
                if let media = entry.mediaURL, !media.pathExtension.isEmpty { Text(media.pathExtension.uppercased()).foregroundStyle(.secondary) }
                Text(entry.capability.rawValue).foregroundStyle([.download, .stream].contains(entry.capability) ? Color.green : tint)
                if !entry.versionHint.isEmpty { Text(entry.versionHint).foregroundStyle(.orange).lineLimit(1) }
                if entry.seconds > 0 { Text((entry.capability == .official ? "目录 " : "") + timeLabel(entry.seconds)).foregroundStyle(.tertiary) }
                Spacer(minLength: 0)
                if let license = entry.licenseURL { Link(entry.licenseName, destination: license) }
                Link("来源 ↗", destination: entry.pageURL)
            }.font(.system(size: 10))
            Text(entry.note).font(.system(size: 10)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 14).padding(.horizontal, 4)
            .contextMenu {
                Link("前往来源", destination: entry.pageURL)
                Button("复制来源链接") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(entry.pageURL.absoluteString, forType: .string) }
            }
    }
    @ViewBuilder private func action(_ entry: DiscoveryEntry) -> some View {
        switch entry.capability {
        case .official: Link("前往官方", destination: entry.pageURL).buttonStyle(.bordered)
        case .page: Link("来源页面", destination: entry.pageURL).buttonStyle(.bordered)
        case .download, .permission, .stream, .album:
            Button(entry.capability == .stream ? "在线播放" : entry.capability == .album ? "展开音轨" : "保存并播放") { catalog.act(entry, library: library, player: player) }
                .buttonStyle(.bordered).disabled(catalog.busyID != nil || (entry.capability == .permission && !catalog.confirmRights))
                .accessibilityLabel((entry.capability == .stream ? "在线播放 " : entry.capability == .album ? "展开音轨 " : "保存并播放 ") + entry.title)
        }
    }
}
