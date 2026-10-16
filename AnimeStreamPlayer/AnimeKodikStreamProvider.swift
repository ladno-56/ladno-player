import Foundation
import SwiftUI

private struct KodikApiClient {
    let baseUrl = "https://kodik-api.com"

    func listAnime(token: String) async throws -> [KodikItem] {
        var request = URLRequest(url: URL(string: "\(baseUrl)/list?token=\(token)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            throw AnimeKodikStreamProviderError.unavailable
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["results"] as? [[String: Any]] else { return [] }
        return items.map { item -> KodikItem in
            KodikItem(
                id: (item["id"] as? String) ?? "",
                type: (item["type"] as? String) ?? "anime",
                title: (item["title"] as? String) ?? "",
                originalTitle: (item["title_orig"] as? String)
            )
        }
    }

    func searchAnime(query: String, token: String) async throws -> [KodikItem] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        var request = URLRequest(url: URL(string: "\(baseUrl)/search?token=\(token)&title=\(encodedQuery)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            throw AnimeKodikStreamProviderError.unavailable
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["results"] as? [[String: Any]] else { return [] }
        return items.map { item -> KodikItem in
            KodikItem(
                id: (item["id"] as? String) ?? "",
                type: (item["type"] as? String) ?? "anime",
                title: (item["title"] as? String) ?? "",
                originalTitle: (item["title_orig"] as? String)
            )
        }
    }
}

private struct KodikSearchResult {
    let id: String
    let type: String
    let title: String
    let originalTitle: String?
    let translationId: Int?
}

private struct KodikItem {
    let id: String
    let type: String
    let title: String
    let originalTitle: String?
}

struct AnimeKodikCatalogProvider: AnimeCatalogProvider {
    private let client = KodikApiClient()

    func airingTitles() async throws -> [AnimeTitle] {
        guard let token = try? await loadToken() else { return [] }
        do {
            let results = try await client.listAnime(token: token)
            return results.map { item in
                AnimeTitle(
                    id: item.id,
                    title: item.title,
                    originalTitle: item.originalTitle ?? "",
                    synopsis: "",
                    genres: [],
                    posterURL: nil,
                    isAiring: true,
                    releasedEpisodeCount: 0,
                    voices: []
                )
            }
        } catch {
            throw AnimeKodikStreamProviderError.unavailable
        }
    }

    func searchTitles(query: String) async throws -> [AnimeTitle] {
        guard let token = try? await loadToken() else { return [] }
        do {
            let results = try await client.searchAnime(query: query, token: token)
            return results.map { result in
                AnimeTitle(
                    id: result.id,
                    title: result.title,
                    originalTitle: result.originalTitle ?? "",
                    synopsis: "",
                    genres: [],
                    posterURL: nil,
                    isAiring: true,
                    releasedEpisodeCount: 0,
                    voices: []
                )
            }
        } catch {
            throw AnimeKodikStreamProviderError.unavailable
        }
    }

    private func loadToken() async throws -> String? {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: "kodik.token") {
            return stored
        }

        let parserToken = await getKodikParserToken()
        if let pt = parserToken {
            defaults.set(pt, forKey: "kodik.token")
            return pt
        }
        return nil
    }

    private func getKodikParserToken() async -> String? {
        do {
            let url = URL(string: "https://githubusercontent.com")!
            let (data, _) = try await URLSession.shared.data(from: url)

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let stableArray = json["stable"] as? [[String: Any]] {
                for item in stableArray {
                    if let tokn = item["tokn"] as? String,
                       let validToken = isValidTokn(tokn) {
                        return validToken
                    }
                }
            }
        } catch {
            print("KODIK: Failed to load token from repository JSON")
        }
        return nil
    }
}

private func isValidTokn(_ tkn: String) -> String? {
    decryptToken(tkn: tkn)
}

func decryptToken(tkn: String) -> String? {
    let half = tkn.count / 2
    let index = tkn.index(tkn.startIndex, offsetBy: half)

    let firstPart = String(tkn[tkn.startIndex..<index].reversed())
    let secondPart = String(tkn[index..<tkn.endIndex])

    guard let p1 = Data(base64Encoded: firstPart),
          let decoded1 = try? JSONDecoder().decode(String.self, from: p1),
          let p2 = Data(base64Encoded: secondPart),
          let decoded2 = try? JSONDecoder().decode(String.self, from: p2)
    else { return nil }

    return "\(decoded2)\(decoded1)"
}

enum AnimeKodikStreamProviderError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Проигрывание Kodik не настроено."
    }
}