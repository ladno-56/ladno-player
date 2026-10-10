import Foundation
import SwiftUI

// MARK: - KODIK API Client (kodik-api.com)
private struct KodikApiClient {
    private let baseUrl = "https://kodik-api.com"
    private let session: URLSession
    
    init(session: URLSession = .shared) { self.session = session }
    
    func searchAnime(query: String, token: String) async throws -> [KodikSearchResult] {
        let encodedTitle = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        var request = URLRequest(url: URL(string: "\(baseUrl)/search?token=\(token)&title=\(encodedTitle)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else { throw AnimeKodikStreamProviderError.unavailable }
        return try parseSearchResponse(data)
    }
    
    func listAnime(token: String, page: Int = 1) async throws -> [KodikItem] {
        var request = URLRequest(url: URL(string: "\(baseUrl)/list?token=\(token)&page=\(page)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else { throw AnimeKodikStreamProviderError.unavailable }
        return try parseListResponse(data)
    }
    
    func getTranslations(token: String) async throws -> [Translation] {
        var request = URLRequest(url: URL(string: "\(baseUrl)/translations?token=\(token)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else { throw AnimeKodikStreamProviderError.unavailable }
        return try parseTranslations(data)
    }
    
    private func parseSearchResponse(_ data: Data) throws -> [KodikSearchResult] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { throw AnimeKodikStreamProviderError.unavailable }
        return results.map { item -> KodikSearchResult in
            KodikSearchResult(
                id: (item["id"] as? String) ?? "", type: (item["type"] as? String) ?? "anime", title: (item["title"] as? String) ?? "",
                originalTitle: (item["title_orig"] as? String), translationId: ((item["translation"] as? [String: Any])?["id"]) as? Int),
                link: (item["link"] as? String), year: (item["year"] as? Int), shikimoriId: (item["shikimori_id"] as? String), imdbId: (item["imdb_id"] as? String)
            )
        }
    }
    
    private func parseListResponse(_ data: Data) throws -> [KodikItem] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { throw AnimeKodikStreamProviderError.unavailable }
        return results.map(parseListItem)
    }
    
    private func parseListItem(_ item: [String: Any]) -> KodikItem {
        let translation = (item["translation"] as? [String: Any]) ?? [:]
        return KodikItem(id: (item["id"] as? String) ?? "", type: (item["type"] as? String) ?? "anime", title: (item["title"] as? String) ?? "",
            originalTitle: (item["title_orig"] as? String), otherTitle: (item["other_title"] as? String), link: (item["link"] as? String),
            translationId: (translation["id"] as? Int), translationName: (translation["title"] as? String), year: (item["year"] as? Int))
    }
    
    private func parseTranslations(_ data: Data) throws -> [Translation] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return json.map { item in Translation(id: (item["id"] as? Int) ?? 0, title: (item["title"] as? String) ?? "", type: (item["type"] as? String) ?? "voice") }
    }
}

private struct KodikSearchResult { let id: String; let type: String; let title: String; let originalTitle: String?; let translationId: Int?; let link: String?; let year: Int?; let shikimoriId: String?; let imdbId: String? }
private struct KodikItem { let id: String; let type: String; let title: String; let originalTitle: String?; let otherTitle: String?; let link: String?; let translationId: Int?; let translationName: String?; let year: Int? }
private struct Translation { let id: Int; let title: String; let type: String; var providerName: String { switch type { case "voice": return "Голосовой перевод \(title)"; case "subtitles": return "Субтитры \(title)"; default: return title } } }

struct AnimeKodikStreamProvider: AnimeStreamProvider {
    private let client = KodikApiClient()
    private var token: String?
    
    init(token: String? = nil) { self.token = token }
    
    func streamOptions(for title: AnimeTitle) async throws -> [AnimeStreamOption] {
        guard let apiToken = try await resolveToken() else { throw AnimeKodikStreamProviderError.unavailable }
        do { let items = try await client.listAnime(token: apiToken); return items.map { item in AnimeStreamOption(id: item.id, title: item.title, providerName: item.translationName ?? "Kodik", releasedEpisodeCount: nil) } } catch { throw AnimeKodikStreamProviderError.unavailable }
    }
    
    func episodes(for title: AnimeTitle, voice: AnimeStreamOption) async throws -> [AnimeEpisode] {
        guard let apiToken = try await resolveToken() else { throw AnimeKodikStreamProviderError.unavailable }
        do {
            // KODIK API: material_data содержит seasons с эпизодами
            var request = URLRequest(url: URL(string: "\(baseUrl)/search?token=\(apiToken)&shikimori_id=\(title.id)")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            let (data, response) = try await client.session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else { throw AnimeKodikStreamProviderError.unavailable }
            return parseEpisodesFromMaterial(data)
        } catch {
            if error is AnimeKodikStreamProviderError { throw error }
            throw AnimeKodikStreamProviderError.unavailable
        }
    }
    
    private func parseEpisodesFromMaterial(_ data: Data) -> [AnimeEpisode] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        
        var episodes: [AnimeEpisode] = []
        for result in results {
            // Материал данных может содержать seasons с эпизодами
            if let matData = result["material_data"] as? [String: Any],
               let seasonsDict = matData["seasons"] as? [String: Any] {
                
                for (seasonKey, seasonVal) in seasonsDict {
                    // Проверяем два варианта структуры:
                    // 1) seasonVal напрямую содержит episodes
                    // 2) material_data.episodes внутри
                    var epArray: [[String: Any]] = []
                    if let seasonObj = seasonVal as? [String: Any],
                       let directEpisodes = seasonObj["episodes"] as? [[String: Any]] {
                        epArray = directEpisodes
                    } else if let matData = seasonVal as? [String: Any],
                              let innerMat = matData["material_data"] as? [String: Any],
                              let nestedEpisodes = innerMat["episodes"] as? [[String: Any]] {
                        epArray = nestedEpisodes
                    }
                    
                    for ep in epArray {
                        if let id = (ep["id"] as? String) ?? (ep["cvh_id"] as? String),
                           let title = (ep["name"] as? String),
                           let number = (ep["episode"] as? Int) ?? 1 {
                            episodes.append(AnimeEpisode(id: id, title: "Серия \(number): \(title)", number: number))
                        }
                    }
                }
            }
        }
        return episodes
    }
    
    func resolveStream(for episode: AnimeEpisode, in title: AnimeTitle, voice: AnimeStreamOption) async throws -> ResolvedAnimeStream {
        guard let apiToken = try await resolveToken() else { throw AnimeKodikStreamProviderError.unavailable }
        do { let streamURL = try await getStreamUrl(token: apiToken, titleId: title.id, episodeId: episode.id); return ResolvedAnimeStream(url: streamURL, advertisingPolicy: .providerConfirmedAdFree) } catch error { if error is AnimeKodikStreamProviderError { throw error }; throw AnimeKodikStreamProviderError.unavailable }
    }
    
    private func resolveToken() async throws -> String? {
        guard let existing = token else { return nil }; if isValidToken(existing) { return existing }; let defaults = UserDefaults.standard; guard let stored = defaults.string(forKey: "kodik.token") else { return nil }; token = stored; return stored
    }
    
    private func isValidToken(_ token: String) -> Bool { let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines); guard trimmed.count > 10 else { return false }; return true }
    
    private func getStreamUrl(token: String, titleId: String, episodeId: String) async throws -> URL {
        var request = URLRequest(url: URL(string: "https://kodik-api.com/stream?token=\(token)&title_id=\(titleId)&episode_id=\(episodeId)")!)
        request.httpMethod = "POST"; request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else { throw AnimeKodikStreamProviderError.unavailable }
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let urlStr = json["url"] as? String ?? json["link"] as? String, let streamUrl = URL(string: urlStr) { return streamUrl }
        throw AnimeKodikStreamProviderError.unavailable
    }
}

struct AnimeKodikCatalogProvider: AnimeCatalogProvider {
    private let client = KodikApiClient()
    
    func airingTitles() async throws -> [AnimeTitle] {
        guard let token = try? await loadToken() else { return [] }
        do {
            let results = try await client.listAnime(token: token)
            return results.map { item in AnimeTitle(id: item.id, title: item.title, originalTitle: item.originalTitle ?? "", synopsis: "", genres: [], posterURL: nil, isAiring: true, releasedEpisodeCount: nil, voices: []) }
        } catch {
            return []
        }
    }

    func searchTitles(query: String) async throws -> [AnimeTitle] {
        guard let token = try? await loadToken() else { return [] }
        do {
            let results = try await client.searchAnime(query: query, token: token)
            return results.map { result in AnimeTitle(id: result.id, title: result.title, originalTitle: result.originalTitle ?? "", synopsis: "", genres: [], posterURL: nil, isAiring: true, releasedEpisodeCount: nil, voices: []) }
        } catch {
            return []
        }
    }

    private func loadToken() async throws -> String? {
        let defaults = UserDefaults.standard
        guard let token = defaults.string(forKey: "kodik.token") else {
            let parserToken = await getKodikParserToken()
            if let pt = parserToken { defaults.set(pt, forKey: "kodik.token"); return pt }
            return nil
        }
    }

    private func getKodikParserToken() async -> String? {
        do {
            let url = URL(string: "https://raw.githubusercontent.com/YaNesyTortiK/AnimeParsers/main/kdk_tokns/tokens.json")!
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let stableArray = json["stable"] as? [[String: Any]] {
                for item in stableArray where (item["functions_availability"] as? [String: Bool]) != nil {
                    if let tokn = item["tokn"] as? String, isValidToken(tokn) { return tokn }
                }
            }
        } catch { print("KODIK: Failed to load token from TOKENS.md"); }
        return nil
    }
}

func decryptToken(tkn: String) -> String? { guard let p1 = Data(base64Encoded: String(tkn[..<tkn.count / 2].reversed())), let decoded1 = try? JSONDecoder().decode(String.self, from: p1), let p2 = Data(base64Encoded: String(tkn[tkn.count / 2...].reversed())), let decoded2 = try? JSONDecoder().decode(String.self, from: p2) else { return nil }; return "\(decoded2)\(decoded1)" }

enum AnimeKodikStreamProviderError: LocalizedError { case unavailable; var errorDescription: String? { "Проигрывание Kodik не настроено." } }
