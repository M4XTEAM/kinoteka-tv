import Foundation

// Minimal TMDB client: multi-search + external_ids (to get IMDB id for the balancer).
enum TMDB {
    static let key = "49e57d39a83fc8d7a40bd0e9d4349dc8"
    static let base = "https://api.themoviedb.org/3"

    static func search(_ query: String) async -> [TMDBItem] {
        guard var c = URLComponents(string: "\(base)/search/multi") else { return [] }
        c.queryItems = [
            .init(name: "api_key", value: key),
            .init(name: "query", value: query),
            .init(name: "language", value: "ru-RU"),
            .init(name: "include_adult", value: "false"),
        ]
        guard let url = c.url, let (data, _) = try? await URLSession.shared.data(from: url) else { return [] }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { r in
            let media = r["media_type"] as? String ?? ""
            guard media == "movie" || media == "tv" else { return nil }
            let isTV = media == "tv"
            guard let id = r["id"] as? Int else { return nil }
            let title = (r["title"] as? String) ?? (r["name"] as? String) ?? "—"
            let date = (r["release_date"] as? String) ?? (r["first_air_date"] as? String) ?? ""
            return TMDBItem(id: id, title: title, year: String(date.prefix(4)), isTV: isTV,
                            posterPath: r["poster_path"] as? String)
        }
    }

    static func imdbID(for item: TMDBItem) async -> String? {
        let kind = item.isTV ? "tv" : "movie"
        guard let url = URL(string: "\(base)/\(kind)/\(item.id)/external_ids?api_key=\(key)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let imdb = root["imdb_id"] as? String, imdb.hasPrefix("tt") else { return nil }
        return imdb
    }
}
