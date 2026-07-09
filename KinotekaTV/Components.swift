import SwiftUI

// ===========================================================
// Переиспользуемые элементы: карточки постеров, полки (rails),
// заголовки секций, карточки «Продолжить», чипы.
// ===========================================================

struct PosterCard: View {
    let item: MediaItem
    var width: CGFloat = 116

    var body: some View {
        NavigationLink(value: MediaRoute(type: item.mediaType, id: item.id)) {
            VStack(alignment: .leading, spacing: 6) {
                RemoteImage(url: TMDB.poster(item.posterPath))
                    .frame(width: width, height: width * 1.5)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Text(item.title)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let v = item.voteAverage, v > 0 {
                        Text("★ \(Fmt.rating(v))")
                    }
                    Text(Fmt.year(item.releaseDate))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .frame(width: width)
        }
        .buttonStyle(.plain)
    }
}

struct SectionHeader: View {
    let title: String
    var more: (() -> AnyView)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.bold))
            Spacer()
            if let more { more() }
        }
        .padding(.horizontal, 20)
    }
}

struct Shelf: View {
    let title: String
    let items: [MediaItem]
    var moreRoute: ListRoute? = nil

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: title, more: moreRoute.map { route in
                    { AnyView(
                        NavigationLink(value: route) {
                            Text("Все ›")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                    ) }
                })
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(items) { item in
                            PosterCard(item: item)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.top, 18)
        }
    }
}

// «Продолжить просмотр»: широкая карточка с прогресс-полосой.
struct ContinueCard: View {
    let item: ContinueItem
    @EnvironmentObject private var store: Store

    private var progress: Double {
        guard let t = item.t, let dur = item.dur, dur > 0 else { return 0 }
        return min(1, max(0, t / dur))
    }

    var body: some View {
        NavigationLink(value: MediaRoute(type: item.mediaType, id: item.id)) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottom) {
                    RemoteImage(url: TMDB.poster(item.posterPath, "w342"))
                        .frame(width: 132, height: 198)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    if progress > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.3))
                                Capsule().fill(Theme.accent)
                                    .frame(width: geo.size.width * progress)
                            }
                        }
                        .frame(height: 4)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                    }
                }
                Text(item.title ?? "")
                    .font(.caption)
                    .lineLimit(1)
                if let s = item.season, let e = item.episode, item.mediaType == .tv {
                    Text("S\(s) · E\(e)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if let t = item.t, t > 10 {
                    Text(Fmt.time(t))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 132)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                store.continueRemove(item.id)
            } label: {
                Label("Убрать из «Продолжить»", systemImage: "trash")
            }
        }
    }
}

struct ContinueShelf: View {
    let title: String
    let items: [ContinueItem]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: title)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(items) { item in
                            ContinueCard(item: item)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.top, 18)
        }
    }
}

// Жанры — стеклянные чипы.
struct GenreShelf: View {
    let title: String
    let genres: [Genre]
    let type: MediaType

    var body: some View {
        if !genres.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: title, more: {
                    AnyView(
                        NavigationLink(value: GenresRoute(type: type)) {
                            Text("Все ›")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                    )
                })
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(genres) { g in
                            NavigationLink(value: BrowseRoute(type: type, genreId: g.id, genreName: g.name)) {
                                Text(g.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.genreAccent)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular, in: .capsule)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.top, 18)
        }
    }
}

// Стриминги — ряд чипов с логотипами.
struct ProviderShelf: View {
    let type: MediaType
    let logos: [Int: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "По стримингам")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(STREAM_PROVIDERS) { p in
                        NavigationLink(value: BrowseRoute(type: type, providerId: p.id, providerName: p.name)) {
                            HStack(spacing: 8) {
                                if let logo = logos[p.id] {
                                    RemoteImage(url: TMDB.poster(logo, "w154"))
                                        .frame(width: 26, height: 26)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                Text(p.name)
                                    .font(.subheadline.weight(.medium))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular, in: .capsule)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 18)
    }
}

// Сетка постеров (страницы «Все», жанры, поиск).
struct PosterGrid: View {
    let items: [MediaItem]
    var onAppearLast: (() -> Void)? = nil

    private let columns = [GridItem(.adaptive(minimum: 106), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                NavigationLink(value: MediaRoute(type: item.mediaType, id: item.id)) {
                    VStack(alignment: .leading, spacing: 6) {
                        RemoteImage(url: TMDB.poster(item.posterPath))
                            .aspectRatio(2 / 3, contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Text(item.title)
                            .font(.caption)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            if let v = item.voteAverage, v > 0 { Text("★ \(Fmt.rating(v))") }
                            Text(Fmt.year(item.releaseDate))
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .onAppear {
                    if i >= items.count - 6 { onAppearLast?() }
                }
            }
        }
        .padding(.horizontal, 20)
    }
}

struct LoadingView: View {
    var body: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .padding(.vertical, 60)
    }
}

struct ErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Повторить", action: retry)
                .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
