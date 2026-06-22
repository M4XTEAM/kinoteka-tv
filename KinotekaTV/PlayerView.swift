import SwiftUI
import AVKit
import AVFoundation

// HF proxy injects Referer/iPhone-UA server-side so the Apple TV (which can't set custom
// HTTP headers on AirPlay) can fetch the VK CDN stream. VK serves the HF (US) IP fine.
enum StreamProxy {
    static let base = "https://MNQE-alloha-extract.hf.space/api?url="
    static func wrap(_ m3u8: String) -> URL? {
        guard let enc = m3u8.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) else { return nil }
        return URL(string: base + enc)
    }
}

extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var cs = CharacterSet.urlQueryAllowed
        cs.remove(charactersIn: "&=?+/")
        return cs
    }()
}

// AVPlayerViewController gives native transport controls INCLUDING the AirPlay route
// button (allowsExternalPlayback defaults true). Tap it -> pick Apple TV.
struct PlayerView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let vc = AVPlayerViewController()
        let player = AVPlayer(url: url)
        player.allowsExternalPlayback = true
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
        vc.player = player
        vc.allowsPictureInPicturePlayback = true
        player.play()
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {}
}

struct PlayerScreen: View {
    let quality: Quality
    var body: some View {
        if let url = StreamProxy.wrap(quality.url) {
            PlayerView(url: url).ignoresSafeArea().navigationTitle("\(quality.height)p")
        } else {
            Text("Битая ссылка потока")
        }
    }
}
