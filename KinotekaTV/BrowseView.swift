import SwiftUI

// ===========================================================
// Каталог: страницы «Все ›» (ListView), сетка жанров (GenresView)
// и discover-браузер с фильтрами (BrowseView).
// ===========================================================

struct ListView: View {
    let route: ListRoute

    @State private var items: [MediaItem] = []
    @State private var page = 0
    @State private var totalPages = 1
    @State private var loading = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PosterGrid(items: items) { loadMore() }
                if loading { LoadingView() }
                Color.clear.frame(height: 30)
            }
            .padding(.top, 8)
        }
        .background(Theme.bg)
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if items.isEmpty { loadMore() }
        }
    }

    private func loadMore() {
        guard !loading, page < totalPages else { return }
        loading = true
        Task {
            let next = page + 1
            if let pg = try? await TMDB.list(route.type, route.source, page: next) {
                let new = (pg.results ?? []).map { $0.asMedia(fallbackType: route.type) }.filter { !$0.title.isEmpty }
                let existing = Set(items.map(\.id))
                items.append(contentsOf: new.filter { !existing.contains($0.id) })
                page = pg.page ?? next
                totalPages = pg.totalPages ?? page
            } else {
                totalPages = page
            }
            loading = false
        }
    }
}

struct GenresView: View {
    let type: MediaType

    @State private var genres: [Genre] = []

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(genres) { g in
                    NavigationLink(value: BrowseRoute(type: type, genreId: g.id, genreName: g.name)) {
                        Text(g.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.genreAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 72)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
                }
            }
            .padding(20)
        }
        .background(Theme.bg)
        .navigationTitle(type == .movie ? "Жанры · Фильмы" : "Жанры · Сериалы")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            genres = (try? await TMDB.genres(type)) ?? []
        }
    }
}

struct BrowseView: View {
    @State var route: BrowseRoute

    @State private var items: [MediaItem] = []
    @State private var page = 0
    @State private var totalPages = 1
    @State private var loading = false
    @State private var genres: [Genre] = []
    @State private var year: Int?
    @State private var sort = "popularity.desc"

    private let sorts: [(String, String)] = [
        ("Популярные", "popularity.desc"),
        ("По рейтингу", "vote_average.desc"),
        ("Новые", "primary_release_date.desc"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                filters
                PosterGrid(items: items) { loadMore() }
                if loading { LoadingView() }
                Color.clear.frame(height: 30)
            }
            .padding(.top, 8)
        }
        .background(Theme.bg)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if genres.isEmpty {
                genres = (try? await TMDB.genres(route.type)) ?? []
            }
            if items.isEmpty { loadMore() }
        }
    }

    private var title: String {
        if let p = route.providerName { return p }
        if let g = route.genreName { return g }
        return route.type == .movie ? "Фильмы" : "Сериалы"
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Тип.
                Menu {
                    Button("Фильмы") { setType(.movie) }
                    Button("Сериалы") { setType(.tv) }
                } label: {
                    filterChip(route.type == .movie ? "Фильмы" : "Сериалы")
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)

                // Жанр.
                Menu {
                    Button("Все жанры") { setGenre(nil) }
                    ForEach(genres) { g in
                        Button(g.name) { setGenre(g) }
                    }
                } label: {
                    filterChip(route.genreName ?? "Жанр")
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)

                // Год.
                Menu {
                    Button("Все годы") { setYear(nil) }
                    ForEach(Array(stride(from: Calendar.current.component(.year, from: Date()), through: 1970, by: -1)), id: \.self) { y in
                        Button(String(y)) { setYear(y) }
                    }
                } label: {
                    filterChip(year.map(String.init) ?? "Год")
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)

                // Сортировка.
                Menu {
                    ForEach(sorts, id: \.1) { s in
                        Button(s.0) { setSort(s.1) }
                    }
                } label: {
                    filterChip(sorts.first { $0.1 == sort }?.0 ?? "Сортировка")
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .padding(.horizontal, 20)
        }
    }

    private func filterChip(_ text: String) -> some View {
        HStack(spacing: 5) {
            Text(text)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
    }

    private func setType(_ t: MediaType) {
        guard t != route.type else { return }
        route.type = t
        route.genreId = nil
        route.genreName = nil
        Task {
            genres = (try? await TMDB.genres(t)) ?? []
            reset()
        }
    }

    private func setGenre(_ g: Genre?) {
        route.genreId = g?.id
        route.genreName = g?.name
        reset()
    }

    private func setYear(_ y: Int?) {
        year = y
        reset()
    }

    private func setSort(_ s: String) {
        sort = s
        reset()
    }

    private func reset() {
        items = []
        page = 0
        totalPages = 1
        loadMore()
    }

    private func loadMore() {
        guard !loading, page < totalPages else { return }
        loading = true
        Task {
            let next = page + 1
            var params: [String: String] = ["page": String(next)]
            let isMovie = route.type == .movie
            params["sort_by"] = isMovie ? sort : sort.replacingOccurrences(of: "primary_release_date", with: "first_air_date")
            if sort.hasPrefix("vote_average") { params["vote_count.gte"] = "200" }
            if let g = route.genreId { params["with_genres"] = String(g) }
            if let p = route.providerId {
                params["with_watch_providers"] = String(p)
                params["watch_region"] = TMDB.watchRegion
            }
            if let y = year {
                let key = isMovie ? "primary_release_date" : "first_air_date"
                params["\(key).gte"] = "\(y)-01-01"
                params["\(key).lte"] = "\(y)-12-31"
            }
            if let pg = try? await TMDB.discover(route.type, params: params) {
                let new = (pg.results ?? []).map { $0.asMedia(fallbackType: route.type) }.filter { !$0.title.isEmpty }
                let existing = Set(items.map(\.id))
                items.append(contentsOf: new.filter { !existing.contains($0.id) })
                page = pg.page ?? next
                totalPages = min(pg.totalPages ?? page, 500)
            } else {
                totalPages = page
            }
            loading = false
        }
    }
}
