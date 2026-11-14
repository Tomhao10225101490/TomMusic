import AppKit
import AVFoundation
import MediaPlayer
import SwiftUI

@MainActor
final class MusicPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var current: Track?
    @Published var isPlaying = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var queue: [Track] = []
    @Published var shuffle = false
    @Published var repeatMode = 0 // off, all, one
    @Published var volume: Float = 0.7 { didSet { audio?.volume = volume; remote?.volume = volume } }
    @Published var remoteSource: URL?
    @Published var remoteLoading = false
    @Published var webPlaybackActive = false
    private var webTransport: ((String) -> Void)?
    func beginWebSession(_ transport: @escaping (String) -> Void) {
        if !webPlaybackActive { pause() }
        webTransport = transport; webPlaybackActive = true
    }
    func endWebSession() {
        webTransport?("pause"); webTransport = nil; webPlaybackActive = false
    }
    @Published private(set) var isTemporaryAudio = false
    private var temporaryAudio: URL?
    private var terminateObserver: NSObjectProtocol?
    var isRemote: Bool { remote != nil || isTemporaryAudio }
    private func clearTemporaryAudio() {
        if isTemporaryAudio { audio?.stop(); audio = nil }
        if let temporaryAudio { NativeAudioPolicy.remove(temporaryAudio) }
        temporaryAudio = nil; isTemporaryAudio = false
    }
    func playTemporaryAudio(_ clip: NativeAudioClip) -> Bool {
        guard NativeAudioPolicy.ownCache(clip.file) else { return false }
        do {
            let candidate = try AVAudioPlayer(contentsOf: clip.file)
            clearRemote(); audio?.stop(); audio = candidate
            candidate.delegate = self; candidate.volume = volume; candidate.prepareToPlay()
            guard candidate.play() else { throw CatalogFailure(message: "无法启动独立音频输出。") }
            temporaryAudio = clip.file; isTemporaryAudio = true
            current = Track(id: "nativeaudio:" + clip.entry.id, title: clip.entry.audioTitle + (clip.entry.version.isEmpty ? "" : " · " + clip.entry.version), artist: "上传者：" + clip.entry.uploader, album: "公开独立音轨 · " + (clip.entry.version.isEmpty ? "版本未核验" : clip.entry.version), duration: candidate.duration, fileName: "", addedAt: Date(), sourceName: "公开独立音轨")
            remoteSource = clip.entry.page; position = 0; duration = candidate.duration; isPlaying = true; error = nil
            queue = []; history = []; playbackContext = []; updateNowPlaying(); return true
        } catch { NativeAudioPolicy.remove(clip.file); self.error = "独立音频播放失败：\(error.localizedDescription)"; return false }
    }
    private var remote: AVPlayer?
    private var remoteStatus: NSKeyValueObservation?
    private var remoteState: NSKeyValueObservation?
    private var remoteEnd: NSObjectProtocol?
    private var remoteFailure: NSObjectProtocol?
    private var wantsRemotePlay = false
    private var remoteRecoveryTask: Task<Void, Never>?
    private var remoteRetry: (@MainActor () async throws -> URL)?
    private var remoteRetriesRemaining = 0
    private var remoteFailureHandled = false
    @Published var error: String?
    private var audio: AVAudioPlayer?
    private var timer: Timer?
    private var history: [Track] = []
    private var playbackContext: [Track] = []
    let library: MusicLibrary

    init(library: MusicLibrary) {
        self.library = library
        super.init()
        volume = library.data.volume
        terminateObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.clearTemporaryAudio() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if let audio = self.audio { self.position = audio.currentTime }
                else if let remote = self.remote {
                    let seconds = remote.currentTime().seconds
                    if seconds.isFinite { self.position = max(0, seconds) }
                    let duration = remote.currentItem?.duration.seconds ?? 0
                    if duration.isFinite, duration > 0 { self.duration = duration }
                }
            }
        }
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        center.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        center.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let seconds = event.positionTime
            Task { @MainActor in self?.seek(seconds) }
            return .success
        }
    }
    deinit {
        if let terminateObserver { NotificationCenter.default.removeObserver(terminateObserver) }
        if let temporaryAudio { NativeAudioPolicy.remove(temporaryAudio) }
    }
    var outputDeviceUID: String? { audio?.currentDevice }
    func play(_ track: Track, in tracks: [Track]? = nil, outputDeviceUID: String? = nil) {
        error = nil
        if let tracks {
            history = []
            playbackContext = tracks
            let index = tracks.firstIndex(where: { $0.id == track.id }) ?? 0
            queue = Array(tracks.dropFirst(index + 1))
            if shuffle { queue.shuffle() }
        } else if let current, !isRemote { history.append(current) }
        do {
            let candidate = try AVAudioPlayer(contentsOf: library.url(for: track))
            clearRemote()
            audio?.stop()
            audio = candidate
            candidate.delegate = self
            if let outputDeviceUID { candidate.currentDevice = outputDeviceUID }
            candidate.volume = volume
            candidate.prepareToPlay()
            guard candidate.play() else { throw NSError(domain: "TomMusic", code: 3, userInfo: [NSLocalizedDescriptionKey: "无法启动音频输出"]) }
            current = track
            duration = candidate.duration
            position = 0
            isPlaying = true
            updateNowPlaying()
        } catch { self.error = "无法播放「\(track.title)」：\(error.localizedDescription)" }
    }
    private func clearRemote() {
        clearTemporaryAudio()
        endWebSession()
        remoteRecoveryTask?.cancel(); remoteRecoveryTask = nil; remoteRetry = nil
        remoteRetriesRemaining = 0; remoteFailureHandled = false
        remote?.pause(); remoteStatus = nil; remoteState = nil
        if let remoteEnd { NotificationCenter.default.removeObserver(remoteEnd) }
        if let remoteFailure { NotificationCenter.default.removeObserver(remoteFailure) }
        remoteEnd = nil; remoteFailure = nil; remote = nil; remoteSource = nil
        remoteLoading = false; wantsRemotePlay = false
    }
    func playRemote(_ url: URL, title: String, artist: String, album: String, source: URL, provider: String,
                    retry: (@MainActor () async throws -> URL)? = nil, remainingRetries: Int = 1, startPosition: Double = 0) {
        clearRemote(); audio?.stop(); audio = nil
        remoteRetry = retry; remoteRetriesRemaining = min(1, max(0, remainingRetries))
        history = []; queue = []; playbackContext = []; error = nil
        let asset = AVURLAsset(url: url, options: [AVURLAssetHTTPUserAgentKey: "TomMusic/1.2 (public authorized music stream)"])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 8
        let engine = AVPlayer(playerItem: item)
        remote = engine; remoteSource = source; engine.volume = volume
        current = Track(id: "remote:" + UUID().uuidString, title: title, artist: artist, album: album, duration: 0, fileName: "", addedAt: Date(), sourceName: provider)
        position = 0; duration = 0; wantsRemotePlay = true; remoteLoading = true; isPlaying = true
        remoteStatus = item.observe(\.status, options: [.initial, .new]) { [weak self, weak engine] item, _ in
            Task { @MainActor in
                guard let self, let engine, self.remote === engine else { return }
                if item.status == .failed {
                    self.handleRemoteFailure(engine, detail: item.error?.localizedDescription ?? "来源暂时不可用")
                } else if item.status == .readyToPlay {
                    let seconds = item.duration.seconds
                    if seconds.isFinite { self.duration = max(0, seconds) }
                    self.updateNowPlaying()
                }
            }
        }
        remoteState = engine.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self, weak engine] _, _ in
            Task { @MainActor in
                guard let self, let engine, self.remote === engine else { return }
                self.remoteLoading = self.remoteRecoveryTask != nil || engine.timeControlStatus == .waitingToPlayAtSpecifiedRate
                self.isPlaying = engine.timeControlStatus == .playing || (self.remoteLoading && self.wantsRemotePlay)
                self.updateNowPlaying()
            }
        }
        remoteEnd = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self, weak engine] _ in
            Task { @MainActor in
                guard let self, let engine, self.remote === engine else { return }
                if self.repeatMode > 0, self.queue.isEmpty { self.seek(0); self.resume() } else { self.next() }
            }
        }
        remoteFailure = NotificationCenter.default.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self, weak engine] _ in
            Task { @MainActor in
                guard let self, let engine, self.remote === engine else { return }
                self.handleRemoteFailure(engine, detail: "来源播放中断")
            }
        }
        if startPosition > 0 { engine.seek(to: CMTime(seconds: startPosition, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
        engine.play(); updateNowPlaying()
    }
    private func handleRemoteFailure(_ engine: AVPlayer, detail: String) {
        guard remote === engine, !remoteFailureHandled else { return }
        remoteFailureHandled = true
        guard wantsRemotePlay, remoteRetriesRemaining > 0, let retry = remoteRetry, let track = current, let source = remoteSource else {
            pause(); error = "在线音频无法播放：\(detail)。没有替换成试听或其他歌曲；可重新选择在线播放或前往来源。"; return
        }
        remoteRetriesRemaining -= 1
        engine.pause(); isPlaying = false; remoteLoading = true
        remoteRecoveryTask = Task { [weak self, weak engine] in
            guard let self, let engine else { return }
            do {
                try await Task.sleep(nanoseconds: 900_000_000)
                let url = try await retry()
                try Task.checkCancellation()
                guard self.remote === engine, self.wantsRemotePlay else { return }
                let queue = self.queue, history = self.history, context = self.playbackContext, position = self.position
                let remaining = self.remoteRetriesRemaining
                self.remoteRecoveryTask = nil
                self.playRemote(url, title: track.title, artist: track.artist, album: track.album, source: source, provider: track.sourceName,
                                retry: retry, remainingRetries: remaining, startPosition: position)
                self.queue = queue; self.history = history; self.playbackContext = context
            } catch {
                guard !Task.isCancelled, self.remote === engine else { return }
                self.remoteRecoveryTask = nil; self.pause()
                self.error = "同一音轨重试后仍不可用：\(error.localizedDescription)。未换歌、未绕过授权；请稍后重试或前往来源。"
            }
        }
    }
    func toggle() {
        if webPlaybackActive { webTransport?("toggle"); return }
        if current == nil {
            if let first = library.data.tracks.first { play(first, in: library.data.tracks) }
        } else if isPlaying { pause() } else { resume() }
    }
    func pause() {
        if webPlaybackActive { webTransport?("pause") }
        remoteRecoveryTask?.cancel(); remoteRecoveryTask = nil
        wantsRemotePlay = false; remoteLoading = false; remote?.pause(); audio?.pause(); isPlaying = false; updateNowPlaying()
    }
    func resume() {
        if webPlaybackActive { webTransport?("play"); return }
        if let remote {
            if remote.currentItem?.status == .failed {
                wantsRemotePlay = true; remoteFailureHandled = false; remoteRetriesRemaining = 1
                handleRemoteFailure(remote, detail: "来源上次播放失败"); return
            }
            if duration > 0, position >= duration - 0.1 { seek(0) }
            wantsRemotePlay = true; remote.play(); isPlaying = true; updateNowPlaying(); return
        }
        guard let audio else { return }
        if audio.currentTime >= audio.duration - 0.1 { audio.currentTime = 0 }
        isPlaying = audio.play(); updateNowPlaying()
    }
    func seek(_ value: Double) {
        guard !webPlaybackActive else { return } // Platform's visible transport owns web seeking.
        let target = min(max(0, value), duration)
        if let remote { remote.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero); position = target }
        else { audio?.currentTime = target; position = audio?.currentTime ?? 0 }
        updateNowPlaying()
    }
    func next() {
        guard !webPlaybackActive else { return }
        if !queue.isEmpty { let track = queue.removeFirst(); play(track) }
        else if repeatMode == 1, !playbackContext.isEmpty {
            let tracks = shuffle ? playbackContext.shuffled() : playbackContext
            if let first = tracks.first { play(first, in: tracks) }
        } else { pause(); seek(duration) }
    }
    func previous() {
        guard !webPlaybackActive else { return }
        if position > 3 { seek(0); return }
        guard let last = history.popLast() else { seek(0); return }
        if let current { queue.insert(current, at: 0) }
        play(last)
        if !history.isEmpty { history.removeLast() }
    }
    func enqueue(_ track: Track, next: Bool = false) {
        if next { queue.insert(track, at: 0) } else { queue.append(track) }
    }
    func toggleShuffle() { shuffle.toggle(); if shuffle { queue.shuffle() } }
    func stopIfCurrent(_ track: Track) {
        queue.removeAll { $0.id == track.id }
        playbackContext.removeAll { $0.id == track.id }
        history.removeAll { $0.id == track.id }
        if current?.id == track.id { clearRemote(); audio?.stop(); audio = nil; current = nil; isPlaying = false; position = 0; duration = 0; MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.audio === player, self.remote == nil else { return }
            if self.repeatMode == 2 { self.seek(0); self.resume() } else { self.next() }
        }
    }
    private func updateNowPlaying() {
        guard let current else { return }
        var info: [String: Any] = [MPMediaItemPropertyTitle: current.title, MPMediaItemPropertyArtist: current.artist, MPMediaItemPropertyAlbumTitle: current.album, MPMediaItemPropertyPlaybackDuration: duration, MPNowPlayingInfoPropertyElapsedPlaybackTime: audio?.currentTime ?? position, MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0]
        if let image = library.artwork(for: current) { info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image } }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }
}
