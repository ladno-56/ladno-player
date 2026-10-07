import Foundation

struct AnimeTitle: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    var originalTitle: String = ""
    var synopsis: String = ""
    var genres: [String] = []
    var posterURL: URL?
    var isAiring: Bool = true
    var releasedEpisodeCount: Int = 0
    var voices: [AnimeStreamOption] = []
}

struct AnimeEpisode: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let number: Int
}

struct AnimeStreamOption: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let providerName: String
    var releasedEpisodeCount: Int = 0
}

struct ResolvedAnimeStream {
    let url: URL
    let advertisingPolicy: StreamAdvertisingPolicy
}

enum StreamAdvertisingPolicy: Equatable {
    // The provider explicitly identifies this stream as free of inserted ads.
    case providerConfirmedAdFree
    case advertisingPresent
    case unknown
}

protocol AnimeCatalogProvider {
    func airingTitles() async throws -> [AnimeTitle]
    func searchTitles(query: String) async throws -> [AnimeTitle]
}

protocol AnimeStreamProvider {
    func streamOptions(for title: AnimeTitle) async throws -> [AnimeStreamOption]
    func episodes(for title: AnimeTitle, voice: AnimeStreamOption) async throws -> [AnimeEpisode]
    func resolveStream(
        for episode: AnimeEpisode,
        in title: AnimeTitle,
        voice: AnimeStreamOption
    ) async throws -> ResolvedAnimeStream
}
