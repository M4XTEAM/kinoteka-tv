import Foundation

// Minimal TMDB client: home rows, search, external_ids (IMDB for the balancer), details.
enum TMDB {
    static let key = "49e57d39a83fc8d7a40bd0e9d4349dc8"
    static let base = "https://api.themoviedb.org/3"
    static let lang = "ru-RU"

    private static func get(_ path: String, _ q: [String: String] = [:]) async -> [String: Any]? {
        guard var c = URLComponents(string: "\(base)\(path)") else { return nil }
        var items = [URLQueryItem(name: "api_key", value: key), URLQueryItem(name: "language", value: lang)]
        items += q.map { URLQueryItem(name: $0.key, value: $0.value) }
        c.queryItems = items
        guard let url = c.url, let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func parse(_ results: [[String: Any]], forceTV: Bool? = nil) -> [TMDBItem] {
        results.compactMap { r in
            let media = r["media_type"] as? String
            let isTV = forceTV ?? (media == "tv")
            if media != nil && media != "movie" && media != "tv" { return nil }
            guard let id = r["id"] as? Int else { return nil }
            let title = (r["title"] as? String) ?? (r["name"] as? String) ?? "—"
            let date = (r["release_date"] as? String) ?? (r["first_air_date"] as? String) ?? ""
            return TMDBItem(id: id, title: title, year: String(date.prefix(4)), isTV: isTV,
                            posterPath: r["poster_path"] as? String,
                            overview: r["overview"] as? String ?? "",
                            backdropPath: r["backdrop_path"] as? String)
        }
    }

    static func home() async -> [HomeRow] {
        async let trMovies = get("/trending/movie/week")
        async let trTV = get("/trending/tv/week")
        async let topMovies = get("/movie/top_rated")
        let rows: [(String, [String: Any]?, Bool?)] = [
            ("В тренде · Фильмы", await trMovies, false),
            ("В тренде · Сериалы", await trTV, true),
            ("Лучшие фильмы", await topMovies, false),
        ]
        return rows.compactMap { title, json, forceTV in
            guard let results = json?["results"] as? [[String: Any]] else { return nil }
            let items = parse(results, forceTV: forceTV)
            return items.isEmpty ? nil : HomeRow(title: title, items: items)
        }
    }

    static func search(_ query: String) async -> [TMDBItem] {
        guard let json = await get("/search/multi", ["query": query, "include_adult": "false"]),
              let results = json["results"] as? [[String: Any]] else { return [] }
        return parse(results)
    }

    static func imdbID(for item: TMDBItem) async -> String? {
        let kind = item.isTV ? "tv" : "movie"
        guard let json = await get("/\(kind)/\(item.id)/external_ids"),
              let imdb = json["imdb_id"] as? String, imdb.hasPrefix("tt") else { return nil }
        return imdb
    }

    // Returns (overview, backdropPath, seasonCount) — fills the detail screen.
    static func details(for item: TMDBItem) async -> (String, String?, Int) {
        let kind = item.isTV ? "tv" : "movie"
        guard let json = await get("/\(kind)/\(item.id)") else { return (item.overview, item.backdropPath, 1) }
        let overview = (json["overview"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? item.overview
        let backdrop = (json["backdrop_path"] as? String) ?? item.backdropPath
        let seasons = (json["number_of_seasons"] as? Int) ?? 1
        return (overview, backdrop, max(1, seasons))
    }
}
