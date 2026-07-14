import SwiftUI

// ===========================================================
// Детальная страница тайтла: бэкдроп с параллаксом, лого,
// мета, кнопки (смотреть/трейлер/избранное/подписка), описание,
// сезоны и серии (tv), актёры, похожее.
// ===========================================================

struct DetailView: View {
    let route: MediaRoute

    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var detail: MediaDetail?
    @State private var logoPath: String?
    @State private var stills: [String] = []
    @State private var awards: [AwardRow] = []
    @State private var trailer: VideoItem?
    @State private var error: String?
    @State private var scrollY: CGFloat = 0

    @State private var wid: WatchId?
    @State private var widResolved = false

    @State private var selectedSeason: Int = 1
    @State private var episodes: [EpisodeInfo] = []

    @State private var showFolderSheet = false
    @State private var showTrailer = false

    private var media: MediaItem? { detail?.asMedia(route.type) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                if let detail {
                    content(detail)
                } else if let error {
                    ErrorView(message: error) { Task { await load() } }
                } else {
                    LoadingView()
                }

                Color.clear.frame(height: 50)
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
        .overlay(alignment: .topLeading) { floatingBar }
        .task { await load() }
        .sheet(isPresented: $showFolderSheet) {
            if let media {
                FolderSheet(item: media)
                    .presentationDetents([.medium])
            }
        }
        .fullScreenCover(isPresented: $showTrailer) {
            if let key = trailer?.key {
                TrailerScreen(youtubeKey: key)
            }
        }
    }

    // ---- Плавающие «Назад» / «Поделиться» (стекло) ----
    private var floatingBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)

            Spacer()

            if let detail {
                ShareLink(item: URL(string: "https://kinoteka.pages.dev/#\(route.type.rawValue)/\(route.id)")!,
                          subject: Text(detail.displayTitle)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // ---- Бэкдроп с параллаксом ----
    private var header: some View {
        let h = UIScreen.main.bounds.height * 0.48
        return ZStack(alignment: .bottom) {
            RemoteImage(url: TMDB.backdrop(detail?.backdropPath, "w1280") ?? TMDB.poster(detail?.posterPath, "w780"))
                // Ширину ограничиваем контейнером: .fill-картинка иначе выходит шире
                // экрана (height*aspect) и раздувает весь стек → контент уезжает влево.
                .frame(height: h)
                .containerRelativeFrame(.horizontal)
                .clipped()
                .offset(y: scrollY > 0 ? scrollY * 0.4 : 0)
                .scaleEffect(scrollY < 0 ? 1 + min(-scrollY, 400) / h : 1 + min(max(scrollY, 0), 700) / 3500,
                             anchor: .top)

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.35),
                    .init(color: Theme.bg.opacity(0.6), location: 0.75),
                    .init(color: Theme.bg, location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )

            VStack(spacing: 10) {
                if let logoPath {
                    RemoteImage(url: TMDB.poster(logoPath, "w500"), contentMode: .fit)
                        .frame(maxWidth: 280, maxHeight: 120)
                        .shadow(color: .black.opacity(0.55), radius: 10, y: 2)
                } else if let detail {
                    Text(detail.displayTitle)
                        .font(.system(size: 32, weight: .heavy))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .shadow(color: .black.opacity(0.6), radius: 8, y: 2)
                }
            }
            .padding(.bottom, 14)
        }
        .frame(height: h)
        .clipped()
    }

    // ---- Контент ----
    @ViewBuilder
    private func content(_ d: MediaDetail) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            metaRow(d)
                .frame(maxWidth: .infinity)

            releaseBox(d)

            actionButtons(d)

            if let tagline = d.tagline, !tagline.isEmpty {
                Text(tagline)
                    .font(.subheadline.italic())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            }

            if let overview = d.overview, !overview.isEmpty {
                Text(overview)
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.9))
                    .lineSpacing(4)
                    .padding(.horizontal, 20)
            }

            if !genreChips(d).isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(genreChips(d), id: \.id) { g in
                            NavigationLink(value: BrowseRoute(type: route.type, genreId: g.id, genreName: g.name)) {
                                Text(g.name)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Theme.genreAccent)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular, in: .capsule)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .padding(.top, 4)

        if route.type == .tv {
            episodesSection(d)
            tvInfoBlock(d)
        }

        if let cast = d.credits?.cast, !cast.isEmpty {
            castShelf(Array(cast.prefix(20)))
        }

        stillsShelf()

        AwardsSection(awards: awards)

        if route.type == .movie {
            financeBlock(d)
        }

        let similar = (d.similar?.results ?? []).map { $0.asMedia(fallbackType: route.type) }.filter { !$0.title.isEmpty }
        Shelf(title: "Похожее", items: similar)
    }

    // ---- Релиз-бокс: когда в кино / когда в сети / когда следующая серия + подписка ----
    @ViewBuilder
    private func releaseBox(_ d: MediaDetail) -> some View {
        let rows = releaseRows(d)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Label {
                        Text(row.text)
                            .font(.subheadline.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: row.icon).foregroundStyle(Theme.accent)
                    }
                }
                if let media {
                    Button {
                        store.subToggle(media)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: store.isSub(d.id, route.type) ? "bell.fill" : "bell")
                            Text(store.isSub(d.id, route.type) ? "Вы подписаны" : "Сообщить о выходе")
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                    }
                    .buttonStyle(.glass)
                    .tint(store.isSub(d.id, route.type) ? Theme.accent : nil)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 20)
        }
    }

    private struct ReleaseRow { let icon: String; let text: String }

    private func releaseRows(_ d: MediaDetail) -> [ReleaseRow] {
        var rows: [ReleaseRow] = []
        if route.type == .movie {
            // Показываем только пока фильм ещё не вышел в сети.
            let digital = d.digitalDate
            let notYetOnline = digital == nil || Fmt.isFuture(digital)
            guard notYetOnline else { return [] }
            if Fmt.isFuture(d.releaseDate), let r = d.releaseDate {
                rows.append(.init(icon: "film", text: "В кино с " + Fmt.date(r)))
            }
            if let dig = digital {
                rows.append(.init(icon: "globe", text: "Онлайн с " + Fmt.date(dig)))
            } else {
                rows.append(.init(icon: "globe", text: "Онлайн: дата уточняется"))
            }
        } else {
            if let next = d.nextEpisodeToAir, let air = next.airDate, !air.isEmpty {
                let se = next.seasonNumber.map { s in "S\(s)" + (next.episodeNumber.map { "·E\($0)" } ?? "") } ?? ""
                rows.append(.init(icon: "calendar", text: "Следующая серия \(se) — " + Fmt.date(air)))
            }
        }
        return rows
    }

    // ---- Кадры из фильма/сериала ----
    @ViewBuilder
    private func stillsShelf() -> some View {
        if !stills.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Кадры")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(stills.prefix(20), id: \.self) { path in
                            RemoteImage(url: TMDB.backdrop(path, "w780"))
                                .frame(width: 240, height: 135)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.top, 24)
        }
    }

    // ---- О сериале ----
    @ViewBuilder
    private func tvInfoBlock(_ d: MediaDetail) -> some View {
        let rows = tvInfoRows(d)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "О сериале")
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                        HStack(alignment: .top) {
                            Text(row.0).foregroundStyle(.secondary)
                            Spacer(minLength: 16)
                            Text(row.1).multilineTextAlignment(.trailing)
                        }
                        .font(.subheadline)
                        .padding(.vertical, 10)
                        if i < rows.count - 1 { Divider().overlay(Color.white.opacity(0.08)) }
                    }
                }
                .padding(.horizontal, 16)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 20)
            }
            .padding(.top, 24)
        }
    }

    private func tvInfoRows(_ d: MediaDetail) -> [(String, String)] {
        var rows: [(String, String)] = []
        if let s = statusRu(d.status) { rows.append(("Статус", s)) }
        if let n = d.numberOfSeasons, n > 0 { rows.append(("Сезонов", "\(n)")) }
        if let e = d.numberOfEpisodes, e > 0 { rows.append(("Серий", "\(e)")) }
        if let creators = d.createdBy, !creators.isEmpty {
            rows.append(("Создатели", creators.map(\.name).joined(separator: ", ")))
        }
        if let nets = d.networks, !nets.isEmpty {
            rows.append(("Сеть", nets.map(\.name).joined(separator: ", ")))
        }
        if let air = d.firstAirDate, !air.isEmpty { rows.append(("Премьера", Fmt.date(air))) }
        return rows
    }

    private func statusRu(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        switch s {
        case "Returning Series": return "Выходит"
        case "Ended": return "Завершён"
        case "Canceled": return "Закрыт"
        case "In Production": return "В производстве"
        case "Planned": return "Запланирован"
        default: return s
        }
    }

    // ---- Сборы (бюджет / кассовые сборы) ----
    @ViewBuilder
    private func financeBlock(_ d: MediaDetail) -> some View {
        let rows: [(String, String)] = [
            (d.budget ?? 0) > 0 ? ("Бюджет", Fmt.money(d.budget)) : nil,
            (d.revenue ?? 0) > 0 ? ("Сборы в мире", Fmt.money(d.revenue)) : nil,
        ].compactMap { $0 }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Сборы")
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                        HStack {
                            Text(row.0).foregroundStyle(.secondary)
                            Spacer()
                            Text(row.1).fontWeight(.semibold)
                        }
                        .font(.subheadline)
                        .padding(.vertical, 10)
                        if i < rows.count - 1 { Divider().overlay(Color.white.opacity(0.08)) }
                    }
                }
                .padding(.horizontal, 16)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 20)
            }
            .padding(.top, 24)
        }
    }

    private func genreChips(_ d: MediaDetail) -> [Genre] { d.genres ?? [] }

    private func metaRow(_ d: MediaDetail) -> some View {
        HStack(spacing: 14) {
            if let v = d.voteAverage, v > 0 {
                Label(Fmt.rating(v), systemImage: "star.fill")
                    .foregroundStyle(Theme.accent)
            }
            Text(Fmt.year(d.date))
            if route.type == .movie {
                if let r = d.runtime, r > 0 { Text(Fmt.runtime(r)) }
            } else if let s = d.numberOfSeasons, s > 0 {
                Text(seasonsWord(s))
            }
            if let cert = d.certification(route.type) {
                Text(cert)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.6), lineWidth: 1))
            }
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
    }

    private func seasonsWord(_ n: Int) -> String {
        let mod10 = n % 10, mod100 = n % 100
        if mod10 == 1 && mod100 != 11 { return "\(n) сезон" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "\(n) сезона" }
        return "\(n) сезонов"
    }

    // ---- Кнопки действий ----
    private func actionButtons(_ d: MediaDetail) -> some View {
        let cont = store.continueGet(d.id)
        let tvResume: ContinueItem? = (route.type == .tv && cont?.season != nil && cont?.episode != nil) ? cont : nil
        let movieResume: ContinueItem? = (route.type == .movie && (cont?.t ?? 0) > 10) ? cont : nil

        var watchLabel = "Смотреть онлайн"
        if let r = tvResume, let s = r.season, let e = r.episode {
            watchLabel = "Продолжить · S\(s)·E\(e)" + ((r.t ?? 0) > 10 ? " · \(Fmt.time(r.t ?? 0))" : "")
        } else if let r = movieResume, let t = r.t {
            watchLabel = "Продолжить · \(Fmt.time(t))"
        }

        return VStack(spacing: 10) {
            Button {
                openPlayer(season: tvResume?.season, episode: tvResume?.episode, resumeAt: movieResume?.t)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text(widResolved && wid == nil ? "Онлайн-версия не найдена" : watchLabel)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
                .foregroundStyle(Theme.onAccent)   // тёмный текст поверх лаймовой кнопки
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.accent)
            .disabled(widResolved && wid == nil)

            HStack(spacing: 10) {
                if trailer != nil {
                    Button {
                        showTrailer = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "movieclapper")
                            Text("Трейлер")
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                    }
                    .buttonStyle(.glass)
                }

                Button {
                    showFolderSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: store.isFavorite(d.id, route.type) ? "heart.fill" : "heart")
                        Text("Избранное")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                }
                .buttonStyle(.glass)

                Button {
                    if let media { store.subToggle(media) }
                } label: {
                    Image(systemName: store.isSub(d.id, route.type) ? "bell.fill" : "bell")
                        .frame(width: 52, height: 44)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(.horizontal, 20)
    }

    private func openPlayer(season: Int?, episode: Int?, resumeAt: Double?) {
        guard let media, let wid else { return }
        PlayerCoordinator.shared.open(PlayerLaunch(
            media: media, wid: wid,
            originalTitle: detail?.title ?? detail?.name,
            season: season, episode: episode, resumeAt: resumeAt
        ))
    }

    // ---- Сезоны и серии ----
    @ViewBuilder
    private func episodesSection(_ d: MediaDetail) -> some View {
        let seasons = (d.seasons ?? []).filter { $0.seasonNumber > 0 }
        if !seasons.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Серии")
                        .font(.title3.weight(.bold))
                    Spacer()
                    Menu {
                        ForEach(seasons) { s in
                            Button("Сезон \(s.seasonNumber)") {
                                selectedSeason = s.seasonNumber
                                Task { await loadSeason(s.seasonNumber) }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Сезон \(selectedSeason)")
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .padding(.horizontal, 20)

                if episodes.isEmpty {
                    LoadingView().frame(height: 80)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(episodes) { ep in
                            episodeRow(ep)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.top, 24)
        }
    }

    private func episodeRow(_ ep: EpisodeInfo) -> some View {
        Button {
            openPlayer(season: selectedSeason, episode: ep.episodeNumber, resumeAt: nil)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RemoteImage(url: TMDB.backdrop(ep.stillPath, "w300"))
                        .frame(width: 130, height: 74)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Image(systemName: "play.fill")
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.45), in: .circle)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(ep.episodeNumber). \(ep.name ?? "Серия \(ep.episodeNumber)")")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    HStack(spacing: 8) {
                        if let air = ep.airDate, !air.isEmpty { Text(Fmt.dateShort(air)) }
                        if let r = ep.runtime, r > 0 { Text("\(r) мин") }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if let o = ep.overview, !o.isEmpty {
                        Text(o)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    // ---- Актёры ----
    private func castShelf(_ cast: [CastMember]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "В ролях")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(cast) { c in
                        NavigationLink(value: PersonRoute(id: c.id)) {
                            VStack(spacing: 6) {
                                RemoteImage(url: TMDB.profile(c.profilePath))
                                    .frame(width: 84, height: 84)
                                    .clipShape(Circle())
                                Text(c.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                Text(c.character ?? "")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 92)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 24)
    }

    // ---- Загрузка ----
    private func load() async {
        do {
            let d = try await TMDB.details(route.type, route.id)
            detail = d
            selectedSeason = 1

            let imgs = try? await TMDB.images(route.type, route.id)
            logoPath = imgs.flatMap { TMDB.pickLogo($0) }
            // Кадры: бэкдропы без логотипа/текста (язык null), запасной вариант — любые.
            let backs = imgs?.backdrops ?? []
            let clean = backs.filter { $0.iso6391 == nil }.compactMap(\.filePath)
            stills = (clean.isEmpty ? backs.compactMap(\.filePath) : clean)
            trailer = pickTrailer((try? await TMDB.videos(route.type, route.id)) ?? [])

            if route.type == .tv {
                let firstSeason = (d.seasons ?? []).filter { $0.seasonNumber > 0 }.first?.seasonNumber ?? 1
                let cont = store.continueGet(d.id)
                selectedSeason = cont?.season ?? firstSeason
                await loadSeason(selectedSeason)
            }

            // Идентификатор для балансеров: imdb → kp (Wikidata).
            if let imdb = d.externalIds?.imdbId, imdb.hasPrefix("tt") {
                wid = WatchId(imdb: imdb, kp: nil)
            } else if let kp = await TMDB.kinopoiskId(d.externalIds?.wikidataId) {
                wid = WatchId(imdb: nil, kp: kp)
            } else {
                wid = nil
            }
            widResolved = true

            // Награды (Wikidata) — грузим последними, не блокируя основной контент.
            if let wdid = d.externalIds?.wikidataId, !wdid.isEmpty {
                awards = await Wikidata.titleAwards(wdid)
            }
        } catch {
            self.error = "Не удалось загрузить"
        }
    }

    private func loadSeason(_ n: Int) async {
        episodes = (try? await TMDB.season(route.id, n)) ?? []
    }

    private func pickTrailer(_ videos: [VideoItem]) -> VideoItem? {
        let yt = videos.filter { $0.site == "YouTube" && $0.key != nil }
        let trailers = yt.filter { $0.type == "Trailer" }
        return trailers.first { $0.iso6391 == "ru" }
            ?? trailers.first { $0.official == true }
            ?? trailers.first
            ?? yt.first
    }
}

// ===========================================================
// Шторка выбора папок избранного.
// ===========================================================

struct FolderSheet: View {
    let item: MediaItem

    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var newFolder = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.folders, id: \.self) { folder in
                    let selected = store.itemFolders(item.id, item.mediaType).contains(folder)
                    Button {
                        var fs = store.itemFolders(item.id, item.mediaType)
                        if selected { fs.removeAll { $0 == folder } }
                        else { fs.append(folder) }
                        store.setFolders(item, fs)
                    } label: {
                        HStack {
                            Text(folder)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }

                HStack {
                    TextField("Новая папка", text: $newFolder)
                    Button("Создать") {
                        store.createFolder(newFolder)
                        newFolder = ""
                    }
                    .disabled(newFolder.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Папки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}
