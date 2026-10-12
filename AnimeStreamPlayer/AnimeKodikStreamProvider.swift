import Foundation
import SwiftUI

private struct KodikApiClient {
    let baseUrl = "https://kodik-api.com"
    
    func listAnime(token: String) async throws -> [KodikItem] {
        var request = URLRequest(url: URL(string: "\(baseUrl)/list?token=\(token)")!)
        request.httpMethod = "POST"; request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else { throw AnimeKodikStreamProviderError.unavailable }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let items = json["results"] as? [[String: Any]] else { return [] }
        return items.map { item -> KodikItem in KodikItem(id: (item["id"] as? String) ?? "", type: (item["type"] as? String) ?? "anime", title: (item["title"] as? String) ?? "", originalTitle: (item["title_orig"] as? String)) }
    }
    
    func searchAnime(query: String, token: String) async throws -> [KodikItem] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        var request = URLRequest(url: URL(string: "\(baseUrl)/search?token=\(token)&title=\(encodedQuery)")!)
        request.httpMethod = "POST"; request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else { throw AnimeKodikStreamProviderError.unavailable }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let items = json["results"] as? [[String: Any]] else { return [] }
        return items.map { item -> KodikItem in KodikItem(id: (item["id"] as? String) ?? "", type: (item["type"] as? String) ?? "anime", title: (item["title"] as? String) ?? "", originalTitle: (item["title_orig"] as? String)) }
    }
}

private struct KodikSearchResult { let id: String; let type: String; let title: String; let originalTitle: String?; let translationId: Int? }
private struct KodikItem { let id: String; let type: String; let title: String; let originalTitle: String? }

struct AnimeKodikStreamProvider: AnimeStreamProvider {
    private let client = KodikApiClient()
    private var token: String?
    
    init(token: String? = nil) { self.token = token }
    
    func streamOptions(for title: AnimeTitle) async throws -> [AnimeStreamOption] {
        var copySelf = self; guard let apiToken = try await copySelf.resolveToken() else { throw AnimeKodikStreamProviderError.unavailable }
        do { let items = try await client.listAnime(token: apiToken); return items.map { item in AnimeStreamOption(id: item.id, title: item.title, providerName: "Kodik", releasedEpisodeCount: (nil as Int?) ?? 0) } } catch { throw AnimeKodikStreamProviderError.unavailable }
    }
    
    func episodes(for title: AnimeTitle, voice: AnimeStreamOption) async throws -> [AnimeEpisode] {
        var copySelf = self; guard let apiToken = try await copySelf.resolveToken() else { throw AnimeKodikStreamProviderError.unavailable }
        do {
            var request = URLRequest(url: URL(string: "\(client.baseUrl)/search?token=\(apiToken)&shikimori_id=\(title.id)")!)
            request.httpMethod = "POST"; request.timeoutInterval = 30
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else { throw AnimeKodikStreamProviderError.unavailable }
            return parseEpisodesFromMaterial(data)
        } catch { throw AnimeKodikStreamProviderError.unavailable }
    }
    
    private func parseEpisodesFromMaterial(_ data: Data) -> [AnimeEpisode] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        
        var episodes: [AnimeEpisode] = []
        for result in results {
            if let matData = result["material_data"] as? [String: Any],
               let seasonsDict = matData["seasons"] as? [String: Any] {
                for seasonVal in seasonsDict.values {
                    var epArray: [[String: Any]] = []
                    if let seasonObj = seasonVal as? [String: Any],
                       let directEpisodes = seasonObj["episodes"] as? [[String: Any]] {
                        epArray = directEpisodes
                    } else if let matData2 = seasonVal as? [String: Any],
                              let innerMat = matData2["material_data"] as? [String: Any],
                              let nestedEpisodes = innerMat["episodes"] as? [[String: Any]] {
                        epArray = nestedEpisodes
                    }
                    for ep in epArray {
                        if let id = (ep["id"] as? String) ?? (ep["cvh_id"] as? String),
                           let titleStr = (ep["name"] as? String),
                           (ep["episode"] as? Int) != nil {
                            episodes.append(AnimeEpisode(id: id, title: "Серия 1: \(titleStr)", number: 1))
                        } else if let id = (ep["id"] as? String) ?? (ep["cvh_id"] as? String),
                                  let titleStr = (ep["name"] as? String) {
                            episodes.append(AnimeEpisode(id: id, title: "Серия 1: \(titleStr)", number: 1))
                        }
                    }
                }
            }
        }
        return episodes
    }
    
    func resolveStream(for episode: AnimeEpisode, in title: AnimeTitle, voice: AnimeStreamOption) async throws -> ResolvedAnimeStream {
        var copySelf = self; guard let apiToken = try await copySelf.resolveToken() else { throw AnimeKodikStreamProviderError.unavailable }
        do { let streamURL = try await getStreamUrl(token: apiToken, titleId: title.id, episodeId: episode.id); return ResolvedAnimeStream(url: streamURL, advertisingPolicy: .providerConfirmedAdFree) } catch { throw AnimeKodikStreamProviderError.unavailable }
    }
    
    private mutating func resolveToken() async throws -> String? {
        guard let existing = token else { return nil }; if isValidTokn(existing) { return existing }; let defaults = UserDefaults.standard; guard let stored = defaults.string(forKey: "kodik.token") else { return nil }; self.token = stored; return stored
    }
    
    private func isValidTokn(_ tokn: String) -> Bool { let trimmed = tokn.trimmingCharacters(in: .whitespacesAndNewlines); guard trimmed.count > 10 else { return false }; return true }
    
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
        do { let results = try await client.listAnime(token: token); return results.map { item in AnimeTitle(id: item.id, title: item.title, originalTitle: item.originalTitle ?? "", synopsis: "", genres: [], posterURL: nil, isAiring: true, releasedEpisodeCount: (nil as Int?) ?? 0, voices: []) } } catch { throw AnimeKodikStreamProviderError.unavailable }
    }

    func searchTitles(query: String) async throws -> [AnimeTitle] {
        guard let token = try? await loadToken() else { return [] }
        do { let results = try await client.searchAnime(query: query, token: token); return results.map { result in AnimeTitle(id: result.id, title: result.title, originalTitle: result.originalTitle ?? "", synopsis: "", genres: [], posterURL: nil, isAiring: true, releasedEpisodeCount: (nil as Int?) ?? 0, voices: []) } } catch { throw AnimeKodikStreamProviderError.unavailable }
    }

    private func loadToken() async throws -> String? {
        let defaults = UserDefaults.standard
        guard let _ = defaults.string(forKey: "kodik.token") else {
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
                for item in stableArray _where (item["functions_availability"] as? [String: Bool]) != nil {
                    if let tokn = item["tokn"] as? String where isValidTokn(tokn) != nil {
                        return tokn
                    }
                    guard case .some(let t) = item["tokn"] as? String else { continue }
                };
            } catch { print("KODIK: Failed to load token from TOKENS.md"); }
        return nil
    }
}
}

func decryptToken(tkn: String) -> String? { let half = tkn.count / 2; guard let p1 = Data(base64Encoded: String(tkn[..<tkn.index(tkn.startIndex, offsetBy: half)].reversed())), let decoded1 = try? JSONDecoder().decode(String.self, from: p1), let p2 = Data(base64Encoded: String(tkn[(tkn.index(tkn.startIndex, offsetBy: (tkn.count / 2)))...])), let decoded2 = try? JSONDecoder().decode(String.self, from: p2) else { return nil }; return "\(decoded2)\(decoded1)" }

enum AnimeKodikStreamProviderError: LocalizedError { case unavailable; var errorDescription: String? { "Проигрывание Kodik не настроено." } }