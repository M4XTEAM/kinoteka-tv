import SwiftUI

// ===========================================================
// Страница персоны: фото, роль, биография (ru → en фолбэк),
// полки фильмографии (актёр: сериалы/фильмы; режиссёр; продюсер).
// ===========================================================

struct PersonView: View {
    let personId: Int

    @State private var person: PersonDetail?
    @State private var bio: String = ""
    @State private var error: String?
    @State private var bioExpanded = false

    var body: some View {
        ScrollView {
            if let p = person {
                VStack(alignment: .leading, spacing: 20) {
                    header(p)

                    if !bio.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Биография")
                                .font(.title3.weight(.bold))
                            Text(bio)
                                .font(.subheadline)
                                .foregroundStyle(.primary.opacity(0.9))
                                .lineLimit(bioExpanded ? nil : 6)
                            Button(bioExpanded ? "Свернуть" : "Читать далее") {
                                withAnimation { bioExpanded.toggle() }
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                        }
                        .padding(.horizontal, 20)
                    }

                    creditShelves(p)
                    Color.clear.frame(height: 40)
                }
                .padding(.top, 12)
            } else if let error {
                ErrorView(message: error) { Task { await load() } }
            } else {
                LoadingView()
            }
        }
        .background(Theme.bg)
        .navigationTitle(person?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func header(_ p: PersonDetail) -> some View {
        HStack(alignment: .top, spacing: 16) {
            RemoteImage(url: TMDB.profile(p.profilePath, "w342"))
                .frame(width: 110, height: 110)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(p.name)
                    .font(.title2.weight(.bold))
                Text(p.knownForDepartment == "Directing" ? "Режиссёр"
                     : p.knownForDepartment == "Production" ? "Продюсер" : "Актёр")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let b = p.birthday, !b.isEmpty {
                    Text(Fmt.date(b) + age(p))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let place = p.placeOfBirth, !place.isEmpty {
                    Text(place)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let ig = p.externalIds?.instagramId, !ig.isEmpty,
                   let url = URL(string: "https://instagram.com/\(ig)") {
                    Link(destination: url) {
                        HStack(spacing: 5) {
                            Image(systemName: "camera.fill")
                            Text("@\(ig)")
                                .lineLimit(1)
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .tint(Theme.accent)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .padding(.top, 2)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private func age(_ p: PersonDetail) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let birth = p.birthday.flatMap({ f.date(from: $0) }) else { return "" }
        let end = p.deathday.flatMap { f.date(from: $0) } ?? Date()
        let years = Calendar.current.dateComponents([.year], from: birth, to: end).year ?? 0
        return " · \(years) лет"
    }

    @ViewBuilder
    private func creditShelves(_ p: PersonDetail) -> some View {
        let cast = p.combinedCredits?.cast ?? []
        let crew = p.combinedCredits?.crew ?? []

        let tvActing = dedupe(cast.filter { $0.mediaType == "tv" })
        let movieActing = dedupe(cast.filter { $0.mediaType != "tv" })
        let directing = dedupe(crew.filter { $0.job == "Director" })
        let producing = dedupe(crew.filter { $0.job == "Producer" || $0.job == "Executive Producer" })

        Shelf(title: "Фильмы", items: movieActing)
        Shelf(title: "Сериалы", items: tvActing)
        Shelf(title: "Режиссёр", items: directing)
        Shelf(title: "Продюсер", items: producing)
    }

    private func dedupe(_ credits: [PersonCredit]) -> [MediaItem] {
        var seen = Set<Int>()
        return credits
            .sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
            .filter { seen.insert($0.id).inserted && $0.posterPath != nil }
            .map(\.asMedia)
    }

    private func load() async {
        do {
            let p = try await TMDB.person(personId)
            person = p
            if let b = p.biography, !b.isEmpty {
                bio = b
            } else {
                bio = (try? await TMDB.personBioEn(personId)) ?? ""
            }
        } catch {
            self.error = "Не удалось загрузить"
        }
    }
}
