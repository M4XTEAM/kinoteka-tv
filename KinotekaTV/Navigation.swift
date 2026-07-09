import SwiftUI

// ===========================================================
// Роуты навигации + координатор плеера (fullScreenCover).
// ===========================================================

struct MediaRoute: Hashable {
    let type: MediaType
    let id: Int
}

struct PersonRoute: Hashable {
    let id: Int
}

struct ListRoute: Hashable {
    let type: MediaType
    let source: String
    let title: String
}

struct GenresRoute: Hashable {
    let type: MediaType
}

struct BrowseRoute: Hashable {
    var type: MediaType
    var genreId: Int?
    var genreName: String?
    var providerId: Int?
    var providerName: String?
}

struct FolderRoute: Hashable {
    let name: String
}

extension View {
    // Общие destination'ы для всех стеков.
    func appDestinations() -> some View {
        self
            .navigationDestination(for: MediaRoute.self) { DetailView(route: $0) }
            .navigationDestination(for: PersonRoute.self) { PersonView(personId: $0.id) }
            .navigationDestination(for: ListRoute.self) { ListView(route: $0) }
            .navigationDestination(for: GenresRoute.self) { GenresView(type: $0.type) }
            .navigationDestination(for: BrowseRoute.self) { BrowseView(route: $0) }
            .navigationDestination(for: FolderRoute.self) { FolderView(name: $0.name) }
    }
}

// ---- Запуск плеера ----
struct PlayerLaunch: Identifiable {
    let id = UUID()
    let media: MediaItem
    let wid: WatchId
    let originalTitle: String?
    var season: Int?
    var episode: Int?
    var resumeAt: Double?
}

@MainActor
final class PlayerCoordinator: ObservableObject {
    static let shared = PlayerCoordinator()
    @Published var launch: PlayerLaunch?

    func open(_ launch: PlayerLaunch) {
        self.launch = launch
    }
}
