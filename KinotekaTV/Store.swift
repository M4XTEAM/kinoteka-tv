import Foundation
import Combine

// ===========================================================
// Локальное хранилище (избранное/папки/подписки/продолжить/
// история) в ТОЧНОМ формате веб-версии: метки `u` (мс) и
// «надгробия» `d:true` → сервер сливает состояния устройств
// без потерь (POST /api/sync). Хранение — UserDefaults (JSON).
// ===========================================================

struct FavItem: Codable, Identifiable, Hashable {
    var id: Int
    var type: String?
    var title: String?
    var posterPath: String?
    var voteAverage: Double?
    var releaseDate: String?
    var folders: [String]?
    var u: Double?
    var d: Bool?

    enum CodingKeys: String, CodingKey {
        case id, type, title, folders, u, d
        case posterPath = "poster_path"
        case voteAverage = "vote_average"
        case releaseDate = "release_date"
    }

    var mediaType: MediaType { MediaType(rawValue: type ?? "movie") ?? .movie }
    var asMedia: MediaItem {
        MediaItem(id: id, mediaType: mediaType, title: title ?? "", posterPath: posterPath,
                  backdropPath: nil, voteAverage: voteAverage, releaseDate: releaseDate)
    }
}

struct FolderItem: Codable, Hashable {
    var name: String
    var u: Double?
    var d: Bool?
}

struct SubItem: Codable, Identifiable, Hashable {
    var id: Int
    var type: String?
    var name: String?
    var posterPath: String?
    var u: Double?
    var d: Bool?

    enum CodingKeys: String, CodingKey {
        case id, type, name, u, d
        case posterPath = "poster_path"
    }
}

struct ContinueItem: Codable, Identifiable, Hashable {
    var id: Int
    var type: String?
    var title: String?
    var posterPath: String?
    var voteAverage: Double?
    var releaseDate: String?
    var season: Int?
    var episode: Int?
    var t: Double?
    var dur: Double?
    var ts: Double?
    var u: Double?
    var d: Bool?

    enum CodingKeys: String, CodingKey {
        case id, type, title, season, episode, t, dur, ts, u, d
        case posterPath = "poster_path"
        case voteAverage = "vote_average"
        case releaseDate = "release_date"
    }

    var mediaType: MediaType { MediaType(rawValue: type ?? "movie") ?? .movie }
    var asMedia: MediaItem {
        MediaItem(id: id, mediaType: mediaType, title: title ?? "", posterPath: posterPath,
                  backdropPath: nil, voteAverage: voteAverage, releaseDate: releaseDate)
    }
}

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    static let defaultFolder = "Избранное"

    @Published private(set) var favorites: [FavItem] = []
    @Published private(set) var folderItems: [FolderItem] = []
    @Published private(set) var subsItems: [SubItem] = []
    @Published private(set) var continueItems: [ContinueItem] = []
    @Published private(set) var historyItems: [ContinueItem] = []

    private let ud = UserDefaults.standard
    private let encoder: JSONEncoder = JSONEncoder()

    private func now() -> Double { Date().timeIntervalSince1970 * 1000 }

    init() {
        favorites = load("kt.favorites")
        folderItems = load("kt.folders")
        subsItems = load("kt.subs")
        continueItems = load("kt.continue")
        historyItems = load("kt.history")
    }

    private func load<T: Codable>(_ key: String) -> [T] {
        guard let data = ud.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([T].self, from: data)) ?? []
    }

    private func persist<T: Codable>(_ key: String, _ list: [T]) {
        if let data = try? encoder.encode(list) { ud.set(data, forKey: key) }
    }

    private var applying = false
    private func changed() {
        persistAll()
        if !applying { SyncEngine.shared.schedule() }
    }

    private func persistAll() {
        persist("kt.favorites", favorites)
        persist("kt.folders", folderItems)
        persist("kt.subs", subsItems)
        persist("kt.continue", continueItems)
        persist("kt.history", historyItems)
    }

    // ---- Папки ----
    var folders: [String] {
        var names = folderItems.filter { $0.d != true }.map(\.name)
        if !names.contains(Store.defaultFolder) { names.insert(Store.defaultFolder, at: 0) }
        return names
    }

    func createFolder(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !folderItems.contains(where: { $0.name == n && $0.d != true }) else { return }
        if let i = folderItems.firstIndex(where: { $0.name == n }) {
            folderItems[i].d = false
            folderItems[i].u = now()
        } else {
            folderItems.append(FolderItem(name: n, u: now(), d: false))
        }
        changed()
    }

    func deleteFolder(_ name: String) {
        guard name != Store.defaultFolder else { return }
        if let i = folderItems.firstIndex(where: { $0.name == name && $0.d != true }) {
            folderItems[i].d = true
            folderItems[i].u = now()
        }
        for i in favorites.indices where favorites[i].d != true {
            var fs = favorites[i].folders ?? [Store.defaultFolder]
            guard fs.contains(name) else { continue }
            fs.removeAll { $0 == name }
            favorites[i].folders = fs
            favorites[i].u = now()
            if fs.isEmpty { favorites[i].d = true }
        }
        changed()
    }

    // ---- Избранное ----
    func favoritesIn(_ folder: String?) -> [FavItem] {
        let live = favorites.filter { $0.d != true }
        guard let f = folder else { return live }
        return live.filter { ($0.folders ?? [Store.defaultFolder]).contains(f) }
    }

    func itemFolders(_ id: Int, _ type: MediaType) -> [String] {
        guard let m = favorites.first(where: { $0.id == id && $0.d != true && ($0.type ?? "movie") == type.rawValue })
        else { return [] }
        return m.folders ?? [Store.defaultFolder]
    }

    func isFavorite(_ id: Int, _ type: MediaType) -> Bool {
        !itemFolders(id, type).isEmpty
    }

    func setFolders(_ item: MediaItem, _ folderArr: [String]) {
        var seen = Set<String>()
        let clean = folderArr.filter { !$0.isEmpty && seen.insert($0).inserted }
        let idx = favorites.firstIndex { $0.id == item.id && ($0.type ?? "movie") == item.mediaType.rawValue }
        if clean.isEmpty {
            if let i = idx {
                favorites[i].d = true
                favorites[i].u = now()
                changed()
            }
            return
        }
        let entry = FavItem(id: item.id, type: item.mediaType.rawValue, title: item.title,
                            posterPath: item.posterPath, voteAverage: item.voteAverage,
                            releaseDate: item.releaseDate, folders: clean, u: now(), d: false)
        if let i = idx {
            favorites[i] = entry
        } else {
            favorites.insert(entry, at: 0)
        }
        changed()
    }

    func toggleFavorite(_ item: MediaItem) {
        if isFavorite(item.id, item.mediaType) { setFolders(item, []) }
        else { setFolders(item, [Store.defaultFolder]) }
    }

    // ---- Подписки ----
    var subs: [SubItem] { subsItems.filter { $0.d != true } }

    func isSub(_ id: Int, _ type: MediaType) -> Bool {
        subs.contains { $0.id == id && ($0.type ?? "tv") == type.rawValue }
    }

    func subToggle(_ item: MediaItem) {
        let i = subsItems.firstIndex { $0.id == item.id && ($0.type ?? "tv") == item.mediaType.rawValue }
        if let i, subsItems[i].d != true {
            subsItems[i].d = true
            subsItems[i].u = now()
        } else {
            let entry = SubItem(id: item.id, type: item.mediaType.rawValue, name: item.title,
                                posterPath: item.posterPath, u: now(), d: false)
            if let i { subsItems[i] = entry } else { subsItems.insert(entry, at: 0) }
        }
        changed()
    }

    // ---- Продолжить просмотр ----
    func continueList(_ type: MediaType? = nil) -> [ContinueItem] {
        let live = continueItems.filter { $0.d != true }.sorted { ($0.u ?? 0) > ($1.u ?? 0) }
        guard let t = type else { return live }
        return live.filter { ($0.type ?? "movie") == t.rawValue }
    }

    func continueGet(_ id: Int) -> ContinueItem? {
        continueItems.first { $0.id == id && $0.d != true }
    }

    func continueAdd(_ item: MediaItem, season: Int? = nil, episode: Int? = nil, t: Double? = nil, dur: Double? = nil) {
        let prev = continueGet(item.id)
        continueItems.removeAll { $0.id == item.id }
        let entry = ContinueItem(
            id: item.id, type: item.mediaType.rawValue, title: item.title,
            posterPath: item.posterPath, voteAverage: item.voteAverage, releaseDate: item.releaseDate,
            season: season ?? prev?.season, episode: episode ?? prev?.episode,
            t: t ?? prev?.t, dur: dur ?? prev?.dur,
            ts: nil, u: now(), d: false
        )
        continueItems.insert(entry, at: 0)
        if continueItems.count > 40 { continueItems = Array(continueItems.prefix(40)) }
        changed()
    }

    func continueRemove(_ id: Int) {
        if let i = continueItems.firstIndex(where: { $0.id == id && $0.d != true }) {
            continueItems[i].d = true
            continueItems[i].u = now()
            changed()
        }
    }

    // ---- История ----
    func historyList(_ type: MediaType? = nil) -> [ContinueItem] {
        let live = historyItems.filter { $0.d != true }.sorted { ($0.u ?? 0) > ($1.u ?? 0) }
        guard let t = type else { return live }
        return live.filter { ($0.type ?? "movie") == t.rawValue }
    }

    func historyAdd(_ item: MediaItem, season: Int? = nil, episode: Int? = nil) {
        let prev = historyItems.first { $0.id == item.id && ($0.type ?? "movie") == item.mediaType.rawValue && $0.d != true }
        historyItems.removeAll { $0.id == item.id && ($0.type ?? "movie") == item.mediaType.rawValue }
        let entry = ContinueItem(
            id: item.id, type: item.mediaType.rawValue, title: item.title,
            posterPath: item.posterPath, voteAverage: item.voteAverage, releaseDate: item.releaseDate,
            season: season ?? prev?.season, episode: episode ?? prev?.episode,
            t: nil, dur: nil, ts: now(), u: now(), d: false
        )
        historyItems.insert(entry, at: 0)
        if historyItems.count > 80 { historyItems = Array(historyItems.prefix(80)) }
        changed()
    }

    func historyRemove(_ id: Int, _ type: MediaType) {
        if let i = historyItems.firstIndex(where: { $0.id == id && ($0.type ?? "movie") == type.rawValue && $0.d != true }) {
            historyItems[i].d = true
            historyItems[i].u = now()
            changed()
        }
    }

    func historyClear() {
        for i in historyItems.indices where historyItems[i].d != true {
            historyItems[i].d = true
            historyItems[i].u = now()
        }
        changed()
    }

    // ---- Синхронизация: экспорт/импорт полного состояния ----
    func exportState() -> [String: Any] {
        func arr<T: Codable>(_ list: [T]) -> [Any] {
            guard let data = try? encoder.encode(list),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [Any]
            else { return [] }
            return obj
        }
        return [
            "favorites": arr(favorites),
            "folders": arr(folderItems),
            "subs": arr(subsItems),
            "continue": arr(continueItems),
            "history": arr(historyItems),
        ]
    }

    func importState(_ state: [String: Any]) {
        applying = true
        defer { applying = false }
        func dec<T: Codable>(_ key: String, _ type: T.Type) -> [T]? {
            guard let raw = state[key],
                  let data = try? JSONSerialization.data(withJSONObject: raw)
            else { return nil }
            return try? JSONDecoder().decode([T].self, from: data)
        }
        if let f: [FavItem] = dec("favorites", FavItem.self) { favorites = f }
        if let f: [FolderItem] = dec("folders", FolderItem.self) { folderItems = f }
        if let s: [SubItem] = dec("subs", SubItem.self) { subsItems = s }
        if let c: [ContinueItem] = dec("continue", ContinueItem.self) { continueItems = c }
        if let h: [ContinueItem] = dec("history", ContinueItem.self) { historyItems = h }
        persistAll()
    }

    func wipeLocal() {
        applying = true
        favorites = []; folderItems = []; subsItems = []; continueItems = []; historyItems = []
        persistAll()
        applying = false
    }
}

// ===========================================================
// Sync-движок: POST /api/sync = upload+merge+download.
// Триггеры: старт, изменение Store (debounce), возврат в foreground.
// Троттлинг 30с (лимит KV-записей на free-тарифе).
// ===========================================================

@MainActor
final class SyncEngine: ObservableObject {
    static let shared = SyncEngine()

    private var syncing = false
    private var pending = false
    private var enabled = true
    private var lastSyncAt: Date = .distantPast
    private var task: Task<Void, Never>?
    private let minInterval: TimeInterval = 30
    private let ownerKey = "kt.owner"

    func schedule(delay: TimeInterval = 1.5) {
        guard enabled else { return }
        let since = Date().timeIntervalSince(lastSyncAt)
        let eff = max(delay, minInterval - since)
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, eff) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    func flush() async {
        guard enabled, !syncing else {
            if syncing { pending = true }
            return
        }
        syncing = true
        lastSyncAt = Date()
        let (state, status) = await Backend.syncPost(Store.shared.exportState())
        if status == 401 || status == 403 { enabled = false }
        if let state { Store.shared.importState(state) }
        syncing = false
        if pending {
            pending = false
            schedule(delay: 0)
        }
    }

    // Первый синк: если аккаунт устройству незнаком/сменился — сервер источник
    // правды (заменяем локальное, ничего не пушим). Иначе — обычный merge.
    func firstSync() async {
        enabled = true
        guard let me = await Backend.me(), let login = me.login else {
            await flush()
            return
        }
        if UserDefaults.standard.string(forKey: ownerKey) == login {
            await flush()
        } else {
            if let state = await Backend.syncGet() {
                Store.shared.wipeLocal()
                Store.shared.importState(state)
            } else {
                Store.shared.wipeLocal()
            }
            UserDefaults.standard.set(login, forKey: ownerKey)
        }
    }
}
