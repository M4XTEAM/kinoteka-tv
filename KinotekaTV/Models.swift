import Foundation

// ===========================================================
// TMDB-модели (Codable, decoder = .convertFromSnakeCase)
// + нормализованный элемент MediaItem.
// ===========================================================

enum MediaType: String, Codable, Hashable {
    case movie, tv
}

struct MediaItem: Codable, Identifiable, Hashable {
    let id: Int
    var mediaType: MediaType
    var title: String
    var posterPath: String?
    var backdropPath: String?
    var voteAverage: Double?
    var releaseDate: String?
    var overview: String?

    init(id: Int, mediaType: MediaType, title: String, posterPath: String?, backdropPath: String?,
         voteAverage: Double?, releaseDate: String?, overview: String? = nil) {
        self.id = id
        self.mediaType = mediaType
        self.title = title
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.voteAverage = voteAverage
        self.releaseDate = releaseDate
        self.overview = overview
    }
}

// Сырой результат TMDB (movie | tv | person в multi-search).
struct TMDBResult: Codable {
    let id: Int
    let mediaType: String?
    let title: String?
    let name: String?
    let posterPath: String?
    let backdropPath: String?
    let profilePath: String?
    let voteAverage: Double?
    let releaseDate: String?
    let firstAirDate: String?
    let overview: String?
    let knownForDepartment: String?

    func asMedia(fallbackType: MediaType) -> MediaItem {
        let t: MediaType
        if let mt = mediaType, let parsed = MediaType(rawValue: mt) { t = parsed }
        else if firstAirDate != nil || name != nil { t = .tv }
        else { t = fallbackType }
        return MediaItem(
            id: id, mediaType: t,
            title: title ?? name ?? "",
            posterPath: posterPath, backdropPath: backdropPath,
            voteAverage: voteAverage,
            releaseDate: releaseDate ?? firstAirDate,
            overview: overview
        )
    }
}

struct TMDBPage: Codable {
    let page: Int?
    let results: [TMDBResult]?
    let totalPages: Int?
}

// ---- Детальная карточка ----
struct Genre: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
}

struct CastMember: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let character: String?
    let profilePath: String?
}

struct CrewMember: Codable, Hashable {
    let id: Int
    let name: String
    let job: String?
    let department: String?
    let profilePath: String?
}

struct Credits: Codable {
    let cast: [CastMember]?
    let crew: [CrewMember]?
}

struct ExternalIds: Codable {
    let imdbId: String?
    let wikidataId: String?
}

struct SeasonInfo: Codable, Hashable, Identifiable {
    let id: Int
    let seasonNumber: Int
    let episodeCount: Int?
    let name: String?
    let airDate: String?
}

struct EpisodeInfo: Codable, Identifiable, Hashable {
    let id: Int
    let episodeNumber: Int
    let seasonNumber: Int?
    let name: String?
    let overview: String?
    let stillPath: String?
    let airDate: String?
    let runtime: Int?
}

struct SeasonDetail: Codable {
    let episodes: [EpisodeInfo]?
}

struct NextEpisode: Codable {
    let airDate: String?
    let episodeNumber: Int?
    let seasonNumber: Int?
}

struct ReleaseDatesWrap: Codable {
    struct Entry: Codable {
        struct Item: Codable {
            let certification: String?
            let type: Int?
            let releaseDate: String?
        }
        let iso31661: String?
        let releaseDates: [Item]?
    }
    let results: [Entry]?
}

struct ContentRatingsWrap: Codable {
    struct Entry: Codable {
        let iso31661: String?
        let rating: String?
    }
    let results: [Entry]?
}

struct Creator: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let profilePath: String?
}

struct Network: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let logoPath: String?
}

struct MediaDetail: Codable {
    let id: Int
    let title: String?
    let name: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let voteAverage: Double?
    let releaseDate: String?
    let firstAirDate: String?
    let runtime: Int?
    let episodeRunTime: [Int]?
    let numberOfSeasons: Int?
    let numberOfEpisodes: Int?
    let genres: [Genre]?
    let tagline: String?
    let status: String?
    let budget: Int?
    let revenue: Int?
    let createdBy: [Creator]?
    let networks: [Network]?
    let credits: Credits?
    let similar: TMDBPage?
    let externalIds: ExternalIds?
    let seasons: [SeasonInfo]?
    let nextEpisodeToAir: NextEpisode?
    let releaseDates: ReleaseDatesWrap?
    let contentRatings: ContentRatingsWrap?

    var displayTitle: String { title ?? name ?? "" }
    var date: String? { releaseDate ?? firstAirDate }

    // Дата цифрового релиза (type 4 = Digital, 6 = TV) из release_dates (US→RU→любой).
    var digitalDate: String? {
        let entries = releaseDates?.results ?? []
        func pick(_ iso: String) -> String? {
            entries.first { $0.iso31661 == iso }?.releaseDates?
                .first { $0.type == 4 || $0.type == 6 }?.releaseDate
        }
        let raw = pick("US") ?? pick("RU") ?? entries.compactMap { e in
            e.releaseDates?.first { $0.type == 4 || $0.type == 6 }?.releaseDate
        }.first
        return raw.map { String($0.prefix(10)) }
    }

    func asMedia(_ type: MediaType) -> MediaItem {
        MediaItem(id: id, mediaType: type, title: displayTitle,
                  posterPath: posterPath, backdropPath: backdropPath,
                  voteAverage: voteAverage, releaseDate: date, overview: overview)
    }

    // Возрастной рейтинг: movie — release_dates (RU→US), tv — content_ratings.
    func certification(_ type: MediaType) -> String? {
        if type == .movie {
            let entries = releaseDates?.results ?? []
            for iso in ["RU", "US"] {
                if let e = entries.first(where: { $0.iso31661 == iso }),
                   let c = (e.releaseDates ?? []).compactMap({ $0.certification }).first(where: { !$0.isEmpty }) {
                    return c
                }
            }
        } else {
            let entries = contentRatings?.results ?? []
            for iso in ["RU", "US"] {
                if let r = entries.first(where: { $0.iso31661 == iso })?.rating, !r.isEmpty { return r }
            }
        }
        return nil
    }
}

// ---- Видео (трейлеры) ----
struct VideoItem: Codable {
    let key: String?
    let site: String?
    let type: String?
    let official: Bool?
    let iso6391: String?
}

struct VideosWrap: Codable {
    let results: [VideoItem]?
}

// ---- Изображения (логотипы тайтла) ----
struct ImageInfo: Codable {
    let filePath: String?
    let iso6391: String?
}

struct ImagesWrap: Codable {
    let logos: [ImageInfo]?
    let backdrops: [ImageInfo]?
}

// ---- Персона ----
struct PersonCredit: Codable, Hashable {
    let id: Int
    let mediaType: String?
    let title: String?
    let name: String?
    let posterPath: String?
    let voteAverage: Double?
    let releaseDate: String?
    let firstAirDate: String?
    let character: String?
    let job: String?
    let popularity: Double?

    var asMedia: MediaItem {
        let t: MediaType = (mediaType == "tv") ? .tv : .movie
        return MediaItem(id: id, mediaType: t, title: title ?? name ?? "",
                         posterPath: posterPath, backdropPath: nil,
                         voteAverage: voteAverage, releaseDate: releaseDate ?? firstAirDate)
    }
}

struct CombinedCredits: Codable {
    let cast: [PersonCredit]?
    let crew: [PersonCredit]?
}

struct PersonExternalIds: Codable {
    let instagramId: String?
    let twitterId: String?
}

struct PersonDetail: Codable {
    let id: Int
    let name: String
    let biography: String?
    let birthday: String?
    let deathday: String?
    let placeOfBirth: String?
    let profilePath: String?
    let knownForDepartment: String?
    let combinedCredits: CombinedCredits?
    let externalIds: PersonExternalIds?
}

// ---- Watch providers ----
struct ProviderInfo: Codable {
    let providerId: Int?
    let logoPath: String?
    let providerName: String?
}

struct ProvidersWrap: Codable {
    let results: [ProviderInfo]?
}

struct StreamProvider: Identifiable, Hashable {
    let id: Int
    let name: String
}

let STREAM_PROVIDERS: [StreamProvider] = [
    .init(id: 8, name: "Netflix"), .init(id: 337, name: "Disney+"),
    .init(id: 1899, name: "HBO Max"), .init(id: 9, name: "Prime Video"),
    .init(id: 350, name: "Apple TV+"), .init(id: 15, name: "Hulu"),
    .init(id: 386, name: "Peacock"), .init(id: 2303, name: "Paramount+"),
    .init(id: 283, name: "Crunchyroll"), .init(id: 43, name: "Starz"),
    .init(id: 526, name: "AMC+"), .init(id: 583, name: "MGM+"),
]

// ---- Идентификатор для балансеров ----
struct WatchId: Hashable, Codable {
    var imdb: String?
    var kp: String?

    var query: String? {
        if let imdb, imdb.hasPrefix("tt") { return "imdb=\(imdb)" }
        if let kp, !kp.isEmpty { return "kp=\(kp)" }
        return nil
    }
}

// ---- Ответ /api/players (балансеры) ----
struct BalancerPlayer: Codable {
    let type: String?
    let iframeUrl: String?
}

// ---- Ответ /api/kp (Кинопаб) ----
struct KpSub: Codable {
    let lang: String?
    let label: String?
    let url: String?
}

struct KpVoice: Codable {
    let label: String?
}

struct KpResponse: Codable {
    let found: Bool?
    let master: String?
    let seasons: [String: [Int]]?
    let subs: [KpSub]?
    let voices: [KpVoice]?
}

// ---- Источник нашего плеера (ylitron / kinopub) ----
struct YlSubtitle: Codable, Hashable {
    let lang: String?
    let label: String?
    let url: String?
}

struct YlSource: Codable, Hashable {
    let label: String?
    let url: String?
    let subtitles: [YlSubtitle]?
}

// ---- ИИ-ассистент ----
struct AIActionTitle: Codable {
    let title: String?
    let media: String?
    let year: Int?
}

struct AIAction: Codable {
    let kind: String?
    let titles: [AIActionTitle]?
    let media: String?
    let person: String?
    let genre: String?
    let yearFrom: Int?
    let yearTo: Int?
    let sort: String?
    let target: String?
    let name: String?
}

struct AIResponse: Codable {
    let reply: String?
    let chips: [String]?
    let actions: [AIAction]?
}

struct PersonLite: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let profilePath: String?
}

struct AIMessage: Identifiable, Hashable {
    let id = UUID()
    let role: String   // "user" | "model"
    var text: String
    var cards: [MediaItem] = []
    var persons: [PersonLite] = []
    var chips: [String] = []
}
