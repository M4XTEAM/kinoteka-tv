import SwiftUI
import AVKit
import Combine

// ===========================================================
// Плеер. Схема источников как в PWA:
//   СЕРИАЛЫ → «Кинотека» = ylitron (телефон-egress, SSE),
//             «Кинотека 2» = Кинопаб, «Кинотека 3» = Alloha (webview).
//   ФИЛЬМЫ  → «Кинотека» = Кинопаб, «Кинотека 2» = Alloha (webview).
// Наш плеер — нативный AVPlayer (AirPlay, CC, фуллскрин из коробки):
// видео летит ПРЯМО с CDN (сырой master / синтетический с сабами),
// как нативная ветка веба. Прогресс → Store.continueAdd (синкается).
// ===========================================================

enum PlayerSourceKind: Equatable {
    case ylitron
    case kinopub
    case iframe(url: String)
}

struct PlayerSource: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let kind: PlayerSourceKind
}

@MainActor
final class YlPlayerModel: ObservableObject {
    let launch: PlayerLaunch

    @Published var sources: [PlayerSource] = []
    @Published var current: PlayerSource?
    @Published var status: String?
    @Published var seasons: [Int: [Int]] = [:]
    @Published var season: Int
    @Published var episode: Int
    @Published var voices: [YlSource] = []
    @Published var voiceIdx: Int = 0
    @Published var player: AVPlayer?

    private var egressBase: String?
    private var loadToken = 0
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var watchT: Double = 0
    private var resumeAt: Double = 0
    private var lastSave = Date.distantPast

    var isTv: Bool { launch.media.mediaType == .tv }

    init(launch: PlayerLaunch) {
        self.launch = launch
        self.season = launch.season ?? 1
        self.episode = launch.episode ?? 1
    }

    // ---- Старт ----
    func start() async {
        Store.shared.continueAdd(launch.media, season: isTv ? season : nil, episode: isTv ? episode : nil)
        Store.shared.historyAdd(launch.media, season: isTv ? season : nil, episode: isTv ? episode : nil)

        if isTv {
            sources = [
                PlayerSource(name: "Кинотека", kind: .ylitron),
                PlayerSource(name: "Кинотека 2", kind: .kinopub),
            ]
        } else {
            sources = [PlayerSource(name: "Кинотека", kind: .kinopub)]
        }
        current = sources.first
        resumeAt = launch.resumeAt ?? 0

        // Alloha (iframe) — фоном, чипом в конец.
        Task { await addAlloha() }

        await loadCurrent()
    }

    private func addAlloha() async {
        let players = await Backend.players(launch.wid)
        guard let alloha = players.first(where: { ($0.type ?? "").lowercased() == "alloha" && $0.iframeUrl != nil }),
              var url = alloha.iframeUrl else { return }
        if isTv {
            url += (url.contains("?") ? "&" : "?") + "season=\(season)&episode=\(episode)"
        }
        let name = isTv ? "Кинотека 3" : "Кинотека 2"
        if !sources.contains(where: { $0.name == name }) {
            sources.append(PlayerSource(name: name, kind: .iframe(url: url)))
        }
    }

    func switchSource(_ source: PlayerSource) {
        guard source != current else { return }
        saveProgress(force: true)
        teardownPlayer()
        current = source
        Task { await loadCurrent() }
    }

    func loadCurrent() async {
        guard let current else { return }
        switch current.kind {
        case .ylitron: await loadYlitron()
        case .kinopub: await loadKinopub()
        case .iframe: status = nil
        }
    }

    // ---- ylitron (SSE с телефона-egress) ----
    private func loadYlitron() async {
        let token = nextToken()
        voices = []
        status = "Подключение…"

        guard let q = launch.wid.query else { status = "Источник не найден"; return }
        guard let base = await egress() else { status = "Источник не найден"; return }
        guard token == loadToken else { return }

        let url = URL(string: "\(base)/ylitron?\(q)&season=\(season)&episode=\(episode)")!
        do {
            let (bytes, _) = try await URLSession.shared.bytes(from: url)
            var collected: [YlSource] = []
            var started = false
            for try await line in bytes.lines {
                guard token == loadToken else { return }
                guard line.hasPrefix("data: "), let data = line.dropFirst(6).data(using: .utf8) else { continue }
                guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                let type = obj["type"] as? String
                if type == "episodes", let s = obj["seasons"] as? [String: [Int]] {
                    var out: [Int: [Int]] = [:]
                    for (k, v) in s { if let n = Int(k) { out[n] = v.sorted() } }
                    seasons = out
                } else if type == "source", let src = obj["source"] as? [String: Any], src["url"] is String {
                    if let d = try? JSONSerialization.data(withJSONObject: src),
                       let parsed = try? JSONDecoder().decode(YlSource.self, from: d) {
                        collected.append(parsed)
                    }
                    // Озвучки приходят пачкой — стартуем после первой порции.
                    if !started {
                        voices = collected
                        started = true
                        playVoice(preferredVoiceIdx(), seekTo: resumeSecond(), token: token)
                    } else {
                        voices = collected
                    }
                } else if type == "error", !started {
                    status = (obj["error"] as? String) ?? "Источник не найден"
                }
            }
            if !started && token == loadToken {
                status = "Источник не найден"
            }
        } catch {
            if token == loadToken && voices.isEmpty { status = "Источник не найден" }
        }
    }

    // ---- Кинопаб (/api/kp → per-voice master с телефона) ----
    private func loadKinopub() async {
        let token = nextToken()
        voices = []
        status = "Подключение…"

        guard let base = await egress() else { status = "Источник не найден"; return }
        guard token == loadToken else { return }

        let d = await Backend.kinopub(
            type: launch.media.mediaType, wid: launch.wid,
            title: launch.media.title, orig: launch.originalTitle,
            season: isTv ? season : nil, episode: isTv ? episode : nil
        )
        guard token == loadToken else { return }
        guard let d, d.found == true, let master = d.master, !master.isEmpty else {
            status = "В Кинопаб этого нет — выберите другой источник."
            return
        }
        if let s = d.seasons, !s.isEmpty {
            var out: [Int: [Int]] = [:]
            for (k, v) in s { if let n = Int(k) { out[n] = v.sorted() } }
            seasons = out
        }
        let masterEnc = master.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? master
        let voiceList = (d.voices?.isEmpty == false) ? d.voices! : [KpVoice(label: "Оригинал")]
        voices = voiceList.enumerated().map { i, v in
            YlSource(label: v.label, url: "\(base)/kpmaster?u=\(masterEnc)&voice=\(i)", subtitles: nil)
        }
        playVoice(preferredVoiceIdx(), seekTo: resumeSecond(), token: token)
    }

    // ---- Выбор URL для AVPlayer ----
    private func nativeUrl(_ source: YlSource, base: String) -> URL? {
        guard var urlStr = source.url else { return nil }
        guard let cur = current else { return URL(string: urlStr) }
        if case .kinopub = cur.kind {
            return URL(string: urlStr)
        }
        // ylitron: разворачиваем прокси /ylhls?url=… в сырой CDN-master (быстро, мимо телефона).
        var raw = urlStr
        if let comp = URLComponents(string: urlStr), comp.path.hasSuffix("/ylhls"),
           let u = comp.queryItems?.first(where: { $0.name == "url" })?.value {
            raw = u
        }
        let subs = source.subtitles ?? []
        if subs.isEmpty {
            return URL(string: raw)
        }
        // Есть субтитры → синтетический мастер с телефона: видео прямо с CDN,
        // сабы — родной дорожкой для AVPlayer (инлайн и на AirPlay).
        struct SubJson: Codable { let lang: String?; let label: String?; let url: String? }
        let subJson = subs.map { SubJson(lang: $0.lang, label: $0.label, url: $0.url) }
        guard let data = try? JSONEncoder().encode(subJson) else { return URL(string: raw) }
        let b64 = data.base64EncodedString()
        let rawEnc = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? raw
        let b64Enc = b64.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? b64
        urlStr = "\(base)/ylmaster?v=\(rawEnc)&subs=\(b64Enc)"
        return URL(string: urlStr)
    }

    func playVoice(_ idx: Int, seekTo: Double, token: Int? = nil) {
        if let token, token != loadToken { return }
        guard voices.indices.contains(idx) else { return }
        voiceIdx = idx
        let src = voices[idx]
        if let label = src.label, !label.isEmpty {
            UserDefaults.standard.set(label, forKey: "kt.ylvoice.\(launch.media.id)")
        }
        status = "Загрузка \(src.label ?? "")…"

        guard let base = egressBase, let url = nativeUrl(src, base: base) else {
            status = "Источник не найден"
            return
        }

        teardownPlayer()
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.allowsExternalPlayback = true
        p.usesExternalPlaybackWhileExternalScreenIsActive = true
        player = p
        status = nil
        watchT = seekTo

        if seekTo > 5 {
            p.seek(to: CMTime(seconds: seekTo, preferredTimescale: 600))
        }
        p.play()

        timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 5, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.watchT = time.seconds
                self.saveProgress()
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.autoNextEpisode()
            }
        }
    }

    func switchVoice(_ idx: Int) {
        guard idx != voiceIdx else { return }
        let t = player?.currentTime().seconds ?? watchT
        playVoice(idx, seekTo: t.isFinite ? t : 0)
    }

    // ---- Сезон/серия ----
    func switchEpisode(season s: Int, episode e: Int) {
        guard isTv else { return }
        saveProgress(force: true)
        season = s
        episode = e
        resumeAt = 0
        Store.shared.continueAdd(launch.media, season: s, episode: e, t: 0)
        Store.shared.historyAdd(launch.media, season: s, episode: e)
        teardownPlayer()
        Task { await loadCurrent() }
    }

    private func autoNextEpisode() {
        guard isTv, !seasons.isEmpty else { return }
        let eps = seasons[season] ?? []
        if let i = eps.firstIndex(of: episode), i + 1 < eps.count {
            switchEpisode(season: season, episode: eps[i + 1])
        } else {
            let ss = seasons.keys.sorted()
            if let si = ss.firstIndex(of: season), si + 1 < ss.count,
               let first = seasons[ss[si + 1]]?.first {
                switchEpisode(season: ss[si + 1], episode: first)
            }
        }
    }

    // ---- Прогресс ----
    private func resumeSecond() -> Double {
        if isTv {
            let cont = Store.shared.continueGet(launch.media.id)
            if let cont, cont.season == season, cont.episode == episode, (cont.t ?? 0) > 10 {
                return cont.t ?? 0
            }
            return 0
        }
        return resumeAt
    }

    func saveProgress(force: Bool = false) {
        guard watchT > 10 else { return }
        guard force || Date().timeIntervalSince(lastSave) > 4 else { return }
        lastSave = Date()
        let durRaw = player?.currentItem?.duration.seconds ?? 0
        let dur: Double? = (durRaw.isFinite && durRaw > 0) ? durRaw.rounded(.down) : nil
        Store.shared.continueAdd(
            launch.media,
            season: isTv ? season : nil,
            episode: isTv ? episode : nil,
            t: watchT.rounded(.down),
            dur: dur
        )
    }

    // ---- Служебное ----
    private func nextToken() -> Int {
        loadToken += 1
        return loadToken
    }

    private func egress() async -> String? {
        if let e = egressBase { return e }
        egressBase = await Backend.ylEgress()
        return egressBase
    }

    private func preferredVoiceIdx() -> Int {
        guard let pref = UserDefaults.standard.string(forKey: "kt.ylvoice.\(launch.media.id)"),
              let i = voices.firstIndex(where: { $0.label == pref })
        else { return 0 }
        return i
    }

    func teardownPlayer() {
        if let obs = timeObserver, let p = player {
            p.removeTimeObserver(obs)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player?.pause()
        player = nil
    }

    func close() {
        loadToken += 1
        saveProgress(force: true)
        teardownPlayer()
        Task { await SyncEngine.shared.flush() }
    }
}

extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=?+/")
        return set
    }()
}

// ===========================================================
// Экран плеера: нативный AVPlayer / iframe-webview + панель
// (источники, сезон/серия, озвучка) на Liquid Glass.
// ===========================================================

struct PlayerScreen: View {
    let launch: PlayerLaunch

    @StateObject private var model: YlPlayerModel
    @Environment(\.dismiss) private var dismiss

    init(launch: PlayerLaunch) {
        self.launch = launch
        _model = StateObject(wrappedValue: YlPlayerModel(launch: launch))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                controlsBar

                ZStack {
                    if let current = model.current, case .iframe(let url) = current.kind {
                        IframePlayerView(urlString: url)
                    } else if let player = model.player {
                        VideoPlayerView(player: player)
                    } else {
                        VStack(spacing: 14) {
                            ProgressView()
                            if let status = model.status {
                                Text(status)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(20)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await model.start() }
        .onDisappear { model.close() }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                model.close()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)

            Text(launch.media.title)
                .font(.headline)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var controlsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Источники.
                ForEach(model.sources) { src in
                    Button {
                        model.switchSource(src)
                    } label: {
                        Text(src.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(src == model.current ? .black : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(src == model.current ? Theme.accent : .clear, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }

                // Сезон / серия.
                if model.isTv && !model.seasons.isEmpty {
                    Menu {
                        ForEach(model.seasons.keys.sorted(), id: \.self) { s in
                            Button("Сезон \(s)") {
                                let eps = model.seasons[s] ?? []
                                model.switchEpisode(season: s, episode: eps.first ?? 1)
                            }
                        }
                    } label: {
                        chipLabel("Сезон \(model.season)")
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)

                    Menu {
                        ForEach(model.seasons[model.season] ?? [], id: \.self) { e in
                            Button("Серия \(e)") {
                                model.switchEpisode(season: model.season, episode: e)
                            }
                        }
                    } label: {
                        chipLabel("Серия \(model.episode)")
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }

                // Озвучка.
                if model.voices.count > 1 {
                    Menu {
                        ForEach(Array(model.voices.enumerated()), id: \.offset) { i, v in
                            Button {
                                model.switchVoice(i)
                            } label: {
                                if i == model.voiceIdx {
                                    Label(v.label ?? "Озвучка \(i + 1)", systemImage: "checkmark")
                                } else {
                                    Text(v.label ?? "Озвучка \(i + 1)")
                                }
                            }
                        }
                    } label: {
                        chipLabel(model.voices[safe: model.voiceIdx]?.label ?? "Озвучка", icon: "waveform")
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }

    private func chipLabel(_ text: String, icon: String? = nil) -> some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.caption2) }
            Text(text)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// AVPlayerViewController: нативные контролы, AirPlay, CC, PiP.
struct VideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.allowsPictureInPicturePlayback = true
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player {
            vc.player = player
        }
    }
}
