import Foundation

// MARK: - Provider enum (from ShikiApp's VideoSource)
enum VideoProvider: String, CaseIterable, Identifiable {
    case KODIK = "Kodik"
    case COLLAPS = "Collapse"
    case CVH = "VideoHub"
    case ANIMELIB = "AnimeLib"
    
    var id: String { rawValue }
}

// MARK: - Episode model (from ShikiApp's EpisodeModel)
struct VideoEpisode: Identifiable, Codable {
    let number: Int
    let link: URL?
    let audioIndex: Int?
    let screenshotURL: URL?
    
    init(number: Int, link: String?, audioIndex: Int? = nil, screenshot: String?) {
        self.number = number
        self.link = link.flatMap { URL(string: $0) }
        self.audioIndex = audioIndex
        self.screenshotURL = screenshot.flatMap { URL(string: $0) }
    }
}

// MARK: - Subtitle track (from ShikiApp's SubtitleTrack)
struct SubtitleTrack: Identifiable, Codable {
    let name: String
    let url: String
    
    var id: String { name + url }
    
    static func off() -> SubtitleTrack {
        return SubtitleTrack(name: "Выключено", url: "")
    }
}

// MARK: - Video voice (from ShikiApp's VideoVoice)
struct VideoVoice: Identifiable, Codable {
    let id: Int
    let title: String
    let hasDubbers: Bool
    let hasSubtitles: Bool
    let episodes: [VideoEpisode]
    let qualityTitle: String?
    let lastEpisode: Int
    
    var episodesCount: Int { episodes.count }
    var hasEpisodes: Bool { episodesCount > 0 }
}

// MARK: - Video source data (from ShikiApp's VideoSourceData)
struct VideoSourceData {
    let type: VideoProvider
    let voices: [VideoVoice]
}
