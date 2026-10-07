import SwiftUI
import UIKit
import UserNotifications
import CryptoKit

private enum AppPalette {
    static func background(_ theme: AnimeTheme) -> Color {
        switch theme {
        case .midnight: return Color(red: 0.035, green: 0.043, blue: 0.075)
        case .amoled: return .black
        case .light: return Color(red: 0.96, green: 0.965, blue: 0.985)
        }
    }

    static func surface(_ theme: AnimeTheme) -> Color {
        switch theme {
        case .midnight: return Color(red: 0.075, green: 0.086, blue: 0.13)
        case .amoled: return Color(red: 0.075, green: 0.075, blue: 0.09)
        case .light: return .white
        }
    }

    static func muted(_ theme: AnimeTheme) -> Color {
        theme == .light ? Color.secondary : Color(red: 0.56, green: 0.6, blue: 0.7)
    }
}

private enum MainTab: Hashable {
    case feed
    case library
    case settings
}

@MainActor
struct AnimeAppShell: View {
    @EnvironmentObject private var appStore: AnimeAppStore
    @State private var selectedTab: MainTab = .feed

    var body: some View {
        TabView(selection: $selectedTab) {
            AnimeFeedView()
                .tabItem { Label("Лента", systemImage: "sparkles.rectangle.stack") }
                .tag(MainTab.feed)

            AnimeLibraryView()
                .tabItem { Label("Библиотека", systemImage: "books.vertical") }
                .tag(MainTab.library)

            AnimeSettingsView()
                .tabItem { Label("Настройки", systemImage: "slider.horizontal.3") }
                .tag(MainTab.settings)
        }
        .tint(appStore.preferences.accentColor)
        .task {
            await appStore.loadAiringTitles()
        }
    }
}

@MainActor
private struct AnimeFeedView: View {
    @EnvironmentObject private var appStore: AnimeAppStore
    @State private var searchText = ""
    @State private var selectedAnime: AnimeTitle?

    private var columns: [GridItem] {
        if appStore.preferences.gridStyle == .list {
            return [GridItem(.flexible())]
        }
        return Array(
            repeating: GridItem(.flexible(), spacing: 12),
            count: appStore.preferences.gridStyle.columnCount
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    topBanner

                    if let catalogError = appStore.catalogError {
                        InlineNotice(text: catalogError, symbol: "exclamationmark.triangle")
                    }

                    if appStore.isLoadingCatalog && appStore.airingTitles.isEmpty {
                        ProgressView("Обновляем каталог…")
                            .frame(maxWidth: .infinity, minHeight: 180)
                    } else if appStore.airingTitles.isEmpty {
                        catalogEmptyState
                    } else {
                        catalogHeading
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(appStore.airingTitles) { anime in
                                AnimeCard(
                                    anime: anime,
                                    style: appStore.preferences.gridStyle,
                                    theme: appStore.preferences.theme
                                ) {
                                    selectedAnime = anime
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(AppPalette.background(appStore.preferences.theme))
            .navigationTitle("Лента")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Найти аниме")
            .onChange(of: searchText) { query in
                appStore.search(query: query)
            }
            .refreshable {
                await appStore.refreshCatalog()
            }
            .sheet(item: $selectedAnime) { anime in
                AnimeDetailView(anime: anime)
            }
        }
    }

    private var topBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("СЕЗОННЫЕ НОВИНКИ", systemImage: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(appStore.preferences.accentColor)

                Spacer()

                Button {
                    Task { await appStore.refreshCatalog() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppPalette.muted(appStore.preferences.theme))
                }
                .accessibilityLabel("Обновить список аниме")
            }

            Text("Что выходит сейчас")
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .foregroundStyle(appStore.preferences.theme == .light ? Color.black : Color.white)

            Text("Свежие тайтлы и новые серии в одном месте.")
            .font(.system(size: 13))
            .foregroundStyle(AppPalette.muted(appStore.preferences.theme))
            .fixedSize(horizontal: false, vertical: true)

            Text("Каталог и расписание: AniList · обнови экран для свежих данных")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppPalette.muted(appStore.preferences.theme))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    appStore.preferences.accentColor.opacity(0.18),
                    AppPalette.surface(appStore.preferences.theme)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }

    private var catalogHeading: some View {
        HStack {
            Text(searchText.isEmpty ? "Сейчас выходит" : "Результаты поиска")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(appStore.preferences.theme == .light ? Color.black : Color.white)
            Spacer()
            Text("\(appStore.airingTitles.count)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppPalette.muted(appStore.preferences.theme))
        }
    }

    private var catalogEmptyState: some View {
        VStack(spacing: 13) {
            Image(systemName: searchText.isEmpty ? "antenna.radiowaves.left.and.right" : "magnifyingglass")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(appStore.preferences.accentColor)

            Text(searchText.isEmpty ? "Пока ничего не найдено" : "Совпадений не найдено")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(appStore.preferences.theme == .light ? .black : .white)

            Text(searchText.isEmpty
                ? "Потяни экран вниз, чтобы обновить каталог."
                : "Измени запрос и попробуй ещё раз.")
            .font(.system(size: 13))
            .foregroundStyle(AppPalette.muted(appStore.preferences.theme))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(AppPalette.surface(appStore.preferences.theme), in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct AnimeCard: View {
    let anime: AnimeTitle
    let style: AnimeGridStyle
    let theme: AnimeTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if style == .list {
                listCard
            } else {
                gridCard
            }
        }
        .buttonStyle(.plain)
    }

    private var gridCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            poster
                .frame(height: style == .threeColumns ? 148 : 205)

            Text(anime.title)
                .font(.system(size: style == .threeColumns ? 12 : 14, weight: .bold))
                .foregroundStyle(theme == .light ? Color.black : Color.white)
                .lineLimit(2)

            Label(
                "\(anime.releasedEpisodeCount) серий вышло",
                systemImage: "play.rectangle"
            )
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(AppPalette.muted(theme))
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var listCard: some View {
        HStack(spacing: 13) {
            poster.frame(width: 76, height: 94)
            VStack(alignment: .leading, spacing: 8) {
                Text(anime.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(theme == .light ? Color.black : Color.white)
                    .lineLimit(2)
                Text(anime.synopsis.isEmpty ? "Описание появится из каталога." : anime.synopsis)
                    .font(.system(size: 12))
                    .foregroundStyle(AppPalette.muted(theme))
                    .lineLimit(2)
                Label("\(anime.releasedEpisodeCount) серий вышло", systemImage: "play.rectangle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppPalette.muted(theme))
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(AppPalette.surface(theme), in: RoundedRectangle(cornerRadius: 16))
    }

    private var poster: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: posterColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let posterURL = anime.posterURL {
                AsyncImage(url: posterURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
            if anime.isAiring {
                Text("ОНГОИНГ")
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.32), in: Capsule())
                    .padding(8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var posterColors: [Color] {
        let seed = abs(anime.id.hashValue)
        let hue = Double(seed % 360) / 360
        return [
            Color(hue: hue, saturation: 0.66, brightness: 0.72),
            Color(hue: (hue + 0.18).truncatingRemainder(dividingBy: 1), saturation: 0.75, brightness: 0.42)
        ]
    }
}

@MainActor
private struct AnimeDetailView: View {
    @EnvironmentObject private var appStore: AnimeAppStore
    @Environment(\.dismiss) private var dismiss
    let anime: AnimeTitle

    @State private var stage: DetailStage = .description
    @State private var selectedVoice: AnimeStreamOption?
    @State private var voiceOptions: [AnimeStreamOption] = []
    @State private var episodes: [AnimeEpisode] = []
    @State private var selectedEpisode: AnimeEpisode?
    @State private var streamAddress = ""
    @State private var isLoadingVoices = false
    @State private var isLoadingEpisodes = false
    @State private var isResolvingStream = false
    @State private var errorMessage: String?
    @State private var activeEpisode: AnimeEpisode?
    @State private var activeStreamURL: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero

                    if let errorMessage {
                        InlineNotice(text: errorMessage, symbol: "exclamationmark.triangle")
                    }

                    switch stage {
                    case .description:
                        descriptionContent
                    case .voices:
                        voicePicker
                    case .episodes:
                        episodePicker
                    }
                }
                .padding(20)
            }
            .background(AppPalette.background(appStore.preferences.theme))
            .navigationTitle(anime.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Закрыть") { dismiss() }
                }
                if stage != .description {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            stage = stage == .episodes ? .voices : .description
                            errorMessage = nil
                        } label: {
                            Image(systemName: "arrow.left")
                        }
                        .accessibilityLabel("Назад")
                    }
                }
            }
            .fullScreenCover(
                item: $activeEpisode,
                onDismiss: {
                    activeEpisode = nil
                    activeStreamURL = nil
                }
            ) { episode in
                if let activeStreamURL {
                    StreamPlayerScreen(
                        anime: anime,
                        episode: episode,
                        streamURL: activeStreamURL
                    )
                } else {
                    Text("Поток не выбран")
                }
            }
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 22)
                .fill(
                    LinearGradient(
                        colors: [appStore.preferences.accentColor.opacity(0.8), .black.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 190)
            VStack(alignment: .leading, spacing: 7) {
                Text(anime.isAiring ? "СЕЙЧАС ВЫХОДИТ" : "АНИМЕ")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.8))
                Text(anime.title)
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Label("\(anime.releasedEpisodeCount) серий вышло", systemImage: "play.rectangle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .padding(19)
        }
    }

    private var descriptionContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !anime.genres.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(anime.genres, id: \.self) { genre in
                            Text(genre)
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(AppPalette.surface(appStore.preferences.theme), in: Capsule())
                        }
                    }
                }
            }

            Text(anime.synopsis.isEmpty ? "Описание для этого тайтла пока не предоставлено каталогом." : anime.synopsis)
                .font(.system(size: 14))
                .lineSpacing(5)
                .foregroundStyle(appStore.preferences.theme == .light ? .black : .white.opacity(0.86))

            libraryStatusMenu

            Button {
                stage = .voices
                voiceOptions = anime.voices
                errorMessage = nil
                Task { await loadVoiceOptions() }
            } label: {
                Label("Смотреть", systemImage: "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(appStore.preferences.accentColor, in: RoundedRectangle(cornerRadius: 15))
                    .foregroundStyle(.white)
            }
        }
    }

    private var libraryStatusMenu: some View {
        Menu {
            ForEach(AnimeLibraryStatus.allCases) { status in
                Button {
                    appStore.setLibraryStatus(status, for: anime)
                } label: {
                    Label(status.rawValue, systemImage: status.symbol)
                }
            }
            if appStore.libraryStatus(for: anime.id) != nil {
                Button("Убрать из библиотеки", role: .destructive) {
                    appStore.setLibraryStatus(nil, for: anime)
                }
            }
        } label: {
            Label(
                appStore.libraryStatus(for: anime.id)?.rawValue ?? "Добавить в библиотеку",
                systemImage: appStore.libraryStatus(for: anime.id)?.symbol ?? "bookmark"
            )
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(appStore.preferences.accentColor)
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.surface(appStore.preferences.theme), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var voicePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Выбери озвучку")
                .font(.system(size: 19, weight: .bold, design: .rounded))

            if isLoadingVoices {
                ProgressView("Ищем доступные озвучки…")
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else if voiceOptions.isEmpty {
                InlineNotice(
                    text: "Для этого тайтла пока нет доступного видеопоставщика и вариантов озвучки.",
                    symbol: "waveform"
                )
            } else {
                ForEach(voiceOptions) { voice in
                    Button {
                        selectedVoice = voice
                        Task { await loadEpisodes(voice) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "waveform")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(appStore.preferences.accentColor)
                                .frame(width: 42, height: 42)
                                .background(appStore.preferences.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(voice.title)
                                    .font(.system(size: 14, weight: .semibold))
                                Text(voice.providerName)
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppPalette.muted(appStore.preferences.theme))
                            }
                            Spacer()
                            Text("\(voice.releasedEpisodeCount) сер.")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppPalette.muted(appStore.preferences.theme))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .padding(12)
                        .background(AppPalette.surface(appStore.preferences.theme), in: RoundedRectangle(cornerRadius: 15))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var episodePicker: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(selectedVoice?.title ?? "Серии")
                .font(.system(size: 19, weight: .bold, design: .rounded))

            if isLoadingEpisodes {
                ProgressView("Загружаем серии…")
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else if episodes.isEmpty {
                InlineNotice(
                    text: "Список серий появится, когда поставщик предоставит его для выбранной озвучки.",
                    symbol: "rectangle.stack"
                )
            } else {
                ForEach(episodes) { episode in
                    episodeRow(episode)
                }
            }

            if let selectedEpisode {
                VStack(alignment: .leading, spacing: 11) {
                    Text("Ссылка на серию \(selectedEpisode.number)")
                        .font(.system(size: 13, weight: .bold))
                    TextField("HTTPS-ссылка от поставщика", text: $streamAddress)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(13)
                        .background(AppPalette.background(appStore.preferences.theme), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("episodeStreamAddressField")
                    Button {
                        Task { await startEpisode(selectedEpisode) }
                    } label: {
                        if isResolvingStream {
                            ProgressView("Подключаем поток…")
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Смотреть серию", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(PrimaryActionStyle(color: appStore.preferences.accentColor))
                    .disabled(isResolvingStream || (selectedVoice == nil && !isValidHTTPSURL(streamAddress)))
                    .accessibilityIdentifier("watchSelectedEpisodeButton")
                }
                .padding(14)
                .background(AppPalette.surface(appStore.preferences.theme), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func episodeRow(_ episode: AnimeEpisode) -> some View {
        let watched = appStore.watchedEpisodesByAnime[anime.id]?.contains(episode.number) ?? false
        let opened = appStore.openedEpisodesByAnime[anime.id]?.contains(episode.number) ?? false
        return Button {
            selectedEpisode = episode
            streamAddress = ""
            appStore.markEpisodeOpened(episode.number, title: anime)
        } label: {
            HStack(spacing: 11) {
                Image(systemName: watched ? "checkmark.circle.fill" : (opened ? "eye.circle.fill" : "play.circle"))
                    .foregroundStyle(watched ? .green : (opened ? appStore.preferences.accentColor.opacity(0.75) : appStore.preferences.accentColor))
                    .font(.system(size: 20))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Серия \(episode.number)")
                        .font(.system(size: 13, weight: .semibold))
                    Text(episode.title)
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.muted(appStore.preferences.theme))
                }
                Spacer()
                if appStore.progressByAnime[anime.id]?.episodeID == episode.id {
                    Text("Продолжить")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(appStore.preferences.accentColor)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppPalette.muted(appStore.preferences.theme))
            }
            .padding(13)
            .background(AppPalette.surface(appStore.preferences.theme), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func loadEpisodes(_ voice: AnimeStreamOption) async {
        stage = .episodes
        isLoadingEpisodes = true
        errorMessage = nil
        defer { isLoadingEpisodes = false }
        do {
            episodes = try await appStore.episodes(for: anime, voice: voice)
        } catch {
            episodes = []
            errorMessage = error.localizedDescription
        }
    }

    private func loadVoiceOptions() async {
        guard voiceOptions.isEmpty else { return }
        isLoadingVoices = true
        errorMessage = nil
        defer { isLoadingVoices = false }
        do {
            voiceOptions = try await appStore.streamOptions(for: anime)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startEpisode(_ episode: AnimeEpisode) async {
        isResolvingStream = true
        defer { isResolvingStream = false }
        do {
            let resolvedStream: ResolvedAnimeStream
            if isValidHTTPSURL(streamAddress), let url = URL(string: streamAddress) {
                resolvedStream = ResolvedAnimeStream(url: url, advertisingPolicy: .unknown)
            } else if let selectedVoice {
                resolvedStream = try await appStore.resolveStream(
                    for: episode,
                    in: anime,
                    voice: selectedVoice
                )
            } else {
                errorMessage = "Вставь HTTPS-ссылку от поставщика или выбери озвучку."
                return
            }
            let acceptedStream = try appStore.validateStream(resolvedStream)
            let resolvedURL = acceptedStream.url
            guard resolvedURL.scheme?.lowercased() == "https", resolvedURL.host != nil else {
                errorMessage = "Источник вернул некорректную ссылку на поток."
                return
            }
            activeStreamURL = resolvedURL
            activeEpisode = episode
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func isValidHTTPSURL(_ value: String) -> Bool {
        guard let components = URLComponents(string: value) else { return false }
        return components.scheme?.lowercased() == "https"
            && !(components.host?.isEmpty ?? true)
    }
}

private enum DetailStage {
    case description
    case voices
    case episodes
}

@MainActor
private struct AnimeLibraryView: View {
    @EnvironmentObject private var appStore: AnimeAppStore
    @State private var selectedStatus: AnimeLibraryStatus = .watching
    @State private var selectedAnime: AnimeTitle?

    private var entries: [AnimeLibraryEntry] {
        appStore.library.filter { $0.status == selectedStatus }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(AnimeLibraryStatus.allCases) { status in
                            Button {
                                selectedStatus = status
                            } label: {
                                Label(status.rawValue, systemImage: status.symbol)
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .foregroundStyle(selectedStatus == status ? .white : AppPalette.muted(appStore.preferences.theme))
                                    .background(
                                        selectedStatus == status
                                            ? appStore.preferences.accentColor
                                            : AppPalette.surface(appStore.preferences.theme),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                if entries.isEmpty {
                    libraryEmptyState
                } else {
                    List {
                        ForEach(entries) { entry in
                            LibraryRow(
                                entry: entry,
                                progress: appStore.progressByAnime[entry.animeID],
                                theme: appStore.preferences.theme,
                                accent: appStore.preferences.accentColor,
                                onSelect: {
                                    selectedAnime = entry.anime ?? AnimeTitle(id: entry.animeID, title: entry.title)
                                },
                                onStatusChange: { status in
                                    let anime = entry.anime ?? AnimeTitle(id: entry.animeID, title: entry.title)
                                    appStore.setLibraryStatus(status, for: anime)
                                }
                            )
                            .listRowBackground(AppPalette.surface(appStore.preferences.theme))
                        }
                        .onDelete(perform: removeEntries)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(AppPalette.background(appStore.preferences.theme))
            .navigationTitle("Библиотека")
            .sheet(item: $selectedAnime) { anime in
                AnimeDetailView(anime: anime)
            }
        }
    }

    private func removeEntries(at offsets: IndexSet) {
        for index in offsets.reversed() {
            let entry = entries[index]
            let anime = entry.anime ?? AnimeTitle(id: entry.animeID, title: entry.title)
            appStore.setLibraryStatus(nil, for: anime)
        }
    }

    private var libraryEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 32))
                .foregroundStyle(appStore.preferences.accentColor)
            Text("Здесь пока пусто")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(appStore.preferences.theme == .light ? Color.black : Color.white)
            Text("Добавляй аниме в библиотеку из карточки тайтла и меняй статус по мере просмотра.")
                .font(.system(size: 13))
                .foregroundStyle(AppPalette.muted(appStore.preferences.theme))
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LibraryRow: View {
    let entry: AnimeLibraryEntry
    let progress: AnimeWatchProgress?
    let theme: AnimeTheme
    let accent: Color
    let onSelect: () -> Void
    let onStatusChange: (AnimeLibraryStatus) -> Void

    var body: some View {
        HStack(spacing: 12) {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 11)
                    .fill(accent.opacity(0.25))
                    .frame(width: 48, height: 60)
                    .overlay {
                        if let posterURL = entry.anime?.posterURL {
                            AsyncImage(url: posterURL) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Image(systemName: "sparkles").foregroundStyle(accent)
                            }
                            .frame(width: 48, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 11))
                        } else {
                            Image(systemName: "sparkles")
                                .foregroundStyle(accent)
                        }
                    }

                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.title)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(2)
                    Text(progress == nil
                        ? "\(entry.watchedEpisodes.count) серий просмотрено"
                        : "\(progress?.episodeTitle ?? "Серия") · \(Int(progress?.seconds ?? 0) / 60) мин")
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.muted(theme))
                    if let progress, progress.duration > 0 {
                        ProgressView(value: progress.seconds, total: progress.duration)
                            .tint(accent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)

        Menu {
                ForEach(AnimeLibraryStatus.allCases) { status in
                    Button(status.rawValue) { onStatusChange(status) }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(AppPalette.muted(theme))
                    .frame(width: 32, height: 42)
                    .contentShape(Rectangle())
            }
        }
        .padding(.vertical, 3)
        .accessibilityIdentifier("libraryEntry-\(entry.animeID)")
    }
}

@MainActor
private struct AnimeSettingsView: View {
    @EnvironmentObject private var appStore: AnimeAppStore
    @State private var permissionMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Уведомления") {
                    Toggle(
                        "Новые серии",
                        isOn: Binding(
                            get: { appStore.preferences.notificationsEnabled },
                            set: { enabled in
                                Task { await setNotifications(enabled) }
                            }
                        )
                    )
                    Text("Сейчас можно разрешить уведомления в iOS. Фактические оповещения появятся после подключения источника обновлений.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Section("Лента") {
                    Picker("Расположение", selection: preferenceBinding(\.gridStyle)) {
                        ForEach(AnimeGridStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                }

                Section("Плеер") {
                    Toggle(
                        "Только источники без рекламы",
                        isOn: preferenceBinding(\.requireAdFreeStreams)
                    )
                    Text("По умолчанию включено: запускаются только потоки, которые сам видеопоставщик помечает как без рекламы. Это заявление поставщика, а не независимая проверка; рекламные вставки внутри видео могут остаться.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Постоянная скорость")
                            Spacer()
                            Text("\(appStore.preferences.defaultPlaybackRate.formatted(.number.precision(.fractionLength(2))))×")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: preferenceBinding(\.defaultPlaybackRate), in: 0.75...3, step: 0.05)
                            .accessibilityIdentifier("defaultPlaybackRateSlider")
                        HStack {
                            Text("0,75×")
                            Spacer()
                            Text("3×")
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    }

                    Picker("Кнопка пропуска опенинга", selection: preferenceBinding(\.introSkipWindow)) {
                        ForEach(IntroSkipWindow.allCases) { window in
                            Text(window.title).tag(window)
                        }
                    }
                    Text("Кнопка вручную перематывает 90 секунд. Она видна только в начале серии и исчезает, если до конца осталось меньше 90 секунд.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Label("Автопереход к следующей серии появится после подключения каталога.", systemImage: "list.number")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Section("Проверка потока") {
                    NavigationLink {
                        ManualStreamEntryView()
                    } label: {
                        Label("Проверить HTTPS-ссылку", systemImage: "play.rectangle")
                    }
                    Text("Это тест только для ссылок от доверенного видеопоставщика. При включённом ограничении ссылка вручную не считается подтверждённой как безрекламная.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Section("Оформление") {
                    Picker("Тема", selection: preferenceBinding(\.theme)) {
                        ForEach(AnimeTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }

                    Picker("Акцентный цвет", selection: preferenceBinding(\.accent)) {
                        ForEach(AccentColorChoice.allCases) { color in
                            HStack {
                                Circle().fill(color.color).frame(width: 10, height: 10)
                                Text(color.rawValue)
                            }
                            .tag(color)
                        }
                    }
                    if appStore.preferences.accent == .custom {
                        ColorPicker(
                            "Настроить цвет",
                            selection: Binding(
                                get: { appStore.preferences.customAccent.color },
                                set: { color in
                                    var red: CGFloat = 0
                                    var green: CGFloat = 0
                                    var blue: CGFloat = 0
                                    UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: nil)
                                    appStore.updatePreferences {
                                        $0.customAccent = AnimeCustomColor(
                                            red: Double(red),
                                            green: Double(green),
                                            blue: Double(blue)
                                        )
                                    }
                                }
                            ),
                            supportsOpacity: false
                        )
                    }
                }

                Section {
                    Label("Глобальный поиск по названию", systemImage: "magnifyingglass")
                    Label("Продолжение с последней позиции", systemImage: "bookmark")
                    Label("Список следующих серий", systemImage: "list.number")
                    Label("Резервная копия библиотеки", systemImage: "icloud")
                } header: {
                    Text("Можно добавить позже")
                } footer: {
                    Text("Поиск, новые серии и озвучки зависят от подключённого официального каталога.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppPalette.background(appStore.preferences.theme))
            .navigationTitle("Настройки")
            .alert("Уведомления", isPresented: Binding(
                get: { permissionMessage != nil },
                set: { if !$0 { permissionMessage = nil } }
            )) {
                Button("Понятно", role: .cancel) { permissionMessage = nil }
            } message: {
                Text(permissionMessage ?? "")
            }
        }
    }

    private func preferenceBinding<Value>(
        _ keyPath: WritableKeyPath<AnimePreferences, Value>
    ) -> Binding<Value> {
        Binding(
            get: { appStore.preferences[keyPath: keyPath] },
            set: { newValue in
                appStore.updatePreferences { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func setNotifications(_ enabled: Bool) async {
        if !enabled {
            appStore.updatePreferences { $0.notificationsEnabled = false }
            return
        }

        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            appStore.updatePreferences { $0.notificationsEnabled = granted }
            if !granted {
                permissionMessage = "Разреши уведомления для приложения в настройках iOS."
            }
        } catch {
            appStore.updatePreferences { $0.notificationsEnabled = false }
            permissionMessage = "Не удалось запросить разрешение: \(error.localizedDescription)"
        }
    }
}

@MainActor
private struct ManualStreamEntryView: View {
    @EnvironmentObject private var appStore: AnimeAppStore
    @State private var address = ""
    @State private var errorMessage: String?
    @State private var playerLaunch: ManualPlayerLaunch?

    var body: some View {
        Form {
            Section("Ссылка на поток") {
                TextField("HTTPS-ссылка от видеопоставщика", text: $address)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("manualStreamAddressField")

                Button("Воспроизвести") {
                    openStream()
                }
                .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("manualStreamPlayButton")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Text("Включённое ограничение «Только источники без рекламы» блокирует эту ссылку, поскольку вручную введённый поток не подтверждён поставщиком. Отключи ограничение только если доверяешь источнику. Используй ссылки, разрешённые поставщиком для стороннего плеера.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Проверка плеера")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $playerLaunch) { launch in
            let anime = AnimeTitle(id: "manual-\(launch.id)", title: "Внешний поток")
            let episode = AnimeEpisode(id: "manual-episode", title: "Поток", number: 1)
            StreamPlayerScreen(anime: anime, episode: episode, streamURL: launch.url)
        }
    }

    private func openStream() {
        let cleanedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let components = URLComponents(string: cleanedAddress),
            components.scheme?.lowercased() == "https",
            let host = components.host,
            !host.isEmpty,
            let url = components.url
        else {
            errorMessage = "Введи корректную HTTPS-ссылку от поставщика."
            return
        }

        errorMessage = nil
        let digest = SHA256.hash(data: Data(cleanedAddress.utf8))
        let stableID = digest.map { String(format: "%02x", $0) }.joined()
        do {
            try appStore.validateStream(
                ResolvedAnimeStream(url: url, advertisingPolicy: .unknown)
            )
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        playerLaunch = ManualPlayerLaunch(id: stableID, url: url)
    }
}

private struct ManualPlayerLaunch: Identifiable {
    let id: String
    let url: URL
}

private struct InlineNotice: View {
    @EnvironmentObject private var appStore: AnimeAppStore
    let text: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(appStore.preferences.accentColor)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(AppPalette.muted(appStore.preferences.theme))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(AppPalette.surface(appStore.preferences.theme), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct PrimaryActionStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .frame(height: 44)
            .background(color.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SecondaryActionStyle: ButtonStyle {
    @EnvironmentObject private var appStore: AnimeAppStore

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(appStore.preferences.accentColor)
            .padding(.horizontal, 11)
            .frame(height: 44)
            .background(appStore.preferences.accentColor.opacity(configuration.isPressed ? 0.18 : 0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}
