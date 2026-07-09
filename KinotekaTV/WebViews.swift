import SwiftUI
import WebKit

// ===========================================================
// WKWebView-обёртки: iframe-плеер балансера (Alloha) и трейлер
// (YouTube-embed).
// ===========================================================

struct IframePlayerView: UIViewRepresentable {
    let urlString: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        web.navigationDelegate = context.coordinator
        // Плеер — HTML-обёртка с iframe (allow fullscreen, без редиректов наружу).
        let html = """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>html,body{margin:0;padding:0;height:100%;background:#000;overflow:hidden}
        iframe{width:100%;height:100%;border:0}</style></head><body>
        <iframe src="\(urlString)" allow="autoplay *; encrypted-media *; fullscreen *; picture-in-picture *" allowfullscreen></iframe>
        </body></html>
        """
        web.loadHTMLString(html, baseURL: URL(string: "https://kinoteka.pages.dev"))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        // Гард от frame-busting: не даём верхнему фрейму уходить с нашей обёртки.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.targetFrame?.isMainFrame == true,
               let url = navigationAction.request.url,
               url.scheme == "http" || url.scheme == "https",
               !(url.host ?? "").contains("kinoteka.pages.dev") {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

struct TrailerScreen: View {
    let youtubeKey: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            YouTubeView(key: youtubeKey)
                .ignoresSafeArea(edges: .bottom)
                .padding(.top, 56)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .padding(.leading, 16)
            .padding(.top, 8)
        }
    }
}

struct YouTubeView: UIViewRepresentable {
    let key: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        let html = """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>html,body{margin:0;padding:0;height:100%;background:#000}
        iframe{width:100%;height:100%;border:0}</style></head><body>
        <iframe src="https://www.youtube-nocookie.com/embed/\(key)?autoplay=1&playsinline=1&rel=0"
          allow="autoplay; encrypted-media; fullscreen; picture-in-picture" allowfullscreen></iframe>
        </body></html>
        """
        web.loadHTMLString(html, baseURL: URL(string: "https://www.youtube-nocookie.com"))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
