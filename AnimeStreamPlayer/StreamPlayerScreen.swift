import AVFoundation
import AVKit
import SwiftUI
import UIKit

@MainActor
struct StreamPlayerScreen: View {
    @EnvironmentObject private var appStore: AnimeAppStore
    @Environment(\.dismiss) private var dismiss

    let anime: AnimeTitle
    let episode: AnimeEpisode
    let streamURL: URL

    @StateObject private var model = StreamPlayerModel()
    @State private var asksToResume = false
    @State private var seekFeedback: String?
    @State private var lastProgressSave = Date.distantPast
    @State private var didMarkCompleted = false
    @State private var controlsVisible = true
    @State private var hideControlsTask: Task<Void, Never>?

    private var savedProgress: AnimeWatchProgress? {
        guard let progress = appStore.progressByAnime[anime.id],
              progress.episodeID == episode.id,
              progress.seconds >= 15,
              progress.duration <= 0 || progress.duration - progress.seconds > 10
        else {
            return nil
        }
        return progress
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible.toggle()
        }
        if controlsVisible {
            scheduleHideControls()
        } else {
            hideControlsTask?.cancel()
        }
    }

    private func scheduleHideControls() {
        hideControlsTask?.cancel()
        guard model.isPlaying else { return }
        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                controlsVisible = false
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                videoArea

                VStack(alignment: .leading, spacing: 15) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(anime.title)
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .lineLimit(2)
                            Text("Серия \(episode.number) · \(episode.title)")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            closePlayer()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.1), in: Circle())
                        }
                        .accessibilityLabel("Закрыть плеер")
                    }

                    if model.errorMessage != nil {
                        Text(model.errorMessage ?? "")
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 10) {
                        Label("Прогресс сохраняется автоматически", systemImage: "bookmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if model.canSkipIntro {
                            Text("Кнопка опенинга — в плеере")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(appStore.preferences.accentColor)
                        }
                    }
                }
                .padding(18)

                Spacer(minLength: 0)
            }
            .background(Color.black.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .statusBarHidden()
            .alert("Продолжить просмотр?", isPresented: $asksToResume) {
                Button("С начала", role: .destructive) {
                    appStore.clearProgress(for: anime.id)
                    startPlayback(resumeAt: 0)
                }
                Button("Продолжить") {
                    startPlayback(resumeAt: savedProgress?.seconds ?? 0)
                }
            } message: {
                Text("Остановились на \(formatTime(savedProgress?.seconds ?? 0)). Продолжить с этого момента?")
            }
            .task {
                if savedProgress != nil {
                    asksToResume = true
                } else {
                    startPlayback(resumeAt: 0)
                }
            }
            .onChange(of: model.currentTime) { seconds in
                guard seconds > 0 else { return }
                let now = Date()
                guard now.timeIntervalSince(lastProgressSave) >= 5 else { return }
                lastProgressSave = now
                saveProgress(seconds: seconds)

                if !didMarkCompleted, model.duration > 0, seconds / model.duration >= 0.95 {
                    didMarkCompleted = true
                    appStore.markEpisodeWatched(episode.number, title: anime)
                    appStore.clearProgress(for: anime.id)
                }
            }
            .onChange(of: model.duration) { duration in
                guard !didMarkCompleted, duration > 0, model.currentTime / duration >= 0.95 else { return }
                didMarkCompleted = true
                appStore.markEpisodeWatched(episode.number, title: anime)
                appStore.clearProgress(for: anime.id)
            }
            .onChange(of: model.isPlaying) { isPlaying in
                if isPlaying {
                    scheduleHideControls()
                } else {
                    hideControlsTask?.cancel()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        controlsVisible = true
                    }
                }
            }
            .onDisappear {
                hideControlsTask?.cancel()
                saveProgress(seconds: model.currentTime)
                model.stop()
            }
        }
        .preferredColorScheme(.dark)
    }

    private var videoArea: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let player = model.player {
                    PlayerLayerRepresentable(player: player)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleControls()
                        }
                        .overlay {
                            doubleTapZones(width: geometry.size.width)
                        }
                } else if model.errorMessage == nil {
                    ProgressView("Подключаем видео…")
                        .tint(.white)
                        .foregroundStyle(.white)
                }

                if let seekFeedback {
                    Text(seekFeedback)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.6), in: Capsule())
                        .transition(.opacity)
                }

                if controlsVisible {
                    VStack {
                        HStack {
                            AirPlayPicker()
                                .frame(width: 32, height: 32)
                            Spacer()
                        }
                        Spacer()
                        playerControls
                    }
                    .padding(14)
                    .transition(.opacity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .background(.black)
        .accessibilityIdentifier("animeStreamPlayer")
    }

    private var playerControls: some View {
        VStack(spacing: 10) {
            if model.canSkipIntro {
                HStack {
                    Spacer()
                    Button {
                        model.skipIntro()
                    } label: {
                        Label("Пропустить опенинг · 1:30", systemImage: "forward.end.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(.black.opacity(0.68), in: Capsule())
                            .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                    }
                    .accessibilityIdentifier("skipIntroButton")
                }
            }

            Slider(
                value: Binding(
                    get: { model.currentTime },
                    set: { model.seek(to: $0) }
                ),
                in: 0...max(model.duration, 1),
                onEditingChanged: { editing in
                    if !editing { scheduleHideControls() }
                }
            )
            .tint(appStore.preferences.accentColor)
            .disabled(model.duration <= 0)
            .accessibilityLabel("Позиция воспроизведения")

            HStack(spacing: 15) {
                Text("\(formatTime(model.currentTime)) / \(formatTime(model.duration))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                trackMenus
                Button(action: model.togglePlayback) {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 37, height: 37)
                        .background(appStore.preferences.accentColor, in: Circle())
                }
                .accessibilityLabel(model.isPlaying ? "Пауза" : "Воспроизвести")
                .accessibilityIdentifier("playPauseButton")
            }
        }
        .padding(13)
        .background {
            LinearGradient(
                colors: [.clear, .black.opacity(0.86)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
    }

    private var trackMenus: some View {
        HStack(spacing: 7) {
            Menu {
                if model.audioTracks.isEmpty {
                    Text("Нет доступных аудиодорожек")
                }
                ForEach(model.audioTracks) { track in
                    Button(track.title) { model.selectAudioTrack(id: track.id) }
                }
            } label: {
                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 31, height: 31)
                    .background(.white.opacity(0.15), in: Circle())
            }
            .accessibilityLabel("Аудиодорожки")

            Menu {
                Button("Субтитры выключены") { model.selectSubtitleTrack(id: nil) }
                ForEach(model.subtitleTracks) { track in
                    Button(track.title) { model.selectSubtitleTrack(id: track.id) }
                }
            } label: {
                Image(systemName: "captions.bubble")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 31, height: 31)
                    .background(.white.opacity(0.15), in: Circle())
            }
            .accessibilityLabel("Субтитры")

            Menu {
                ForEach(playbackRates, id: \.self) { rate in
                    Button("\(rate.formatted(.number.precision(.fractionLength(2))))×") {
                        model.setPlaybackRate(to: Float(rate))
                    }
                }
            } label: {
                Text("\(model.playbackRate.formatted(.number.precision(.fractionLength(2))))×")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 38, minHeight: 31)
                    .background(.white.opacity(0.15), in: Capsule())
            }
            .accessibilityLabel("Скорость воспроизведения")
        }
    }

    private func doubleTapZones(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture(count: 2)
                        .onEnded { _ in showSeekFeedback(isForward: false) }
                )
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture(count: 2)
                        .onEnded { _ in showSeekFeedback(isForward: true) }
                )
        }
        .frame(width: width, height: max(geometryHeight(width: width), 1))
        .allowsHitTesting(true)
    }

    private func geometryHeight(width: CGFloat) -> CGFloat {
        width * 9 / 16
    }

    private func showSeekFeedback(isForward: Bool) {
        let step = model.doubleTapStep
        model.handleDoubleTapForward(isForward: isForward)
        withAnimation(.easeInOut(duration: 0.15)) {
            seekFeedback = "\(isForward ? "+" : "−")\(Int(step)) сек."
        }
        Task {
            try? await Task.sleep(nanoseconds: 750_000_000)
            withAnimation(.easeInOut(duration: 0.2)) {
                seekFeedback = nil
            }
        }
    }

    private var playbackRates: [Double] {
        [0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75, 3]
    }

    private func startPlayback(resumeAt seconds: Double) {
        model.play(
            address: streamURL.absoluteString,
            defaultRate: Float(appStore.preferences.defaultPlaybackRate),
            resumeAt: seconds,
            introSkipWindow: appStore.preferences.skipWindow.rawValue
        )
        appStore.markEpisodeOpened(episode.number, title: anime)
    }

    private func saveProgress(seconds: Double) {
        guard seconds > 0 else { return }
        if model.duration > 0, seconds / model.duration >= 0.95 {
            appStore.markEpisodeWatched(episode.number, title: anime)
            appStore.clearProgress(for: anime.id)
        } else {
            appStore.saveProgress(
                anime: anime,
                episode: episode,
                seconds: seconds,
                duration: model.duration
            )
        }
    }

    private func closePlayer() {
        saveProgress(seconds: model.currentTime)
        model.stop()
        dismiss()
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remaining = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remaining)
        }
        return String(format: "%02d:%02d", minutes, remaining)
    }
}

private struct PlayerLayerRepresentable: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> AnimePlayerLayerView {
        let view = AnimePlayerLayerView()
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: AnimePlayerLayerView, context: Context) {
        uiView.playerLayer.player = player
    }

    static func dismantleUIView(_ uiView: AnimePlayerLayerView, coordinator: ()) {
        uiView.playerLayer.player = nil
    }
}

private final class AnimePlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspect
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct AirPlayPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = true
        picker.tintColor = .white
        picker.backgroundColor = .clear
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
