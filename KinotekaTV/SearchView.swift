import SwiftUI

// ===========================================================
// Поиск: мгновенный TMDB-поиск по буквам + ИИ-ассистент
// (Gemini через /api/ai) в шторке.
// ===========================================================

struct SearchView: View {
    @State private var query = ""
    @State private var results: [TMDBResult] = []
    @State private var segment = "all"   // all | movie | tv | person
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var showAI = false

    private var filtered: [TMDBResult] {
        switch segment {
        case "movie": return results.filter { $0.mediaType == "movie" }
        case "tv": return results.filter { $0.mediaType == "tv" }
        case "person": return results.filter { $0.mediaType == "person" }
        default: return results
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    aiGreeting
                } else if searching && results.isEmpty {
                    LoadingView()
                } else if results.isEmpty {
                    Text("Ничего не найдено")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else {
                    segmentPicker
                    resultsGrid
                }
                Color.clear.frame(height: 30)
            }
            .padding(.top, 8)
        }
        .background(Theme.bg)
        .navigationTitle("Поиск")
        .searchable(text: $query, prompt: "Фильмы, сериалы, люди")
        .onChange(of: query) { _, newValue in
            scheduleSearch(newValue)
        }
        .sheet(isPresented: $showAI) {
            AIChatView()
                .presentationDetents([.large])
        }
    }

    private var aiGreeting: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                showAI = true
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ИИ-ассистент")
                            .font(.headline)
                        Text("Опишите настроение, сюжет или актёра — подберу, что посмотреть.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                }
                .padding(16)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["Что-то лёгкое на вечер", "Фильм как «Интерстеллар»", "Лучшие триллеры 2020-х", "Сериал на выходные"], id: \.self) { chip in
                        Button {
                            showAI = true
                        } label: {
                            Text(chip)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 13)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 10)
    }

    private var segmentPicker: some View {
        Picker("Тип", selection: $segment) {
            Text("Все").tag("all")
            Text("Фильмы").tag("movie")
            Text("Сериалы").tag("tv")
            Text("Люди").tag("person")
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
    }

    private var resultsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 106), spacing: 12)], spacing: 18) {
            ForEach(Array(filtered.enumerated()), id: \.offset) { _, r in
                if r.mediaType == "person" {
                    NavigationLink(value: PersonRoute(id: r.id)) {
                        VStack(spacing: 6) {
                            RemoteImage(url: TMDB.profile(r.profilePath, "w185"))
                                .aspectRatio(2 / 3, contentMode: .fill)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            Text(r.name ?? "")
                                .font(.caption)
                                .lineLimit(1)
                            Text(r.knownForDepartment == "Directing" ? "Режиссёр" : "Актёр")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    let m = r.asMedia(fallbackType: .movie)
                    NavigationLink(value: MediaRoute(type: m.mediaType, id: m.id)) {
                        VStack(alignment: .leading, spacing: 6) {
                            RemoteImage(url: TMDB.poster(m.posterPath))
                                .aspectRatio(2 / 3, contentMode: .fill)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            Text(m.title)
                                .font(.caption)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                if let v = m.voteAverage, v > 0 { Text("★ \(Fmt.rating(v))") }
                                Text(Fmt.year(m.releaseDate))
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func scheduleSearch(_ q: String) {
        searchTask?.cancel()
        let query = q.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            results = []
            return
        }
        searching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            var page = (try? await TMDB.search(query))?.results ?? []
            // Фикс «ё»: TMDB не находит по «е» — пробуем замену.
            if page.isEmpty, query.contains("е") {
                let yo = query.replacingOccurrences(of: "е", with: "ё")
                page = (try? await TMDB.search(yo))?.results ?? []
            }
            guard !Task.isCancelled else { return }
            results = page.filter { ($0.title ?? $0.name)?.isEmpty == false }
            searching = false
        }
    }
}
