import Combine
import Foundation
import SwiftUI

enum AnimeLibraryStatus: String, CaseIterable, Codable, Identifiable {
    case watching = "Смотрю"
    case completed = "Просмотрено"
    case planned = "Планирую"
    case dropped = "Брошено"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .watching: return "play.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .planned: return "bookmark.fill"
        case .dropped: return "xmark.circle.fill"
        }
    }
}

enum AnimeGridStyle: String, CaseIterable, Codable, Identifiable {
    case twoColumns = "2 × 2"
    case threeColumns = "3 × 2"
    case list = "Список"

    var id: String { rawValue }

    var columnCount: Int {
        switch self {
        case .twoColumns: return 2
        case .threeColumns: return 3
        case .list: return 1
        }
    }
}

enum AnimeTheme: String, CaseIterable, Codable, Identifiable {
    case midnight = "Ночь"
    case amoled = "AMOLED"
    case light = "Светлая"

    var id: String { rawValue }
}

enum AccentColorChoice: String, CaseIterable, Codable, Identifiable {
    case violet = "Фиолетовый"
    case blue = "Синий"
    case pink = "Розовый"
    case emerald = "Изумрудный"
    case orange = "Оранжевый"
    case custom = "Свой цвет"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .violet: return Color(red: 0.48, green: 0.39, blue: 1)
        case .blue: return Color(red: 0.18, green: 0.48, blue: 0.98)
        case .pink: return Color(red: 0.92, green: 0.28, blue: 0.58)
        case .emerald: return Color(red: 0.12, green: 0.68, blue: 0.48)
        case .orange: return Color(red: 0.95, green: 0.46, blue: 0.2)
        case .custom: return Color(red: 0.48, green: 0.39, blue: 1)
        }
    }
}

struct AnimeCustomColor: Codable {
    var red = 0.48
    var green = 0.39
    var blue = 1.0

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }
}

enum IntroSkipWindow: Int, CaseIterable, Identifiable {
    case off = 0
    case threeMinutes = 180
    case fiveMinutes = 300

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .off: return "Выключено"
        case .threeMinutes: return "3 минуты"
        case .fiveMinutes: return "5 минут"
        }
    }
}

struct AnimePreferences: Codable {
    var notificationsEnabled = false
    var gridStyle: AnimeGridStyle = .twoColumns
    var defaultPlaybackRate: Double = 1
    var theme: AnimeTheme = .midnight
    var accent: AccentColorChoice = .violet
    var customAccent = AnimeCustomColor()
    var introSkipWindow = 180
    var requireAdFreeStreams = true

    private enum CodingKeys: String, CodingKey {
        case notificationsEnabled
        case gridStyle
        case defaultPlaybackRate
        case theme
        case accent
        case customAccent
        case introSkipWindow
        case requireAdFreeStreams
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        notificationsEnabled = try values.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? false
        gridStyle = try values.decodeIfPresent(AnimeGridStyle.self, forKey: .gridStyle) ?? .twoColumns
        defaultPlaybackRate = try values.decodeIfPresent(Double.self, forKey: .defaultPlaybackRate) ?? 1
        theme = try values.decodeIfPresent(AnimeTheme.self, forKey: .theme) ?? .midnight
        accent = try values.decodeIfPresent(AccentColorChoice.self, forKey: .accent) ?? .violet
        customAccent = try values.decodeIfPresent(AnimeCustomColor.self, forKey: .customAccent)
            ?? AnimeCustomColor()
        introSkipWindow = try values.decodeIfPresent(Int.self, forKey: .introSkipWindow) ?? 180
        requireAdFreeStreams = try values.decodeIfPresent(Bool.self, forKey: .requireAdFreeStreams) ?? true
    }

    var skipWindow: IntroSkipWindow {
        get { IntroSkipWindow(rawValue: introSkipWindow) ?? .off }
        set { introSkipWindow = newValue.rawValue }
    }

    var accentColor: Color {
        accent == .custom ? customAccent.color : accent.color
    }
}

struct AnimeLibraryEntry: Codable, Identifiable {
    var id: String { animeID }
    let animeID: String
    let title: String
    var status: AnimeLibraryStatus
    var anime: AnimeTitle?
    var openedEpisodes: Set<Int> = []
    var watchedEpisodes: Set<Int> = []
}

struct AnimeWatchProgress: Codable {
    let animeID: String
    let episodeID: String
    let episodeTitle: String
    var seconds: Double
    var duration: Double
    var updatedAt: Date
}

@MainActor
final class AnimeAppStore: ObservableObject {
    @Published private(set) var airingTitles: [AnimeTitle] = []
    @Published private(set) var isLoadingCatalog = false
    @Published private(set) var catalogError: String?
    @Published private(set) var library: [AnimeLibraryEntry] = []
    @Published private(set) var progressByAnime: [String: AnimeWatchProgress] = [:]
    @Published private(set) var openedEpisodesByAnime: [String: Set<Int>] = [:]
    @Published private(set) var watchedEpisodesByAnime: [String: Set<Int>] = [:]
    @Published var preferences: AnimePreferences {
        didSet { save(preferences, forKey: Keys.preferences) }
    }

    private let catalogProvider: any AnimeCatalogProvider
    private let streamProvider: (any AnimeStreamProvider)?
    private let defaults: UserDefaults
    private var searchTask: Task<Void, Never>?

    init(
        catalogProvider: any AnimeCatalogProvider = AniListCatalogProvider(),
        streamProvider: (any AnimeStreamProvider)? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.catalogProvider = catalogProvider
        self.streamProvider = streamProvider
        self.defaults = defaults
        preferences = Self.load(AnimePreferences.self, key: Keys.preferences, from: defaults)
            ?? AnimePreferences()
        library = Self.load([AnimeLibraryEntry].self, key: Keys.library, from: defaults) ?? []
        progressByAnime = Self.load([String: AnimeWatchProgress].self, key: Keys.progress, from: defaults) ?? [:]
        openedEpisodesByAnime = Self.load([String: Set<Int>].self, key: Keys.openedEpisodes, from: defaults)
            ?? library.reduce(into: [:]) { $0[$1.animeID] = $1.openedEpisodes }
        watchedEpisodesByAnime = Self.load([String: Set<Int>].self, key: Keys.watchedEpisodes, from: defaults)
            ?? library.reduce(into: [:]) { $0[$1.animeID] = $1.watchedEpisodes }
    }

    func loadAiringTitles() async {
        isLoadingCatalog = true
        catalogError = nil
        defer { isLoadingCatalog = false }

        do {
            airingTitles = try await catalogProvider.airingTitles()
        } catch {
            catalogError = "Не удалось обновить ленту: \(error.localizedDescription)"
        }
    }

    func search(query: String) {
        searchTask?.cancel()
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedQuery.isEmpty else {
            searchTask = Task { await loadAiringTitles() }
            return
        }

        searchTask = Task {
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            isLoadingCatalog = true
            catalogError = nil
            defer { isLoadingCatalog = false }

            do {
                let results = try await catalogProvider.searchTitles(query: normalizedQuery)
                guard !Task.isCancelled else { return }
                airingTitles = results
            } catch {
                guard !Task.isCancelled else { return }
                catalogError = "Поиск не выполнен: \(error.localizedDescription)"
            }
        }
    }

    func refreshCatalog() async {
        await loadAiringTitles()
    }

    func episodes(for title: AnimeTitle, voice: AnimeStreamOption) async throws -> [AnimeEpisode] {
        guard let streamProvider else {
            throw CatalogUnavailableError.noLicensedVideoSource
        }
        return try await streamProvider.episodes(for: title, voice: voice)
    }

    func streamOptions(for title: AnimeTitle) async throws -> [AnimeStreamOption] {
        guard let streamProvider else {
            throw CatalogUnavailableError.noLicensedVideoSource
        }
        return try await streamProvider.streamOptions(for: title)
    }

    func resolveStream(
        for episode: AnimeEpisode,
        in title: AnimeTitle,
        voice: AnimeStreamOption
    ) async throws -> ResolvedAnimeStream {
        guard let streamProvider else {
            throw CatalogUnavailableError.noLicensedVideoSource
        }
        let stream = try await streamProvider.resolveStream(for: episode, in: title, voice: voice)
        return try validateStream(stream)
    }

    func validateStream(_ stream: ResolvedAnimeStream) throws -> ResolvedAnimeStream {
        guard preferences.requireAdFreeStreams else { return stream }
        guard stream.advertisingPolicy == .providerConfirmedAdFree else {
            throw StreamAdvertisingError(policy: stream.advertisingPolicy)
        }
        return stream
    }

    func libraryStatus(for animeID: String) -> AnimeLibraryStatus? {
        library.first(where: { $0.animeID == animeID })?.status
    }

    func setLibraryStatus(_ status: AnimeLibraryStatus?, for title: AnimeTitle) {
        if let index = library.firstIndex(where: { $0.animeID == title.id }) {
            if let status {
                library[index].status = status
                library[index].anime = title
            } else {
                library.remove(at: index)
            }
        } else if let status {
            library.append(AnimeLibraryEntry(
                animeID: title.id,
                title: title.title,
                status: status,
                anime: title,
                openedEpisodes: openedEpisodesByAnime[title.id] ?? [],
                watchedEpisodes: watchedEpisodesByAnime[title.id] ?? []
            ))
        }
        save(library, forKey: Keys.library)
    }

    func markEpisodeWatched(_ episodeNumber: Int, title: AnimeTitle) {
        watchedEpisodesByAnime[title.id, default: []].insert(episodeNumber)
        save(watchedEpisodesByAnime, forKey: Keys.watchedEpisodes)
        if let index = library.firstIndex(where: { $0.animeID == title.id }) {
            library[index].watchedEpisodes.insert(episodeNumber)
            save(library, forKey: Keys.library)
        }
    }

    func markEpisodeOpened(_ episodeNumber: Int, title: AnimeTitle) {
        openedEpisodesByAnime[title.id, default: []].insert(episodeNumber)
        save(openedEpisodesByAnime, forKey: Keys.openedEpisodes)
        if let index = library.firstIndex(where: { $0.animeID == title.id }) {
            library[index].openedEpisodes.insert(episodeNumber)
            save(library, forKey: Keys.library)
        }
    }

    func saveProgress(
        anime: AnimeTitle,
        episode: AnimeEpisode,
        seconds: Double,
        duration: Double
    ) {
        guard seconds.isFinite, duration.isFinite else { return }
        progressByAnime[anime.id] = AnimeWatchProgress(
            animeID: anime.id,
            episodeID: episode.id,
            episodeTitle: episode.title,
            seconds: max(0, seconds),
            duration: max(0, duration),
            updatedAt: Date()
        )
        save(progressByAnime, forKey: Keys.progress)
    }

    func clearProgress(for animeID: String) {
        progressByAnime.removeValue(forKey: animeID)
        save(progressByAnime, forKey: Keys.progress)
    }

    func updatePreferences(_ update: (inout AnimePreferences) -> Void) {
        update(&preferences)
    }

    private func save<T: Encodable>(_ value: T, forKey key: String) {
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: key)
        } catch {
            catalogError = "Не удалось сохранить настройки и прогресс: \(error.localizedDescription)"
        }
    }

    private static func load<T: Decodable>(
        _ type: T.Type,
        key: String,
        from defaults: UserDefaults
    ) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            return nil
        }
    }

    private enum Keys {
        static let preferences = "anime.preferences"
        static let library = "anime.library"
        static let progress = "anime.progress"
        static let openedEpisodes = "anime.openedEpisodes"
        static let watchedEpisodes = "anime.watchedEpisodes"
    }
}

enum CatalogUnavailableError: LocalizedError {
    case noLicensedVideoSource

    var errorDescription: String? {
        "Каталог показывает расписание и описания, но не предоставляет видеопотоки или озвучки. Для просмотра подключите официальный видеосервис."
    }
}

struct StreamAdvertisingError: LocalizedError {
    let policy: StreamAdvertisingPolicy

    var errorDescription: String? {
        switch policy {
        case .providerConfirmedAdFree:
            return nil
        case .advertisingPresent:
            return "Этот источник сообщает о рекламных вставках. Выключи ограничение «Только источники без рекламы» в настройках, если хочешь продолжить."
        case .unknown:
            return "Источник не подтверждает отсутствие рекламы, поэтому поток не запущен. Выключи ограничение «Только источники без рекламы» в настройках, если доверяешь этой ссылке."
        }
    }
}
