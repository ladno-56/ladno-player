import Foundation

struct AniListCatalogProvider: AnimeCatalogProvider {
    private let endpoint = URL(string: "https://graphql.anilist.co")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func airingTitles() async throws -> [AnimeTitle] {
        let query = """
        query {
          Page(page: 1, perPage: 50) {
            media(type: ANIME, status: RELEASING, sort: POPULARITY_DESC) {
              id
              title { romaji english }
              description(asHtml: false)
              genres
              episodes
              status
              coverImage { large }
              nextAiringEpisode { episode airingAt }
            }
          }
        }
        """
        return try await fetch(query: query).map(makeAnime)
    }

    func searchTitles(query: String) async throws -> [AnimeTitle] {
        let queryText = """
        query ($search: String) {
          Page(page: 1, perPage: 50) {
            media(search: $search, type: ANIME, sort: SEARCH_MATCH) {
              id
              title { romaji english }
              description(asHtml: false)
              genres
              episodes
              status
              coverImage { large }
              nextAiringEpisode { episode airingAt }
            }
          }
        }
        """
        return try await fetch(query: queryText, variables: ["search": query]).map(makeAnime)
    }

    private func fetch(query: String, variables: [String: String] = [:]) async throws -> [AniListMedia] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("KiraAnimePlayer/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(GraphQLRequest(query: query, variables: variables))

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw AniListCatalogError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw AniListCatalogError.httpStatus(response.statusCode)
        }

        let result = try JSONDecoder().decode(AniListResponse.self, from: data)
        if let error = result.errors?.first {
            throw AniListCatalogError.graphQL(error.message)
        }
        guard let media = result.data?.page.media else {
            throw AniListCatalogError.missingCatalog
        }
        return media
    }

    private func makeAnime(_ media: AniListMedia) -> AnimeTitle {
        let title = media.title.english ?? media.title.romaji ?? "Аниме без названия"
        let releasedEpisodeCount: Int
        if let nextEpisode = media.nextAiringEpisode?.episode {
            releasedEpisodeCount = max(0, nextEpisode - 1)
        } else if media.status == "FINISHED" {
            releasedEpisodeCount = media.episodes ?? 0
        } else {
            releasedEpisodeCount = 0
        }

        return AnimeTitle(
            id: String(media.id),
            title: title,
            originalTitle: media.title.romaji ?? title,
            synopsis: media.description ?? "",
            genres: media.genres ?? [],
            posterURL: media.coverImage?.large.flatMap { URL(string: $0) },
            isAiring: media.status == "RELEASING",
            releasedEpisodeCount: releasedEpisodeCount
        )
    }
}

private struct GraphQLRequest: Encodable {
    let query: String
    let variables: [String: String]
}

private struct AniListResponse: Decodable {
    let data: AniListData?
    let errors: [AniListGraphQLError]?
}

private struct AniListData: Decodable {
    let page: AniListPage

    enum CodingKeys: String, CodingKey {
        case page = "Page"
    }
}

private struct AniListPage: Decodable {
    let media: [AniListMedia]
}

private struct AniListMedia: Decodable {
    let id: Int
    let title: AniListTitle
    let description: String?
    let genres: [String]?
    let episodes: Int?
    let status: String?
    let coverImage: AniListCoverImage?
    let nextAiringEpisode: AniListNextEpisode?
}

private struct AniListTitle: Decodable {
    let romaji: String?
    let english: String?
}

private struct AniListCoverImage: Decodable {
    let large: String?
}

private struct AniListNextEpisode: Decodable {
    let episode: Int
    let airingAt: Int
}

private struct AniListGraphQLError: Decodable {
    let message: String
}

private enum AniListCatalogError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case graphQL(String)
    case missingCatalog

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Каталог вернул некорректный ответ."
        case .httpStatus(let status):
            return "Каталог временно недоступен (HTTP \(status))."
        case .graphQL(let message):
            return "Ошибка запроса каталога: \(message)"
        case .missingCatalog:
            return "Каталог не вернул список аниме."
        }
    }
}
