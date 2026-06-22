import SwiftUI

struct ContentView: View {
    @State private var query = ""
    @State private var results: [TMDBItem] = []
    @State private var searching = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(results) { item in
                    NavigationLink(value: item) {
                        HStack(spacing: 12) {
                            AsyncImage(url: item.posterURL) { img in img.resizable().aspectRatio(contentMode: .fill) }
                                placeholder: { Color.gray.opacity(0.2) }
                                .frame(width: 46, height: 69).clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.headline)
                                Text("\(item.isTV ? "Сериал" : "Фильм") · \(item.year)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Кинотека TV")
            .navigationDestination(for: TMDBItem.self) { DetailView(item: $0) }
            .searchable(text: $query, prompt: "Фильм или сериал")
            .onSubmit(of: .search) { Task { await runSearch() } }
            .overlay { if searching { ProgressView() } }
        }
    }

    private func runSearch() async {
        guard query.count > 1 else { return }
        searching = true
        results = await TMDB.search(query)
        searching = false
    }
}

struct DetailView: View {
    let item: TMDBItem
    @State private var season = 1
    @State private var episode = 1
    @State private var extracting = false
    @State private var error: String?
    @State private var voices: [VoiceTrack] = []
    @State private var showPicker = false
    @StateObject private var holder = ExtractorHolder()

    var body: some View {
        Form {
            Section(item.title) {
                Text("\(item.isTV ? "Сериал" : "Фильм") · \(item.year)").foregroundStyle(.secondary)
                if item.isTV {
                    Stepper("Сезон: \(season)", value: $season, in: 1...50)
                    Stepper("Серия: \(episode)", value: $episode, in: 1...200)
                }
            }
            Section {
                Button {
                    Task { await extract() }
                } label: {
                    Label("Смотреть на Apple TV", systemImage: "appletv")
                        .frame(maxWidth: .infinity)
                }
                .disabled(extracting)
                if extracting { HStack { ProgressView(); Text("Извлечение потока…").foregroundStyle(.secondary) } }
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            } footer: {
                Text("Поток извлекается на устройстве (твой IP), затем играй и жми AirPlay → Apple TV.")
            }
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) { VoicePicker(voices: voices) }
    }

    private func extract() async {
        error = nil; extracting = true
        defer { extracting = false }
        guard let imdb = await TMDB.imdbID(for: item) else { error = ExtractError.noImdb.errorDescription; return }
        do {
            let res = try await holder.extractor.extract(imdb: imdb, isTV: item.isTV, season: season, episode: episode)
            voices = res.voices
            showPicker = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// Keeps the @MainActor extractor alive across the async call.
@MainActor final class ExtractorHolder: ObservableObject { let extractor = AllohaExtractor() }

struct VoicePicker: View {
    let voices: [VoiceTrack]
    var body: some View {
        NavigationStack {
            List(voices) { v in
                NavigationLink(v.label) {
                    List(v.qualities) { q in
                        NavigationLink(q.label) { PlayerScreen(quality: q) }
                    }.navigationTitle("Качество")
                }
            }
            .navigationTitle("Озвучка")
        }
    }
}
