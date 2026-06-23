import SwiftUI
import WebKit

// In-app playback = the balancer's own player in a WKWebView (like the PWA does).
// The embed must be FRAMED (Alloha's isFramed guard) and we use referrerpolicy=no-referrer
// to dodge domain-allowlist checks. iPhone UA -> H.264 renditions that the phone decodes.
struct WebPlayerView: UIViewRepresentable {
    let embed: String

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.customUserAgent = AllohaExtractor.iphoneUA
        wv.scrollView.isScrollEnabled = false
        wv.backgroundColor = .black
        wv.isOpaque = false
        let html = """
        <!doctype html><html><head><meta charset=utf-8>
        <meta name=viewport content="width=device-width,initial-scale=1,viewport-fit=cover"></head>
        <body style="margin:0;background:#000">
        <iframe referrerpolicy="no-referrer" src="\(embed)"
          allow="autoplay;fullscreen;encrypted-media;picture-in-picture"
          allowfullscreen style="border:0;position:fixed;inset:0;width:100%;height:100%"></iframe>
        </body></html>
        """
        wv.loadHTMLString(html, baseURL: URL(string: "https://fbphdplay.top/"))
        return wv
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct WebPlayerScreen: View {
    let embed: String
    var body: some View {
        WebPlayerView(embed: embed)
            .ignoresSafeArea()
            .background(.black)
    }
}
