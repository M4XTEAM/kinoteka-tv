import SwiftUI

// ===========================================================
// ИИ-ассистент (Gemini через /api/ai): чат в шторке,
// actions → карточки тайтлов/персон, чипы-подсказки.
// ===========================================================

struct AIChatView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var thread: [AIMessage] = []
    @State private var input = ""
    @State private var busy = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            if thread.isEmpty {
                                greeting
                            }
                            ForEach(thread) { msg in
                                bubble(msg)
                            }
                            if busy {
                                HStack(spacing: 8) {
                                    Image(systemName: "sparkles")
                                        .foregroundStyle(Theme.accent)
                                    ProgressView()
                                }
                                .padding(.horizontal, 20)
                            }
                            Color.clear.frame(height: 8).id("bottom")
                        }
                        .padding(.top, 14)
                    }
                    .onChange(of: thread.count) { _, _ in
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }

                composer
            }
            .background(Theme.bg)
            .navigationTitle("ИИ-ассистент")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Новый диалог") { thread = [] }
                        .disabled(thread.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .navigationDestination(for: MediaRoute.self) { DetailView(route: $0) }
            .navigationDestination(for: PersonRoute.self) { PersonView(personId: $0.id) }
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Theme.accent)
                Text("Привет! Опишите настроение, сюжет, жанр или актёра — подберу, что посмотреть.")
                    .font(.subheadline)
            }
            .padding(14)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))

            ForEach(["Хочу что-то атмосферное и медленное", "Комедии с Джимом Керри", "Лучшая фантастика за 5 лет"], id: \.self) { chip in
                Button {
                    send(chip)
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

    @ViewBuilder
    private func bubble(_ msg: AIMessage) -> some View {
        VStack(alignment: msg.role == "user" ? .trailing : .leading, spacing: 10) {
            HStack {
                if msg.role == "user" { Spacer(minLength: 60) }
                Text(msg.text)
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        msg.role == "user" ? AnyShapeStyle(Theme.accent.opacity(0.9)) : AnyShapeStyle(.ultraThinMaterial),
                        in: .rect(cornerRadius: 16)
                    )
                    .foregroundStyle(msg.role == "user" ? .black : .primary)
                if msg.role != "user" { Spacer(minLength: 60) }
            }

            if !msg.cards.isEmpty || !msg.persons.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(msg.persons) { p in
                            NavigationLink(value: PersonRoute(id: p.id)) {
                                VStack(spacing: 6) {
                                    RemoteImage(url: TMDB.profile(p.profilePath))
                                        .frame(width: 84, height: 84)
                                        .clipShape(Circle())
                                    Text(p.name)
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                                .frame(width: 92)
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(msg.cards) { item in
                            PosterCard(item: item, width: 104)
                        }
                    }
                }
            }

            if !msg.chips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(msg.chips, id: \.self) { chip in
                            Button {
                                send(chip)
                            } label: {
                                Text(chip)
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.interactive(), in: .capsule)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Спросите про кино…", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .rect(cornerRadius: 20))

            Button {
                send(input)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.glassProminent)
            .disabled(busy || input.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func send(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !busy else { return }
        input = ""
        thread.append(AIMessage(role: "user", text: t))
        busy = true
        Task {
            let history = thread.suffix(10).map { ["role": $0.role, "text": $0.text] }
            let resp = await Backend.ai(messages: Array(history))
            var msg = AIMessage(role: "model", text: resp?.reply ?? "Не получилось ответить — попробуйте ещё раз.")
            msg.chips = resp?.chips ?? []
            if let actions = resp?.actions {
                let (cards, persons) = await resolveActions(actions)
                msg.cards = cards
                msg.persons = persons
            }
            thread.append(msg)
            busy = false
        }
    }

    // ---- Исполнитель actions (как aiRunActions в вебе) ----
    private func resolveActions(_ actions: [AIAction]) async -> ([MediaItem], [PersonLite]) {
        var cards: [MediaItem] = []
        var persons: [PersonLite] = []

        for a in actions {
            switch a.kind {
            case "titles":
                for t in (a.titles ?? []).prefix(12) {
                    guard let name = t.title, !name.isEmpty else { continue }
                    if let found = (try? await TMDB.search(name))?.results?
                        .first(where: { ($0.mediaType == "movie" || $0.mediaType == "tv") && $0.posterPath != nil }) {
                        cards.append(found.asMedia(fallbackType: .movie))
                    }
                }
            case "discover":
                let type: MediaType = (a.media == "tv") ? .tv : .movie
                if let personName = a.person, !personName.isEmpty {
                    if let p = (try? await TMDB.searchPerson(personName))?.first,
                       let credits = (try? await TMDB.person(p.id))?.combinedCredits {
                        let all = (credits.cast ?? []).map(\.asMedia)
                            .filter { $0.posterPath != nil && $0.mediaType == type }
                        cards.append(contentsOf: filterYears(all, a).prefix(12))
                        persons.append(p)
                    }
                } else {
                    var params: [String: String] = ["sort_by": sortParam(a.sort)]
                    if let g = a.genre, !g.isEmpty,
                       let genre = (try? await TMDB.genres(type))?.first(where: { $0.name.lowercased().contains(g.lowercased()) }) {
                        params["with_genres"] = String(genre.id)
                    }
                    let dateKey = type == .movie ? "primary_release_date" : "first_air_date"
                    if let y = a.yearFrom { params["\(dateKey).gte"] = "\(y)-01-01" }
                    if let y = a.yearTo { params["\(dateKey).lte"] = "\(y)-12-31" }
                    if params["sort_by"]?.contains("vote_average") == true { params["vote_count.gte"] = "200" }
                    let page = try? await TMDB.discover(type, params: params)
                    cards.append(contentsOf: (page?.results ?? []).map { $0.asMedia(fallbackType: type) }
                        .filter { $0.posterPath != nil }.prefix(12))
                }
            case "open":
                if a.target == "person", let name = a.name {
                    if let p = (try? await TMDB.searchPerson(name))?.first {
                        persons.append(p)
                    } else {
                        // Фикс суффиксов: «Дауни-младший» → без суффикса.
                        let stripped = name.replacingOccurrences(
                            of: "[\\s-]*(младший|мл\\.?|старший|ст\\.?|jr\\.?|sr\\.?)$",
                            with: "", options: [.regularExpression, .caseInsensitive])
                        if stripped != name, let p = (try? await TMDB.searchPerson(stripped))?.first {
                            persons.append(p)
                        }
                    }
                } else if let name = a.name {
                    if let found = (try? await TMDB.search(name))?.results?
                        .first(where: { ($0.mediaType == "movie" || $0.mediaType == "tv") && $0.posterPath != nil }) {
                        cards.append(found.asMedia(fallbackType: .movie))
                    }
                }
            default:
                break
            }
        }

        // Дедуп, ≤20.
        var seen = Set<String>()
        let deduped = cards.filter { seen.insert("\($0.mediaType.rawValue)-\($0.id)").inserted }
        return (Array(deduped.prefix(20)), persons)
    }

    private func sortParam(_ sort: String?) -> String {
        switch sort {
        case "rating": return "vote_average.desc"
        case "new": return "primary_release_date.desc"
        default: return "popularity.desc"
        }
    }

    private func filterYears(_ items: [MediaItem], _ a: AIAction) -> [MediaItem] {
        items.filter { item in
            guard let yStr = item.releaseDate?.prefix(4), let y = Int(yStr) else { return a.yearFrom == nil && a.yearTo == nil }
            if let from = a.yearFrom, y < from { return false }
            if let to = a.yearTo, y > to { return false }
            return true
        }
        .sorted { ($0.voteAverage ?? 0) > ($1.voteAverage ?? 0) }
    }
}
