import SwiftUI

// ===========================================================
// Избранное: папки, «Продолжить просмотр», история.
// Всё синкается с веб-версией через /api/sync.
// ===========================================================

struct FavoritesView: View {
    @EnvironmentObject private var store: Store
    @State private var newFolder = ""
    @State private var showNewFolder = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ContinueShelf(title: "Продолжить просмотр", items: store.continueList())

                // Папки избранного.
                ForEach(store.folders, id: \.self) { folder in
                    let items = store.favoritesIn(folder).map(\.asMedia)
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: folder, more: {
                                AnyView(
                                    NavigationLink(value: FolderRoute(name: folder)) {
                                        Text("Все ›")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(Theme.accent)
                                    }
                                    .buttonStyle(.plain)
                                )
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

                if store.favoritesIn(nil).isEmpty && store.continueList().isEmpty && store.historyList().isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "heart")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Здесь появится то, что вы добавите в избранное")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 120)
                }

                // История.
                let history = store.historyList()
                if !history.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "История", more: {
                            AnyView(
                                Button("Очистить") { store.historyClear() }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                                    .buttonStyle(.plain)
                            )
                        })
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 12) {
                                ForEach(history) { item in
                                    ContinueCard(item: item)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.top, 18)
                }

                Color.clear.frame(height: 40)
            }
            .padding(.top, 8)
        }
        .background(Theme.bg)
        .navigationTitle("Избранное")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNewFolder = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
            }
        }
        .alert("Новая папка", isPresented: $showNewFolder) {
            TextField("Название", text: $newFolder)
            Button("Создать") {
                store.createFolder(newFolder)
                newFolder = ""
            }
            Button("Отмена", role: .cancel) { newFolder = "" }
        }
    }
}

struct FolderView: View {
    let name: String

    @EnvironmentObject private var store: Store

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PosterGrid(items: store.favoritesIn(name).map(\.asMedia))
                Color.clear.frame(height: 30)
            }
            .padding(.top, 8)
        }
        .background(Theme.bg)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if name != Store.defaultFolder {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(role: .destructive) {
                            store.deleteFolder(name)
                        } label: {
                            Label("Удалить папку", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
}
