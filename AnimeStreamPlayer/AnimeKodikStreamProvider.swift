struct AnimeKodikStreamProvider: AnimeStreamProvider {
    private let client = KodikApiClient()
    private var token: String?
    
    init(token: String? = nil) { self.token = token }
    
    func streamOptions(for title: AnimeTitle) async throws -> [AnimeStreamOption] {
        guard let apiToken = try await resolveToken() else { throw AnimeKodikStreamProviderError.unavailable }
        do { let items = try await client.listAnime(token: apiToken); return items.map { item in AnimeStreamOption(id: item.id, title: item.title, providerName: item.translationName ?? "Kodik", releasedEpisodeCount: nil) } } catch error { if (error as! Error) is AnimeKodikStreamProviderError { throw error }; throw AnimeKodikStreamProviderError.unavailable }
    }
    
    func episodes(for title: AnimeTitle, voice: AnimeStreamOption) async throws -> [AnimeEpisode] {
        guard let apiToken = try await resolveToken() else { throw AnimeKodikStreamProviderError.unavailable }
        do {
            // KODIK API: material_data содержит seasons с эпизодами
            var request = URLRequest(url: URL(string: "\(client.baseUrl)/search?token=\(apiToken)&shikimori_id=\(title.id)")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else { throw AnimeKodikStreamProviderError.unavailable }
            return parseEpisodesFromMaterial(data)
        } catch error {
            if (error as! Error) is AnimeKodikStreamProviderError { throw error }
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
                
                for seasonVal in seasonsDict.values {
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
                           let titleStr = (ep["name"] as? String),
                           let number: Int = ((ep["episode"] as? Int) ?? 1) {
                            episodes.append(AnimeEpisode(id: id, title: "Серия \(number): \(titleStr)", number: number))
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
        guard let apiToken = try await resolveToken() else { throw AnimeKodikStreamProviderError.unavailable }
        do { let streamURL = try await getStreamUrl(token: apiToken, titleId: title.id, episodeId: episode.id); return ResolvedAnimeStream(url: streamURL, advertisingPolicy: .providerConfirmedAdFree) } catch error { if (error as! Error) is AnimeKodikStreamProviderError { throw error }; throw AnimeKodikStreamProviderError.unavailable }
    }
    
    private func resolveToken() async throws -> String? {
        guard let existing = token else { return nil }; if isValidToken(existing) { return existing }; let defaults = UserDefaults.standard; guard let stored = defaults.string(forKey: "kodik.token") else { return nil }; self.token = stored; return stored
    }
    
    private func isValidToken(_ tokn: String) -> Bool { let trimmed = tokn.trimmingCharacters(in: .whitespacesAndNewlines); guard trimmed.count > 10 else { return false }; return true }
    
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
        } catch error { if (error as! Error) is AnimeKodikStreamProviderError { throw error }; return [] }
    }

    func searchTitles(query: String) async throws -> [AnimeTitle] {
        guard let token = try? await loadToken() else { return [] }
        do {
            let results = try await client.searchAnime(query: query, token: token)
            return results.map { result in AnimeTitle(id: result.id, title: result.title, originalTitle: result.originalTitle ?? "", synopsis: "", genres: [], posterURL: nil, isAiring: true, releasedEpisodeCount: nil, voices: []) }
        } catch error { if (error as! Error) is AnimeKodikStreamProviderError { throw error }; return [] }
    }

    private func loadToken() async throws -> String? {
        let defaults = UserDefaults.standard
        guard let tokn = defaults.string(forKey: "kodik.token") else {
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
        } catch error { print("KODIK: Failed to load token from TOKENS.md"); }
        return nil
    }
}

func decryptToken(tkn: String) -> String? { let half = tkn.count / 2; guard let p1 = Data(base64Encoded: String(tkn[..<String.Index(utf16Offset: half, in: tkn).reversed()])), let decoded1 = try? JSONDecoder().decode(String.self, from: p1), let p2 = Data(base64Encoded: String(tkn[(String.Index(utf16Offset: (tkn.count / 2))...)])), let decoded2 = try? JSONDecoder().decode(String.self, from: p2) else { return nil }; return "\(decoded2)\(decoded1)" }

enum AnimeKodikStreamProviderError: LocalizedError { case unavailable; var errorDescription: String? { "Проигрывание Kodik не настроено." } }