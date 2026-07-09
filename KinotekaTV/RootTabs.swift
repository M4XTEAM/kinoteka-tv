import SwiftUI

// ===========================================================
// Корневые вкладки в стиле приложения Apple TV+ (iOS 26):
// системный плавающий Liquid Glass таб-бар, «Поиск» — отдельной
// стеклянной кнопкой (role: .search), бар прячется при скролле.
// ===========================================================

struct RootTabs: View {
    @StateObject private var player = PlayerCoordinator.shared

    var body: some View {
        TabView {
            Tab("Фильмы", systemImage: "film.fill") {
                NavigationStack {
                    CatalogHomeView(type: .movie)
                        .appDestinations()
                }
            }
            Tab("Сериалы", systemImage: "play.tv.fill") {
                NavigationStack {
                    CatalogHomeView(type: .tv)
                        .appDestinations()
                }
            }
            Tab("Подписки", systemImage: "rectangle.stack.badge.play.fill") {
                NavigationStack {
                    SubscriptionsView()
                        .appDestinations()
                }
            }
            Tab("Избранное", systemImage: "heart.fill") {
                NavigationStack {
                    FavoritesView()
                        .appDestinations()
                }
            }
            Tab("Поиск", systemImage: "magnifyingglass", role: .search) {
                NavigationStack {
                    SearchView()
                        .appDestinations()
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .fullScreenCover(item: $player.launch) { launch in
            PlayerScreen(launch: launch)
        }
    }
}
