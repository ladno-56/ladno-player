import AVFoundation
import Combine
import Foundation

struct PlaybackTrack: Identifiable, Equatable {
    let id: Int
    let title: String
}

@MainActor
final class StreamPlayerModel: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime = 0.0
    @Published private(set) var duration = 0.0
    @Published private(set) var volume: Float = 0.8
    @Published private(set) var playbackRate: Float = 1
    @Published private(set) var audioTracks: [PlaybackTrack] = []
    @Published private(set) var subtitleTracks: [PlaybackTrack] = []
    @Published private(set) var selectedAudioTrackID: Int?
    @Published private(set) var selectedSubtitleTrackID: Int?

    private var itemObservation: NSKeyValueObservation?
    private var durationObservation: NSKeyValueObservation?
    private var timeObserver: (player: AVPlayer, token: Any)?
    private var playbackEndedObserver: NSObjectProtocol?
    private var audioSelectionGroup: AVMediaSelectionGroup?
    private var subtitleSelectionGroup: AVMediaSelectionGroup?
    private var trackLoadingTask: Task<Void, Never>?
    private var shouldAutoPlayWhenReady = true
    private var requestedResumeTime = 0.0
    private var doubleTapCount = 0
    private var lastDoubleTapAt = Date.distantPast
    private var introSkipWasUsed = false
    private var introSkipWindowSeconds = 180

    var canSkipIntro: Bool {
        guard !introSkipWasUsed, introSkipWindowSeconds > 0, duration > 90 else { return false }
        return currentTime <= Double(introSkipWindowSeconds) && duration - currentTime >= 90
    }

    var doubleTapStep: Double {
        doubleTapCount >= 5 ? 20 : 10
    }

    func play(
        address: String,
        defaultRate: Float = 1,
        resumeAt: Double = 0,
        autoPlay: Bool = true,
        introSkipWindow: Int = 180
    ) {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            let components = URLComponents(string: trimmedAddress),
            components.scheme?.lowercased() == "https",
            let host = components.host,
            !host.isEmpty,
            let url = components.url
        else {
            errorMessage = "Введите корректную HTTPS-ссылку на поток."
            return
        }

        stop()
        errorMessage = nil
        playbackRate = min(max(defaultRate, 0.75), 3)
        requestedResumeTime = max(resumeAt.isFinite ? resumeAt : 0, 0)
        shouldAutoPlayWhenReady = autoPlay
        introSkipWindowSeconds = introSkipWindow
        introSkipWasUsed = false

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.volume = volume
        player = newPlayer

        itemObservation = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            Task { @MainActor [weak self] in
                guard let self, self.player?.currentItem === observedItem else { return }
                switch observedItem.status {
                case .readyToPlay:
                    self.updateDuration(from: observedItem)
                    if self.requestedResumeTime > 0 {
                        self.seek(to: self.requestedResumeTime)
                        self.requestedResumeTime = 0
                    }
                    if self.shouldAutoPlayWhenReady {
                        self.startPlayback()
                    }
                    self.trackLoadingTask?.cancel()
                    self.trackLoadingTask = Task {
                        await self.loadTracks(for: observedItem)
                    }
                case .failed:
                    self.isPlaying = false
                    self.errorMessage = observedItem.error?.localizedDescription
                        ?? "Не удалось воспроизвести поток."
                default:
                    break
                }
            }
        }

        durationObservation = item.observe(\.duration, options: [.new]) { [weak self] observedItem, _ in
            let itemDuration = observedItem.duration.seconds
            guard itemDuration.isFinite, itemDuration > 0 else { return }
            Task { @MainActor [weak self] in
                guard self?.player?.currentItem === observedItem else { return }
                self?.duration = itemDuration
            }
        }

        timeObserver = (
            player: newPlayer,
            token: newPlayer.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
                queue: .main
            ) { [weak self] time in
                let seconds = time.seconds
                guard seconds.isFinite else { return }
                Task { @MainActor [weak self] in
                    self?.currentTime = max(seconds, 0)
                }
            }
        )

        playbackEndedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard self?.player?.currentItem === item else { return }
                self?.isPlaying = false
                self?.currentTime = 0
            }
        }

        isPlaying = false
        if autoPlay {
            newPlayer.playImmediately(atRate: playbackRate)
            isPlaying = true
        }
    }

    func togglePlayback() {
        guard let player else { return }

        if isPlaying {
            player.pause()
            isPlaying = false
            shouldAutoPlayWhenReady = false
        } else {
            startPlayback()
        }
    }

    func startPlayback() {
        guard let player else { return }
        if duration > 0, currentTime >= duration - 0.3 {
            seek(to: 0)
        }
        shouldAutoPlayWhenReady = true
        player.playImmediately(atRate: playbackRate)
        isPlaying = true
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite, let player else { return }
        let nonnegativeTime = max(seconds, 0)
        let boundedTime = min(nonnegativeTime, duration > 0 ? duration : nonnegativeTime)
        player.seek(
            to: CMTime(seconds: boundedTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        currentTime = boundedTime
    }

    func skip(by seconds: Double) {
        guard seconds.isFinite else { return }
        seek(to: currentTime + seconds)
    }

    func handleDoubleTapForward(isForward: Bool) {
        let now = Date()
        if now.timeIntervalSince(lastDoubleTapAt) > 2 {
            doubleTapCount = 0
        }
        lastDoubleTapAt = now
        let step = doubleTapStep
        doubleTapCount += 1
        skip(by: isForward ? step : -step)
    }

    func skipIntro() {
        guard canSkipIntro else { return }
        introSkipWasUsed = true
        skip(by: 90)
    }

    func setVolume(to newVolume: Float) {
        guard newVolume.isFinite else { return }
        volume = min(max(newVolume, 0), 1)
        player?.volume = volume
    }

    func setPlaybackRate(to newRate: Float) {
        guard newRate.isFinite, (0.75...3).contains(newRate) else { return }
        playbackRate = newRate
        if isPlaying {
            player?.rate = newRate
        }
    }

    func selectAudioTrack(id: Int) {
        guard
            let playerItem = player?.currentItem,
            let audioSelectionGroup,
            audioSelectionGroup.options.indices.contains(id)
        else {
            return
        }

        let option = audioSelectionGroup.options[id]
        playerItem.select(option, in: audioSelectionGroup)
        selectedAudioTrackID = id
    }

    func selectSubtitleTrack(id: Int?) {
        guard
            let playerItem = player?.currentItem,
            let subtitleSelectionGroup
        else {
            return
        }

        if let id {
            guard subtitleSelectionGroup.options.indices.contains(id) else { return }
            playerItem.select(subtitleSelectionGroup.options[id], in: subtitleSelectionGroup)
            selectedSubtitleTrackID = id
        } else {
            playerItem.select(nil, in: subtitleSelectionGroup)
            selectedSubtitleTrackID = nil
        }
    }

    func stop() {
        trackLoadingTask?.cancel()
        trackLoadingTask = nil

        if let playbackEndedObserver {
            NotificationCenter.default.removeObserver(playbackEndedObserver)
            self.playbackEndedObserver = nil
        }

        if let timeObserver {
            timeObserver.player.removeTimeObserver(timeObserver.token)
            self.timeObserver = nil
        }

        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        itemObservation = nil
        durationObservation = nil
        audioSelectionGroup = nil
        subtitleSelectionGroup = nil
        audioTracks = []
        subtitleTracks = []
        selectedAudioTrackID = nil
        selectedSubtitleTrackID = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        errorMessage = nil
        shouldAutoPlayWhenReady = true
        requestedResumeTime = 0
        introSkipWindowSeconds = 0
        introSkipWasUsed = false
        doubleTapCount = 0
    }

    private func updateDuration(from item: AVPlayerItem) {
        let itemDuration = item.duration.seconds
        guard itemDuration.isFinite, itemDuration > 0 else { return }
        duration = itemDuration
    }

    private func loadTracks(for item: AVPlayerItem) async {
        do {
            let characteristics = try await item.asset.load(
                .availableMediaCharacteristicsWithMediaSelectionOptions
            )
            let audioGroup: AVMediaSelectionGroup?
            let subtitleGroup: AVMediaSelectionGroup?

            if characteristics.contains(.audible) {
                audioGroup = try await item.asset.loadMediaSelectionGroup(for: .audible)
            } else {
                audioGroup = nil
            }

            if characteristics.contains(.legible) {
                subtitleGroup = try await item.asset.loadMediaSelectionGroup(for: .legible)
            } else {
                subtitleGroup = nil
            }

            guard player?.currentItem === item, !Task.isCancelled else { return }

            audioSelectionGroup = audioGroup
            subtitleSelectionGroup = subtitleGroup
            audioTracks = audioGroup?.options.enumerated().map { index, option in
                PlaybackTrack(id: index, title: option.displayName)
            } ?? []
            subtitleTracks = subtitleGroup?.options.enumerated().map { index, option in
                PlaybackTrack(id: index, title: option.displayName)
            } ?? []

            if let audioGroup,
               let selectedOption = item.currentMediaSelection.selectedMediaOption(in: audioGroup) {
                selectedAudioTrackID = audioGroup.options.firstIndex(of: selectedOption)
            }

            if let subtitleGroup,
               let selectedOption = item.currentMediaSelection.selectedMediaOption(in: subtitleGroup) {
                selectedSubtitleTrackID = subtitleGroup.options.firstIndex(of: selectedOption)
            }
        } catch {
            guard player?.currentItem === item, !Task.isCancelled else { return }
            errorMessage = "Видео запущено, но не удалось загрузить варианты дорожек: \(error.localizedDescription)"
        }
    }
}
