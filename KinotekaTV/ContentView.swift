import SwiftUI

struct ContentView: View {
    @State private var rows: [HomeRow] = []
    @State private var query = ""
    @State private var results: [TMDBItem] = []
    @State private var loading = true

    var body: some View {
        NavigationStack {
            Group {
                if query.count > 1 {
                    List(results) { item in NavigationLink(value: item) { ItemRow(item: item) } }
                        .listStyle(.plain)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            ForEach(rows) { row in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(row.title).font(.title3.bold()).padding(.horizontal)
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 12) {
                                            ForEach(row.items) { item in
                                                NavigationLink(value: item) { Poster(item: item) }
                                            }
                                        }.padding(.horizontal)
                                    }
                                }
                            }
                        }.padding(.vertical)
                    }
                    .overlay { if loading && rows.isEmpty { ProgressView() } }
                }
            }
            .navigationTitle("Кинотека")
            .navigationDestination(for: TMDBItem.self) { DetailView(item: $0) }
            .searchable(text: $query, prompt: "Фильм или сериал")
            .onSubmit(of: .search) { Task { results = await TMDB.search(query) } }
            .task { rows = await TMDB.home(); loading = false }
        }
    }
}

struct Poster: View {
    let item: TMDBItem
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AsyncImage(url: item.posterURL) { $0.resizable().aspectRatio(contentMode: .fill) }
                placeholder: { Color.gray.opacity(0.2) }
                .frame(width: 110, height: 165).clipShape(RoundedRectangle(cornerRadius: 10))
            Text(item.title).font(.caption).lineLimit(1).frame(width: 110, alignment: .leading)
        }
    }
}

struct ItemRow: View {
    let item: TMDBItem
    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: item.posterURL) { $0.resizable().aspectRatio(contentMode: .fill) }
                placeholder: { Color.gray.opacity(0.2) }
                .frame(width: 46, height: 69).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.headline)
                Text("\(item.isTV ? "Сериал" : "Фильм") · \(item.year)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct DetailView: View {
    let item: TMDBItem
    @State private var overview = ""
    @State private var backdrop: URL?
    @State private var seasonCount = 1
    @State private var season = 1
    @State private var episode = 1
    @State private var extracting = false
    @State private var error: String?
    @State private var voices: [VoiceTrack] = []
    @State private var showPicker = false
    @State private var webEmbed: String?
    @State private var showWeb = false
    @StateObject private var holder = ExtractorHolder()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AsyncImage(url: backdrop) { $0.resizable().aspectRatio(contentMode: .fill) }
                    placeholder: { Color.gray.opacity(0.15) }
                    .frame(height: 210).frame(maxWidth: .infinity).clipped()

                VStack(alignment: .leading, spacing: 12) {
                    Text(item.title).font(.title2.bold())
                    Text("\(item.isTV ? "Сериал" : "Фильм") · \(item.year)").foregroundStyle(.secondary)

                    if item.isTV {
                        Stepper("Сезон: \(season)", value: $season, in: 1...max(1, seasonCount))
                        Stepper("Серия: \(episode)", value: $episode, in: 1...200)
                    }

                    HStack(spacing: 12) {
                        Button { Task { await openWeb() } } label: {
                            Label("Смотреть", systemImage: "play.fill").frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent)
                        Button { Task { await extractForTV() } } label: {
                            Label("Apple TV", systemImage: "appletv").frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered)
                    }
                    if extracting { HStack { ProgressView(); Text("Извлечение потока…").foregroundStyle(.secondary) } }
                    if let error { Text(error).foregroundStyle(.red).font(.footnote) }

                    if !overview.isEmpty { Text(overview).font(.callout).foregroundStyle(.secondary) }
                }.padding(.horizontal)
            }
        }
        .navigationTitle(item.title).navigationBarTitleDisplayMode(.inline)
        .task { let d = await TMDB.details(for: item); overview = d.0; backdrop = item.backdropURL ?? URL(string: "https://image.tmdb.org/t/p/w780\(d.1 ?? "")"); seasonCount = d.2 }
        .sheet(isPresented: $showPicker) { VoicePicker(voices: voices) }
        .fullScreenCover(isPresented: $showWeb) {
            ZStack(alignment: .topTrailing) {
                if let webEmbed { WebPlayerScreen(embed: webEmbed) } else { Color.black.ignoresSafeArea() }
                Button { showWeb = false } label: { Image(systemName: "xmark.circle.fill").font(.title).padding() }
                    .tint(.white)
            }
        }
    }

    private func openWeb() async {
        error = nil; extracting = true; defer { extracting = false }
        guard let imdb = await TMDB.imdbID(for: item) else { error = ExtractError.noImdb.errorDescription; return }
        guard let embed = await holder.extractor.embedURL(imdb: imdb, isTV: item.isTV, season: season, episode: episode) else {
            error = ExtractError.noAlloha.errorDescription; return
        }
        webEmbed = embed; showWeb = true
    }

    private func extractForTV() async {
        error = nil; extracting = true; defer { extracting = false }
        guard let imdb = await TMDB.imdbID(for: item) else { error = ExtractError.noImdb.errorDescription; return }
        do {
            let res = try await holder.extractor.extract(imdb: imdb, isTV: item.isTV, season: season, episode: episode)
            voices = res.voices; showPicker = true
        } catch { self.error = error.localizedDescription }
    }
}

@MainActor final class ExtractorHolder: ObservableObject { let extractor = AllohaExtractor() }

struct VoicePicker: View {
    let voices: [VoiceTrack]
    var body: some View {
        NavigationStack {
            List(voices) { v in
                NavigationLink(v.label) {
                    List(v.qualities) { q in NavigationLink(q.label) { PlayerScreen(quality: q) } }
                        .navigationTitle("Качество")
                }
            }.navigationTitle("Озвучка")
        }
    }
}
