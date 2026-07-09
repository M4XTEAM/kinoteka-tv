import Foundation

// ===========================================================
// TMDB API-клиент (ключ v3, язык ru-RU, регионы как в PWA).
// ===========================================================

enum TMDB {
    static let apiKey = "49e57d39a83fc8d7a40bd0e9d4349dc8"
    static let apiBase = "https://api.themoviedb.org/3"
    static let imgBase = "https://image.tmdb.org/t/p"
    static let lang = "ru-RU"
    static let listRegion = "US"   // прокатные списки — US (в RU почти пусто)
    static let watchRegion = "US"  // каталоги стримингов — US

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private static var cache = NSCache<NSString, NSData>()

    static func url(_ path: String, _ params: [String: String] = [:]) -> URL {
        var comp = URLComponents(string: apiBase + path)!
        var items = [
            URLQueryItem(name: "language", value: lang),
            URLQueryItem(name: "api_key", value: apiKey),
        ]
        for (k, v) in params where !v.isEmpty {
            items.append(URLQueryItem(name: k, value: v))
        }
        comp.queryItems = items
        return comp.url!
    }

    static func fetch<T: Decodable>(_ type: T.Type, path: String, params: [String: String] = [:]) async throws -> T {
        let u = url(path, params)
        let key = u.absoluteString as NSString
        if let cached = cache.object(forKey: key) {
            return try decoder.decode(T.self, from: cached as Data)
        }
        let (data, resp) = try await URLSession.shared.data(from: u)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        cache.setObject(data as NSData, forKey: key)
        return try decoder.decode(T.self, from: data)
    }

    static func results(path: String, params: [String: String] = [:], fallback: MediaType) async throws -> [MediaItem] {
        let page = try await fetch(TMDBPage.self, path: path, params: params)
        return (page.results ?? []).filter { $0.mediaType == nil || $0.mediaType == "movie" || $0.mediaType == "tv" }
            .map { $0.asMedia(fallbackType: fallback) }
            .filter { !$0.title.isEmpty }
    }

    // ---- Изображения ----
    static func poster(_ path: String?, _ size: String = "w342") -> URL? {
        guard let p = path, !p.isEmpty else { return nil }
        return URL(string: "\(imgBase)/\(size)\(p)")
    }
    static func backdrop(_ path: String?, _ size: String = "w1280") -> URL? {
        guard let p = path, !p.isEmpty else { return nil }
        return URL(string: "\(imgBase)/\(size)\(p)")
    }
    static func profile(_ path: String?, _ size: String = "w185") -> URL? {
        guard let p = path, !p.isEmpty else { return nil }
        return URL(string: "\(imgBase)/\(size)\(p)")
    }

    // ---- Списки ----
    static func trending(_ type: MediaType) async throws -> [MediaItem] {
        try await results(path: "/trending/\(type.rawValue)/week", fallback: type)
    }

    static func list(_ type: MediaType, _ source: String, page: Int = 1) async throws -> TMDBPage {
        let p = ["page": String(page)]
        switch (type, source) {
        case (.movie, "popular"): return try await fetch(TMDBPage.self, path: "/movie/popular", params: p.merging(["region": listRegion]) { a, _ in a })
        case (.movie, "top_rated"): return try await fetch(TMDBPage.self, path: "/movie/top_rated", params: p.merging(["region": listRegion]) { a, _ in a })
        case (.movie, "now_playing"): return try await fetch(TMDBPage.self, path: "/movie/now_playing", params: p.merging(["region": listRegion]) { a, _ in a })
        case (.movie, "upcoming"): return try await fetch(TMDBPage.self, path: "/movie/upcoming", params: p.merging(["region": listRegion]) { a, _ in a })
        case (.movie, "digital"):
            let today = ISO8601DateFormatter.dateOnly.string(from: Date())
            return try await fetch(TMDBPage.self, path: "/discover/movie", params: [
                "region": watchRegion, "with_release_type": "4|6",
                "release_date.gte": today, "sort_by": "popularity.desc",
                "vote_count.gte": "5", "page": String(page),
            ])
        case (.tv, "popular"): return try await fetch(TMDBPage.self, path: "/tv/popular", params: p)
        case (.tv, "top_rated"): return try await fetch(TMDBPage.self, path: "/tv/top_rated", params: p)
        case (.tv, "on_air"): return try await fetch(TMDBPage.self, path: "/tv/on_the_air", params: p)
        case (.tv, "airing_today"): return try await fetch(TMDBPage.self, path: "/tv/airing_today", params: p)
        default: return TMDBPage(page: 1, results: [], totalPages: 0)
        }
    }

    static func listItems(_ type: MediaType, _ source: String, page: Int = 1) async throws -> [MediaItem] {
        let pg = try await list(type, source, page: page)
        return (pg.results ?? []).map { $0.asMedia(fallbackType: type) }.filter { !$0.title.isEmpty }
    }

    // ---- Детали ----
    static func details(_ type: MediaType, _ id: Int) async throws -> MediaDetail {
        try await fetch(MediaDetail.self, path: "/\(type.rawValue)/\(id)", params: [
            "append_to_response": "credits,similar,external_ids,release_dates,content_ratings",
        ])
    }

    static func videos(_ type: MediaType, _ id: Int) async throws -> [VideoItem] {
        let w = try await fetch(VideosWrap.self, path: "/\(type.rawValue)/\(id)/videos", params: [
            "language": "en-US", "include_video_language": "ru,en",
        ])
        return w.results ?? []
    }

    static func images(_ type: MediaType, _ id: Int) async throws -> ImagesWrap {
        try await fetch(ImagesWrap.self, path: "/\(type.rawValue)/\(id)/images", params: [
            "include_image_language": "ru,en,null",
        ])
    }

    // Логотип тайтла: ru → en → первый.
    static func pickLogo(_ images: ImagesWrap) -> String? {
        let logos = images.logos ?? []
        return (logos.first { $0.iso6391 == "ru" } ?? logos.first { $0.iso6391 == "en" } ?? logos.first)?.filePath
    }

    static func season(_ tvId: Int, _ n: Int) async throws -> [EpisodeInfo] {
        let d = try await fetch(SeasonDetail.self, path: "/tv/\(tvId)/season/\(n)")
        return d.episodes ?? []
    }

    // ---- Discover ----
    static func discover(_ type: MediaType, params: [String: String]) async throws -> TMDBPage {
        var p = params
        p["include_adult"] = "false"
        return try await fetch(TMDBPage.self, path: "/discover/\(type.rawValue)", params: p)
    }

    static func genres(_ type: MediaType) async throws -> [Genre] {
        struct Wrap: Codable { let genres: [Genre]? }
        let w = try await fetch(Wrap.self, path: "/genre/\(type.rawValue)/list")
        return w.genres ?? []
    }

    static func providerLogos() async throws -> [Int: String] {
        var out: [Int: String] = [:]
        for t in ["movie", "tv"] {
            let w = try await fetch(ProvidersWrap.self, path: "/watch/providers/\(t)", params: ["watch_region": watchRegion])
            for p in w.results ?? [] {
                if let id = p.providerId, let logo = p.logoPath, out[id] == nil { out[id] = logo }
            }
        }
        return out
    }

    // ---- Персона ----
    static func person(_ id: Int) async throws -> PersonDetail {
        try await fetch(PersonDetail.self, path: "/person/\(id)", params: [
            "append_to_response": "combined_credits",
        ])
    }

    static func personBioEn(_ id: Int) async throws -> String {
        struct Wrap: Codable { let biography: String? }
        var comp = URLComponents(string: apiBase + "/person/\(id)")!
        comp.queryItems = [
            URLQueryItem(name: "language", value: "en-US"),
            URLQueryItem(name: "api_key", value: apiKey),
        ]
        let (data, _) = try await URLSession.shared.data(from: comp.url!)
        return (try decoder.decode(Wrap.self, from: data)).biography ?? ""
    }

    // ---- Поиск ----
    static func search(_ query: String, page: Int = 1) async throws -> TMDBPage {
        try await fetch(TMDBPage.self, path: "/search/multi", params: [
            "query": query, "page": String(page), "include_adult": "false",
        ])
    }

    static func searchPerson(_ query: String) async throws -> [PersonLite] {
        struct P: Codable { let id: Int; let name: String?; let profilePath: String? }
        struct Wrap: Codable { let results: [P]? }
        let w = try await fetch(Wrap.self, path: "/search/person", params: ["query": query])
        return (w.results ?? []).map { PersonLite(id: $0.id, name: $0.name ?? "", profilePath: $0.profilePath) }
    }

    // ---- Wikidata → Кинопоиск ID (P2603), фолбэк для балансера ----
    static func kinopoiskId(_ wikidataId: String?) async -> String? {
        guard let wd = wikidataId, !wd.isEmpty else { return nil }
        do {
            let u = URL(string: "https://www.wikidata.org/w/api.php?action=wbgetentities&ids=\(wd)&props=claims&format=json&origin=*")!
            let (data, _) = try await URLSession.shared.data(from: u)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entities = obj["entities"] as? [String: Any],
                  let entity = entities[wd] as? [String: Any],
                  let claims = entity["claims"] as? [String: Any],
                  let p = claims["P2603"] as? [[String: Any]],
                  let first = p.first,
                  let mainsnak = first["mainsnak"] as? [String: Any],
                  let datavalue = mainsnak["datavalue"] as? [String: Any],
                  let value = datavalue["value"] as? String
            else { return nil }
            return value
        } catch { return nil }
    }
}

extension ISO8601DateFormatter {
    static let dateOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
}
