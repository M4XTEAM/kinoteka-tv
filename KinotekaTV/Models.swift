import Foundation

// A TMDB search hit (movie or tv).
struct TMDBItem: Identifiable, Hashable {
    let id: Int
    let title: String
    let year: String
    let isTV: Bool
    let posterPath: String?
    var overview: String = ""
    var backdropPath: String? = nil
    var posterURL: URL? { posterPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w342\($0)") } }
    var backdropURL: URL? { backdropPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w780\($0)") } }
}

// A titled row of items for the home screen.
struct HomeRow: Identifiable {
    let id = UUID()
    let title: String
    let items: [TMDBItem]
}

// One translation (voice) with its per-quality master m3u8 URLs, parsed from Alloha /bnsi.
struct VoiceTrack: Identifiable, Hashable {
    let id = UUID()
    let label: String              // e.g. "(Russian) Dub Blu-Ray"
    let qualities: [Quality]       // sorted high->low
}

struct Quality: Identifiable, Hashable {
    let id = UUID()
    let height: Int                // 1080, 720, ...
    let url: String                // direct master m3u8 (VK CDN)
    var label: String { "\(height)p" }
}

struct ExtractResult {
    let voices: [VoiceTrack]
}

enum ExtractError: LocalizedError {
    case noImdb, noAlloha, notCaptured(String)
    var errorDescription: String? {
        switch self {
        case .noImdb: return "Не найден IMDB id для этого тайтла"
        case .noAlloha: return "Alloha-источник недоступен для этого тайтла"
        case .notCaptured(let m): return "Не удалось извлечь поток: \(m)"
        }
    }
}
