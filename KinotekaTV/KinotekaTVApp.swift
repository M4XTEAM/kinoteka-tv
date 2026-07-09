import SwiftUI
import AVFAudio

// ===========================================================
// Кинотека — нативный клиент (iOS 26, Liquid Glass).
// ===========================================================

@main
struct KinotekaTVApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var store = Store.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.checking {
                    SplashView()
                } else if appState.authorized {
                    RootTabs()
                } else {
                    AuthView()
                }
            }
            .environmentObject(appState)
            .environmentObject(store)
            .preferredColorScheme(.dark)
            .tint(Theme.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && appState.authorized {
                Task { await SyncEngine.shared.flush() }
            } else if phase == .background {
                Task { await SyncEngine.shared.flush() }
            }
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var checking = true
    @Published var authorized = false
    @Published var login: String?
    @Published var expiresAt: Double?

    init() {
        Task { await check() }
    }

    func check() async {
        checking = true
        if Backend.hasSessionCookie, let me = await Backend.me() {
            login = me.login
            expiresAt = me.expiresAt
            authorized = true
            await SyncEngine.shared.firstSync()
        } else {
            authorized = false
        }
        checking = false
    }

    func didLogin() async {
        if let me = await Backend.me() {
            login = me.login
            expiresAt = me.expiresAt
        }
        authorized = true
        await SyncEngine.shared.firstSync()
    }

    func logout() async {
        await Backend.logout()
        authorized = false
        login = nil
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Кинотека")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.accent)
                ProgressView()
            }
        }
    }
}
