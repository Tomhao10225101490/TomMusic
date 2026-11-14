import SwiftUI
import UniformTypeIdentifiers

private let accent = Color(red: 0.96, green: 0.22, blue: 0.34)

enum LibraryPage: Hashable {
    case discover, online, recent, artists, albums, songs, favorites, playlist(UUID)
    var title: String {
        switch self {
        case .discover: return "全网音乐发现"
        case .online: return "在线免费音乐"
        case .recent: return "最近添加"
        case .artists: return "艺人"
        case .albums: return "专辑"
        case .songs: return "歌曲"
        case .favorites: return "喜爱的歌曲"
        case .playlist: return "播放列表"
        }
    }
}

struct Artwork: View {
    @ObservedObject var library: MusicLibrary
    var track: Track?
    var size: CGFloat
    var radius: CGFloat = 8
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius).fill(LinearGradient(colors: [Color(nsColor: .quaternaryLabelColor).opacity(0.3), Color(nsColor: .quaternaryLabelColor).opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing))
            if let track, let image = library.artwork(for: track) {
                Image(nsImage: image).resizable().scaledToFill().frame(width: size, height: size).clipped()
            } else {
                Image(systemName: "music.note").font(.system(size: size * 0.35, weight: .light)).foregroundStyle(.secondary.opacity(0.55))
            }
        }
        .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: radius))
        .overlay(RoundedRectangle(cornerRadius: radius).stroke(.primary.opacity(0.05), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

struct ContentView: View {
    @EnvironmentObject var library: MusicLibrary
    @EnvironmentObject var player: MusicPlayer
    @StateObject private var online = OnlineCatalog()
    @StateObject private var discovery = DiscoveryCatalog()
    @State private var page: LibraryPage = .recent
    @State private var search = ""
    @State private var showQueue = false
    @State private var newPlaylist = false
    @State private var playlistName = ""
    @State private var albumFilter: String?
    @State private var artistFilter: String?
    @State private var dropTarget = false
    @State private var pendingDelete: Track?
    @State private var deletePlaylist = false
    @AppStorage("appearance") private var appearance = "system"

    private var title: String {
        if !search.isEmpty { return "搜索结果" }
        if let albumFilter { return library.data.tracks.first { $0.albumKey == albumFilter }?.album ?? "专辑" }
        if let artistFilter { return artistFilter }
        if case let .playlist(id) = page { return library.data.playlists.first { $0.id == id }?.name ?? "播放列表" }
        return page.title
    }
    private var tracks: [Track] {
        var result = library.data.tracks
        if !search.isEmpty {
            return result.filter { [$0.title, $0.artist, $0.album].contains { $0.localizedCaseInsensitiveContains(search) } }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        switch page {
        case .favorites: result = result.filter(\.favorite)
        case .playlist(let id):
            let ids = library.data.playlists.first { $0.id == id }?.trackIDs ?? []
            let lookup = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
            result = ids.compactMap { lookup[$0] }
        default: break
        }
        if let albumFilter { result = result.filter { $0.albumKey == albumFilter } }
        if let artistFilter { result = result.filter { $0.artist == artistFilter } }
        if case .recent = page { return result.sorted { $0.addedAt > $1.addedAt } }
        if case .playlist = page { return result }
        return result.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    private var showsGrid: Bool { search.isEmpty && albumFilter == nil && artistFilter == nil && (page == .recent || page == .albums) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar
                Divider()
                VStack(spacing: 0) {
                    topbar
                    Divider().opacity(0.5)
                    if page == .discover { MusicDiscoveryView(catalog: discovery) }
                    else if page == .online { OnlineMusicView(catalog: online) }
                    else { mainContent }
                    if library.importing {
                        HStack(spacing: 10) { ProgressView().controlSize(.small); Text(library.importStatus).lineLimit(1); Spacer() }.font(.caption).padding(12).background(.bar)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                if showQueue { Divider(); queuePanel }
            }
            Divider()
            if player.webPlaybackActive {
                HStack(spacing: 14) {
                    Image(systemName: "play.rectangle.fill").foregroundStyle(accent)
                    Text("站内网页播放器 · 使用上方平台控件选曲、调音量或拖动进度").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("暂停网页") { player.pause() }.help("暂停网页").accessibilityLabel("暂停网页")
                    Button("继续网页") { player.resume() }.help("继续网页").accessibilityLabel("继续网页")
                }.padding(.horizontal, 24).frame(height: 72).background(.bar)
            } else { PlayerBar(showQueue: $showQueue) }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(accent)
        .frame(minWidth: 980, minHeight: 640)
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .onChange(of: page) { _, _ in albumFilter = nil; artistFilter = nil; search = "" }
        .onDrop(of: [.fileURL], isTargeted: $dropTarget) { providers in
            Task {
                var urls: [URL] = []
                for provider in providers {
                    let bytes: Data? = await withCheckedContinuation { continuation in
                        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                            continuation.resume(returning: data)
                        }
                    }
                    if let bytes, let url = URL(dataRepresentation: bytes, relativeTo: nil) { urls.append(url) }
                }
                await library.importFiles(urls)
            }
            return true
        }
        .overlay { if dropTarget { RoundedRectangle(cornerRadius: 12).stroke(accent, style: StrokeStyle(lineWidth: 3, dash: [8])).padding(6).allowsHitTesting(false) } }
        .alert("新建播放列表", isPresented: $newPlaylist) {
            TextField("播放列表名称", text: $playlistName)
            Button("取消", role: .cancel) {}
            Button("创建") { if let id = library.createPlaylist(playlistName) { page = .playlist(id) }; playlistName = "" }.disabled(playlistName.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: { Text("给你喜欢的音乐一个专属空间。") }
        .alert("无法完成操作", isPresented: Binding(get: { library.error != nil || player.error != nil }, set: { if !$0 { library.error = nil; player.error = nil } })) {
            Button("好") { library.error = nil; player.error = nil }
        } message: { Text(library.error ?? player.error ?? "") }
        .alert("从资料库移除？", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button("移除", role: .destructive) { if let track = pendingDelete { player.stopIfCurrent(track); library.remove(track) }; pendingDelete = nil }
        } message: { Text("会移除资料库内的副本及播放列表记录，不影响你原来的音乐文件。") }
        .alert("删除播放列表？", isPresented: $deletePlaylist) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { if case let .playlist(id) = page { library.deletePlaylist(id); page = .recent } }
        } message: { Text("歌曲仍会保留在资料库中。") }
        .onReceive(NotificationCenter.default.publisher(for: .newPlaylist)) { _ in newPlaylist = true }
        .onReceive(NotificationCenter.default.publisher(for: .togglePlayback)) { _ in player.toggle() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "music.note").font(.system(size: 25, weight: .bold)).foregroundStyle(accent)
                Text("Tom Music").font(.system(size: 21, weight: .bold, design: .rounded))
            }.padding(.horizontal, 23).padding(.top, 48).padding(.bottom, 30)
            navItem("全网音乐发现", icon: "magnifyingglass.circle", target: .discover)
            navItem("在线免费音乐", icon: "globe", target: .online)
            Text("资料库").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary).padding(.horizontal, 24).padding(.top, 23).padding(.bottom, 9)
            navItem("最近添加", icon: "clock", target: .recent)
            navItem("艺人", icon: "music.mic", target: .artists)
            navItem("专辑", icon: "square.stack", target: .albums)
            navItem("歌曲", icon: "music.note", target: .songs)
            navItem("喜爱的歌曲", icon: "star", target: .favorites)
            HStack {
                Text("播放列表").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                Spacer()
                Button { playlistName = ""; newPlaylist = true } label: { Image(systemName: "plus").font(.system(size: 12, weight: .medium)) }.buttonStyle(.plain).help("新建播放列表 ⌘N").accessibilityLabel("新建播放列表")
            }.padding(.horizontal, 24).padding(.top, 29).padding(.bottom, 9)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(library.data.playlists) { playlist in
                        navItem(playlist.name, icon: "music.note.list", target: .playlist(playlist.id))
                    }
                    if library.data.playlists.isEmpty {
                        Text("把喜欢的音乐收在一起").font(.system(size: 11)).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.top, 4)
                    }
                }
            }
            Spacer(minLength: 10)
            VStack(alignment: .leading, spacing: 10) {
                Button { library.chooseFiles() } label: {
                    Label("导入音乐", systemImage: "plus.circle").font(.system(size: 13, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).foregroundStyle(accent).disabled(library.importing).accessibilityIdentifier("importMusic")
                Text("你的音乐，自在聆听。").font(.system(size: 10)).foregroundStyle(.tertiary)
            }.padding(24)
        }
        .frame(width: 214).frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    private func navItem(_ name: String, icon: String, target: LibraryPage) -> some View {
        Button { page = target; albumFilter = nil; artistFilter = nil; search = "" } label: {
            HStack(spacing: 11) {
                Image(systemName: icon).font(.system(size: 16)).foregroundStyle(page == target ? Color.white : accent).frame(width: 20)
                Text(name).font(.system(size: 13, weight: page == target ? .medium : .regular)).lineLimit(1)
                Spacer(minLength: 0)
            }.padding(.horizontal, 12).frame(height: 34).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(page == target ? .white : .primary)
        .background(page == target ? accent : .clear, in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 12).padding(.vertical, 1)
        .accessibilityLabel(name)
    }

    private var topbar: some View {
        HStack {
            if albumFilter != nil || artistFilter != nil {
                Button { albumFilter = nil; artistFilter = nil } label: { Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold)) }.buttonStyle(.plain).help("返回资料库")
            }
            Text("资料库").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Spacer()
            if page == .discover {
                Text("多源检索 · 公开音频 · 不伪装试听").font(.caption).foregroundStyle(.secondary)
            } else if page == .online {
                Text("Internet Archive · 开放授权曲源").font(.caption).foregroundStyle(.secondary)
            } else {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索你的音乐", text: $search).textFieldStyle(.plain).font(.system(size: 12)).accessibilityLabel("搜索你的音乐")
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).accessibilityLabel("清除搜索") }
            }.padding(.horizontal, 10).padding(.vertical, 7).frame(width: 225).background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
            }
            Menu {
                Button("导入音乐…") { library.chooseFiles() }
                Button("导入文件夹…") { library.chooseFiles(folder: true) }
                Divider()
                Picker("外观", selection: $appearance) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }
                Button("在访达中显示音乐库") { NSWorkspace.shared.open(library.root) }
            } label: { Image(systemName: "ellipsis.circle").font(.system(size: 18)).foregroundStyle(.secondary) }.menuStyle(.borderlessButton).frame(width: 28).help("更多选项")
        }.padding(.horizontal, 30).frame(height: 62)
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(title).font(.system(size: 31, weight: .bold)).lineLimit(2)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                if !tracks.isEmpty && (!showsGrid || albumFilter != nil) {
                    Button { if let first = tracks.first { player.play(first, in: tracks) } } label: { Label("播放", systemImage: "play.fill").font(.system(size: 12, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 4) }.buttonStyle(.borderedProminent)
                    Button { let shuffled = tracks.shuffled(); if let first = shuffled.first { player.play(first, in: shuffled) } } label: { Image(systemName: "shuffle").padding(.vertical, 4) }.buttonStyle(.bordered).help("随机播放")
                }
                if case .playlist = page {
                    Menu { Button("删除播放列表", role: .destructive) { deletePlaylist = true } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 24)
                }
            }.padding(.horizontal, 32).padding(.top, 29).padding(.bottom, 24)
            if tracks.isEmpty { emptyState }
            else if page == .artists && search.isEmpty && artistFilter == nil { artistGrid }
            else if showsGrid { albumGrid }
            else { songList }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var subtitle: String {
        if !search.isEmpty { return "找到 \(tracks.count) 首歌曲" }
        if library.data.tracks.isEmpty { return "为生活，留一点音乐。" }
        if page == .recent { return "让新的旋律，成为日常。" }
        return "\(tracks.count) 首歌曲 · \(timeLabel(tracks.reduce(0) { $0 + $1.duration }))"
    }
    private var emptyState: some View {
        VStack(spacing: 17) {
            ZStack {
                RoundedRectangle(cornerRadius: 26).fill(accent.opacity(0.07)).frame(width: 112, height: 112)
                Image(systemName: !search.isEmpty ? "magnifyingglass" : page == .favorites ? "star" : "music.note").font(.system(size: 47, weight: .light)).foregroundStyle(accent)
            }
            Text(!search.isEmpty ? "没有找到这首旋律" : page == .favorites ? "把心动的旋律留下" : page.isPlaylist ? "你的精选，从这里开始" : "好音乐，值得随身收藏")
                .font(.system(size: 23, weight: .semibold)).padding(.top, 7)
            Text(!search.isEmpty ? "试试其他歌曲、艺人或专辑名称。" : page == .favorites ? "点击歌曲旁的星标，在这里重遇你的最爱。" : page.isPlaylist ? "在歌曲的右键菜单中，将音乐添加到此播放列表。" : "导入你的音乐，在这里开启专属聆听时光。\n支持 MP3、M4A、FLAC 等格式，也可以直接拖入文件。")
                .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
            if library.data.tracks.isEmpty {
                Button { library.chooseFiles() } label: { Label("导入音乐", systemImage: "plus").font(.system(size: 13, weight: .semibold)).padding(.horizontal, 19).padding(.vertical, 7) }.buttonStyle(.borderedProminent).padding(.top, 8).disabled(library.importing)
                Button("或选择一个音乐文件夹") { library.chooseFiles(folder: true) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.bottom, 45)
    }

    private var albumGrid: some View {
        let groups = Dictionary(grouping: tracks, by: \.albumKey)
        let keys = groups.keys.sorted {
            if page == .recent { return (groups[$0]?.map(\.addedAt).max() ?? .distantPast) > (groups[$1]?.map(\.addedAt).max() ?? .distantPast) }
            return $0.localizedStandardCompare($1) == .orderedAscending
        }
        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 24, alignment: .top)], alignment: .leading, spacing: 27) {
                ForEach(keys, id: \.self) { key in
                    if let track = groups[key]?.first {
                        VStack(alignment: .leading, spacing: 6) {
                            GeometryReader { geo in
                                Artwork(library: library, track: track, size: geo.size.width, radius: 9)
                                    .overlay(alignment: .bottomTrailing) {
                                        Button { let items = groups[key] ?? []; if let first = items.first { player.play(first, in: items) } } label: { Image(systemName: "play.fill").font(.system(size: 15)).foregroundStyle(.white).frame(width: 34, height: 34).background(.black.opacity(0.4), in: Circle()) }.buttonStyle(.plain).padding(9).help("播放 \(track.album)")
                                    }
                            }.aspectRatio(1, contentMode: .fit).shadow(color: .black.opacity(0.07), radius: 7, y: 3)
                            Text(track.album).font(.system(size: 13, weight: .medium)).lineLimit(1).padding(.top, 4)
                            Text(track.artist).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        }.contentShape(Rectangle()).onTapGesture { albumFilter = key }
                        .accessibilityElement(children: .contain).accessibilityLabel("专辑 \(track.album)")
                        .contextMenu { Button("打开专辑") { albumFilter = key }; Button("播放专辑") { let items = groups[key] ?? []; if let first = items.first { player.play(first, in: items) } } }
                    }
                }
            }.padding(.horizontal, 32).padding(.bottom, 28)
        }
    }

    private var artistGrid: some View {
        let artists = Array(Set(tracks.map(\.artist))).sorted()
        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145, maximum: 200), spacing: 24)], spacing: 26) {
                ForEach(artists, id: \.self) { artist in
                    Button { artistFilter = artist } label: {
                        VStack(spacing: 13) {
                            Image(systemName: "music.mic").font(.system(size: 43, weight: .ultraLight)).foregroundStyle(.secondary).frame(width: 116, height: 116).background(.primary.opacity(0.045), in: Circle())
                            Text(artist).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text("\(tracks.filter { $0.artist == artist }.count) 首歌曲").font(.system(size: 11)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 32).padding(.bottom, 28)
        }
    }

    private var songList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("名称").frame(maxWidth: .infinity, alignment: .leading)
                Text("专辑").frame(width: 155, alignment: .leading)
                Image(systemName: "clock").frame(width: 48)
                Color.clear.frame(width: 37, height: 1)
            }.font(.system(size: 11)).foregroundStyle(.tertiary).padding(.leading, 65).padding(.trailing, 13).padding(.bottom, 10).padding(.horizontal, 25)
            Divider().padding(.horizontal, 32)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        HStack(spacing: 12) {
                            ZStack(alignment: .center) {
                                Artwork(library: library, track: track, size: 38, radius: 4)
                                if player.current?.id == track.id {
                                    RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.4))
                                    Image(systemName: player.isPlaying ? "waveform" : "pause.fill").foregroundStyle(.white).font(.system(size: 15))
                                }
                            }.frame(width: 38, height: 38)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.title).font(.system(size: 13, weight: .medium)).foregroundStyle(player.current?.id == track.id ? accent : .primary).lineLimit(1)
                                Text(track.artist).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Text(track.album).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).frame(width: 155, alignment: .leading)
                            Text(timeLabel(track.duration)).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary).frame(width: 48)
                            Button { library.toggleFavorite(track) } label: { Image(systemName: track.favorite ? "star.fill" : "star").font(.system(size: 13)).foregroundStyle(track.favorite ? accent : Color.secondary.opacity(0.5)) }.buttonStyle(.plain).frame(width: 25).help(track.favorite ? "取消喜爱" : "添加到喜爱").accessibilityLabel("\(track.favorite ? "取消喜爱" : "喜爱") \(track.title)")
                        }.padding(.horizontal, 13).padding(.vertical, 8)
                        .background(index.isMultiple(of: 2) ? Color.primary.opacity(0.025) : .clear, in: RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle()).onTapGesture(count: 2) { player.play(track, in: tracks) }
                        .contextMenu { trackMenu(track) }
                        .accessibilityElement(children: .contain).accessibilityLabel(track.title)
                    }
                }.padding(.horizontal, 25).padding(.bottom, 25)
            }
        }
    }
    @ViewBuilder private func trackMenu(_ track: Track) -> some View {
        Button("播放") { player.play(track, in: tracks) }
        Button("下一首播放") { player.enqueue(track, next: true) }
        Button("最后播放") { player.enqueue(track) }
        Divider()
        Button(track.favorite ? "取消喜爱" : "喜爱") { library.toggleFavorite(track) }
        Menu("添加到播放列表") {
            if library.data.playlists.isEmpty { Text("先创建一个播放列表") }
            ForEach(library.data.playlists) { list in Button(list.name) { library.add([track], to: list.id) } }
        }
        if case let .playlist(id) = page { Button("从播放列表移除") { library.removeFromPlaylist(track, id: id) } }
        Divider()
        Button("在访达中显示") { NSWorkspace.shared.activateFileViewerSelecting([library.url(for: track)]) }
        if let origin = track.origin {
            if let url = URL(string: origin.pageURL), url.scheme == "https", url.host == "archive.org" { Link("音乐来源 · \(origin.provider)", destination: url) }
            if let url = URL(string: origin.licenseURL), url.scheme == "https", ["creativecommons.org", "www.creativecommons.org"].contains(url.host ?? "") { Link("授权条款 · \(origin.licenseName)", destination: url) }
            Text("来源署名：\(origin.creator)")
        }
        Button("从资料库移除…", role: .destructive) { pendingDelete = track }
    }

    private var queuePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("待播清单").font(.system(size: 17, weight: .bold)); Spacer(); Button { showQueue = false } label: { Image(systemName: "xmark").font(.system(size: 12)) }.buttonStyle(.plain).accessibilityLabel("关闭待播清单") }.padding(.top, 26).padding(.bottom, 24)
            if let current = player.current {
                Text("正在播放").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.bottom, 12)
                queueRow(current).padding(.bottom, 24)
            }
            HStack {
                Text("接下来").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                if !player.queue.isEmpty { Button("清除") { player.queue = [] }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(accent) }
            }.padding(.bottom, 12)
            if player.queue.isEmpty {
                Text("还没有待播歌曲\n右键点击歌曲，添加到待播清单。").font(.system(size: 12)).foregroundStyle(.tertiary).lineSpacing(6).padding(.top, 18)
            }
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(Array(player.queue.enumerated()), id: \.offset) { index, track in
                        queueRow(track).contentShape(Rectangle()).onTapGesture(count: 2) { player.queue.removeFirst(index + 1); player.play(track) }.contextMenu { Button("从待播清单移除") { if index < player.queue.count { player.queue.remove(at: index) } } }
                    }
                }
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, 20).frame(width: 244).frame(maxHeight: .infinity).background(.primary.opacity(0.018))
    }
    private func queueRow(_ track: Track) -> some View {
        HStack(spacing: 10) {
            Artwork(library: library, track: track, size: 38, radius: 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(track.artist).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

extension LibraryPage {
    var isPlaylist: Bool { if case .playlist = self { return true }; return false }
}

struct PlayerBar: View {
    @EnvironmentObject var library: MusicLibrary
    @EnvironmentObject var player: MusicPlayer
    @Binding var showQueue: Bool
    @State private var scrubbing = false
    @State private var scrubPosition: Double = 0
    var body: some View {
        HStack(spacing: 23) {
            HStack(spacing: 12) {
                Artwork(library: library, track: player.current, size: 52, radius: 6)
                VStack(alignment: .leading, spacing: 5) {
                    Text(player.current?.title ?? "尚未播放").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(player.isRemote ? "\(player.remoteLoading ? "缓冲中" : player.isTemporaryAudio ? "独立音频 · 临时缓存" : "在线 · 不保存") · \(player.current?.artist ?? "")" : player.current?.artist ?? "选择一首喜欢的音乐").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let source = player.remoteSource {
                    Link(destination: source) { Image(systemName: "arrow.up.right.square") }.help("前往在线音轨来源")
                } else if let track = player.current {
                    let favorite = library.data.tracks.first { $0.id == track.id }?.favorite ?? false
                    Button { library.toggleFavorite(track) } label: { Image(systemName: favorite ? "star.fill" : "star").foregroundStyle(favorite ? accent : .secondary) }.buttonStyle(.plain).help("喜爱当前歌曲")
                }
            }.frame(width: 245)
            VStack(spacing: 6) {
                HStack(spacing: 24) {
                    control("shuffle", label: "随机播放", color: player.shuffle ? accent : .secondary) { player.toggleShuffle() }
                    control("backward.end.fill", label: "上一首", size: 18) { player.previous() }
                    control(player.isPlaying ? "pause.fill" : "play.fill", label: player.isPlaying ? "暂停" : "播放", size: 24) { player.toggle() }
                    control("forward.end.fill", label: "下一首", size: 18) { player.next() }
                    control(player.repeatMode == 2 ? "repeat.1" : "repeat", label: "循环模式", color: player.repeatMode > 0 ? accent : .secondary) { player.repeatMode = (player.repeatMode + 1) % 3 }
                }.frame(height: 29)
                HStack(spacing: 8) {
                    Text(timeLabel(scrubbing ? scrubPosition : player.position)).frame(width: 32, alignment: .trailing)
                    Slider(value: Binding(get: { scrubbing ? scrubPosition : player.position }, set: { scrubPosition = $0; if !scrubbing { player.seek($0) } }), in: 0...max(player.duration, 1), onEditingChanged: { editing in
                        if editing { scrubPosition = player.position; scrubbing = true }
                        else { player.seek(scrubPosition); scrubbing = false }
                    }).controlSize(.mini).tint(.secondary).disabled(player.current == nil).accessibilityLabel("播放进度")
                    Text(timeLabel(player.duration)).frame(width: 32, alignment: .leading)
                }.font(.system(size: 9).monospacedDigit()).foregroundStyle(.tertiary)
            }.frame(maxWidth: 530)
            Spacer(minLength: 0)
            HStack(spacing: 9) {
                Image(systemName: "speaker.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                Slider(value: $player.volume, in: 0...1, onEditingChanged: { editing in if !editing { library.data.volume = player.volume; library.save() } }).controlSize(.mini).frame(width: 76).tint(.secondary).accessibilityLabel("音量")
                Image(systemName: "speaker.wave.2.fill").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Button { showQueue.toggle() } label: { Image(systemName: "list.bullet").font(.system(size: 18)).foregroundStyle(showQueue ? accent : .secondary).frame(width: 30, height: 30).background(showQueue ? accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 5)) }.buttonStyle(.plain).help("待播清单").accessibilityLabel("待播清单")
        }.padding(.horizontal, 24).frame(height: 88).background(.bar)
    }
    private func control(_ icon: String, label: String, size: CGFloat = 13, color: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: size, weight: .medium)).foregroundStyle(color).frame(width: 25, height: 29) }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

extension Notification.Name {
    static let newPlaylist = Notification.Name("TomMusic.newPlaylist")
    static let togglePlayback = Notification.Name("TomMusic.togglePlayback")
}
