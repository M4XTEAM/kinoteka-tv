import SwiftUI

// ===========================================================
// Подписки: расписание новых серий подписанных сериалов,
// подписки-карточки, каталоги стримингов, аккаунт (выход).
// ===========================================================

struct SubscriptionsView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var appState: AppState

    @State private var schedule: [(item: MediaItem, line: String, date: String?)] = []
    @State private var providerLogos: [Int: String] = [:]
    @State private var loadedFor: Int = -1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Расписание ближайших серий.
                if !schedule.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Скоро выходят")
                        VStack(spacing: 10) {
                            ForEach(Array(schedule.enumerated()), id: \.offset) { _, entry in
                                NavigationLink(value: MediaRoute(type: entry.item.mediaType, id: entry.item.id)) {
                                    HStack(spacing: 12) {
                                        RemoteImage(url: TMDB.poster(entry.item.posterPath, "w154"))
                                            .frame(width: 52, height: 78)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(entry.item.title)
                                                .font(.subheadline.weight(.semibold))
                                                .lineLimit(1)
                                                .foregroundStyle(.primary)
                                            Text(entry.line)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if let d = entry.date {
                                            Text(Fmt.dateShort(d))
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(Theme.accent)
                                        }
                                    }
                                    .padding(10)
                                }
                                .buttonStyle(.plain)
                                .glassEffect(.regular, in: .rect(cornerRadius: 14))
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.top, 18)
                }

                // Мои подписки.
                let subs = store.subs
                if !subs.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Мои подписки")
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 12) {
                                ForEach(subs) { sub in
                                    let type = MediaType(rawValue: sub.type ?? "tv") ?? .tv
                                    NavigationLink(value: MediaRoute(type: type, id: sub.id)) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            RemoteImage(url: TMDB.poster(sub.posterPath))
                                                .frame(width: 116, height: 174)
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                            Text(sub.name ?? "")
                                                .font(.caption)
                                                .lineLimit(1)
                                        }
                                        .frame(width: 116)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            let item = MediaItem(id: sub.id, mediaType: type, title: sub.name ?? "",
                                                                 posterPath: sub.posterPath, backdropPath: nil,
                                                                 voteAverage: nil, releaseDate: nil)
                                            store.subToggle(item)
                                        } label: {
                                            Label("Отписаться", systemImage: "bell.slash")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.top, 18)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "bell")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Подпишитесь на сериал или фильм колокольчиком — здесь появится расписание новинок")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                    .padding(.bottom, 30)
                }

                // Стриминги.
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Стриминги")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        ForEach(STREAM_PROVIDERS) { p in
                            NavigationLink(value: BrowseRoute(type: .movie, providerId: p.id, providerName: p.name)) {
                                HStack(spacing: 10) {
                                    if let logo = providerLogos[p.id] {
                                        RemoteImage(url: TMDB.poster(logo, "w154"))
                                            .frame(width: 34, height: 34)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    Text(p.name)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(12)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.top, 18)

                // Аккаунт.
                accountCard
                    .padding(.top, 24)

                Color.clear.frame(height: 40)
            }
            .padding(.top, 8)
        }
        .background(Theme.bg)
        .navigationTitle("Подписки")
        .task {
            if providerLogos.isEmpty {
                providerLogos = (try? await TMDB.providerLogos()) ?? [:]
            }
            await loadSchedule()
        }
        .refreshable { await loadSchedule(force: true) }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.login ?? "Аккаунт")
                        .font(.headline)
                    if let exp = appState.expiresAt {
                        let days = Int((exp / 1000 - Date().timeIntervalSince1970) / 86400)
                        Text(days > 0 ? "Подписка: ещё \(days) дн." : "Подписка истекла")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Безлимитный доступ")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Выйти", role: .destructive) {
                    Task { await appState.logout() }
                }
                .buttonStyle(.glass)
            }
            .padding(14)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 20)
    }

    // Ближайшие серии подписанных сериалов + цифровые релизы фильмов.
    private func loadSchedule(force: Bool = false) async {
        let subs = store.subs
        let key = subs.map(\.id).reduce(0, &+)
        if !force && key == loadedFor { return }
        loadedFor = key

        var out: [(item: MediaItem, line: String, date: String?)] = []
        await withTaskGroup(of: (MediaItem, String, String?)?.self) { group in
            for sub in subs.prefix(24) {
                let type = MediaType(rawValue: sub.type ?? "tv") ?? .tv
                group.addTask {
                    guard let d = try? await TMDB.details(type, sub.id) else { return nil }
                    let media = d.asMedia(type)
                    if type == .tv {
                        guard let next = d.nextEpisodeToAir, let air = next.airDate, !air.isEmpty else { return nil }
                        let s = next.seasonNumber ?? 0
                        let e = next.episodeNumber ?? 0
                        return (media, "S\(s) · E\(e)", air)
                    } else {
                        guard let rel = d.releaseDates?.results?
                            .first(where: { $0.iso31661 == "US" })?
                            .releaseDates?
                            .first(where: { $0.type == 4 || $0.type == 6 })?
                            .releaseDate
                        else { return nil }
                        let day = String(rel.prefix(10))
                        guard day >= ISO8601DateFormatter.dateOnly.string(from: Date()) else { return nil }
                        return (media, "Выходит в сети", day)
                    }
                }
            }
            for await entry in group {
                if let entry { out.append((item: entry.0, line: entry.1, date: entry.2)) }
            }
        }
        schedule = out.sorted { ($0.date ?? "") < ($1.date ?? "") }
    }
}
