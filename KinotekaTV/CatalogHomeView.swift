import SwiftUI

// ===========================================================
// Главная «Фильмы» / «Сериалы»: hero-карусель + полки
// (порядок секций 1:1 с PWA).
// ===========================================================

struct CatalogHomeView: View {
    let type: MediaType

    @EnvironmentObject private var store: Store
    @Namespace private var zoomNS

    @State private var hero: [HeroEntry] = []
    @State private var shelves: [(title: String, source: String, items: [MediaItem])] = []
    @State private var genres: [Genre] = []
    @State private var providerLogos: [Int: String] = [:]
    @State private var upcomingSeasons: [MediaItem] = []
    @State private var loading = true
    @State private var error: String?
    @State private var scrollY: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !hero.isEmpty {
                    HeroCarousel(entries: hero, scrollY: scrollY, zoomNamespace: zoomNS)
                }

                if loading && hero.isEmpty {
                    ZStack {
                        Theme.bg
                        ProgressView()
                    }
                    .frame(height: 400)
                } else if let error, shelves.isEmpty {
                    ErrorView(message: error) { Task { await load() } }
                } else {
                    let cont = store.continueList(type)
                    ContinueShelf(title: "Продолжить просмотр", items: cont)

                    ForEach(Array(shelves.enumerated()), id: \.offset) { pair in
                        let shelf = pair.element
                        Shelf(title: shelf.title, items: shelf.items,
                              moreRoute: ListRoute(type: type, source: shelf.source, title: shelf.title))

                        // Как в вебе: после первой полки — жанры, после второй — стриминги.
                        if pair.offset == 0 {
                            GenreShelf(title: "По жанрам", genres: genres, type: type)
                        }
                        if pair.offset == 1 {
                            ProviderShelf(type: type, logos: providerLogos)
                        }
                    }

                    if type == .tv && !upcomingSeasons.isEmpty {
                        Shelf(title: "Скоро новый сезон", items: upcomingSeasons)
                    }

                    Color.clear.frame(height: 40)
                }
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top
        } action: { _, newValue in
            scrollY = newValue
        }
        .background(Theme.bg)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: HeroRoute.self) { route in
            DetailView(route: MediaRoute(type: route.type, id: route.id))
                .navigationTransition(.zoom(sourceID: route, in: zoomNS))
        }
        .task(id: type) { await load() }
        .refreshable { await load(force: true) }
    }

    private func load(force: Bool = false) async {
        if !force && !shelves.isEmpty { return }
        loading = true
        error = nil
        do {
            if type == .movie {
                async let trending = TMDB.trending(.movie)
                async let popular = TMDB.listItems(.movie, "popular")
                async let topRated = TMDB.listItems(.movie, "top_rated")
                async let nowPlaying = TMDB.listItems(.movie, "now_playing")
                async let upcoming = TMDB.listItems(.movie, "upcoming")
                async let digital = TMDB.listItems(.movie, "digital")
                async let gen = TMDB.genres(.movie)

                let (tr, pop, top, now, up, dig, g) =
                    try await (trending, popular, topRated, nowPlaying, upcoming, digital, gen)

                // «Скоро в кино» = только будущие релизы, которых нет в «Сейчас в кино».
                let today = ISO8601DateFormatter.dateOnly.string(from: Date())
                let nowIds = Set(now.map(\.id))
                let upClean = up.filter { !nowIds.contains($0.id) && ($0.releaseDate ?? "") > today }

                genres = g
                shelves = [
                    ("Популярное", "popular", pop),
                    ("Лучшее по оценкам", "top_rated", top),
                    ("Сейчас в кино", "now_playing", now),
                    ("Скоро в кино", "upcoming", upClean),
                    ("Скоро в сети", "digital", dig),
                ]
                await buildHero(Array(tr.prefix(7)))
            } else {
                async let trending = TMDB.trending(.tv)
                async let popular = TMDB.listItems(.tv, "popular")
                async let topRated = TMDB.listItems(.tv, "top_rated")
                async let onAir = TMDB.listItems(.tv, "on_air")
                async let today = TMDB.listItems(.tv, "airing_today")
                async let gen = TMDB.genres(.tv)

                let (tr, pop, top, air, tod, g) =
                    try await (trending, popular, topRated, onAir, today, gen)

                genres = g
                shelves = [
                    ("Популярные", "popular", pop),
                    ("Лучшее по оценкам", "top_rated", top),
                    ("Сейчас выходят", "on_air", air),
                    ("Премьеры сегодня", "airing_today", tod),
                ]
                await buildHero(Array(tr.prefix(7)))
                await loadUpcomingSeasons(pool: tr + pop + air)
            }
            if providerLogos.isEmpty {
                providerLogos = (try? await TMDB.providerLogos()) ?? [:]
            }
        } catch {
            self.error = "Не удалось загрузить каталог"
        }
        loading = false
    }

    private func buildHero(_ items: [MediaItem]) async {
        var entries: [HeroEntry] = []
        await withTaskGroup(of: (Int, String?).self) { group in
            for (i, item) in items.enumerated() {
                group.addTask {
                    let logo = (try? await TMDB.images(item.mediaType, item.id)).flatMap { TMDB.pickLogo($0) }
                    return (i, logo)
                }
            }
            var logos = [String?](repeating: nil, count: items.count)
            for await (i, logo) in group { logos[i] = logo }
            entries = items.enumerated().map { HeroEntry(item: $1, logoPath: logos[$0]) }
        }
        hero = entries
    }

    // «Скоро новый сезон»: сериалы, у которых следующая серия — E1 в будущем.
    private func loadUpcomingSeasons(pool: [MediaItem]) async {
        var seen = Set<Int>()
        let unique = pool.filter { seen.insert($0.id).inserted }.prefix(16)
        var found: [(String, MediaItem)] = []
        await withTaskGroup(of: (String, MediaItem)?.self) { group in
            for item in unique {
                group.addTask {
                    guard let d = try? await TMDB.details(.tv, item.id),
                          let next = d.nextEpisodeToAir,
                          next.episodeNumber == 1,
                          let air = next.airDate, !air.isEmpty,
                          air >= ISO8601DateFormatter.dateOnly.string(from: Date())
                    else { return nil }
                    return (air, d.asMedia(.tv))
                }
            }
            for await result in group {
                if let result { found.append(result) }
            }
        }
        upcomingSeasons = found.sorted { $0.0 < $1.0 }.map(\.1)
    }
}
