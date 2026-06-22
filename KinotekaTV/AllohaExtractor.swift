import Foundation
import WebKit
import UIKit

// On-device Alloha extraction. We can't sniff a cross-origin iframe's network from
// JS in a normal web page, but a NATIVE WKWebView CAN inject a script into ALL frames
// (forMainFrameOnly: false) — so we hook XHR/fetch INSIDE the Alloha iframe, let its
// obfuscated player compute the anti-bot `borth` and POST /bnsi, and capture the JSON.
// Runs on the device's residential IP -> no datacenter geo-block.
@MainActor
final class AllohaExtractor: NSObject, WKScriptMessageHandler, WKNavigationDelegate {

    static let iphoneUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    private let balancer = "https://fbphdplay.top"

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<ExtractResult, Error>?
    private var bestBnsi: [String: Any]?
    private var timeoutTask: Task<Void, Never>?

    // MARK: public API
    func extract(imdb: String, isTV: Bool, season: Int, episode: Int) async throws -> ExtractResult {
        guard let embed = try await allohaEmbed(imdb: imdb) else { throw ExtractError.noAlloha }
        var embedURL = embed
        if isTV { embedURL += (embed.contains("?") ? "&" : "?") + "season=\(season)&episode=\(episode)" }
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            self.startWebView(embed: embedURL, isTV: isTV, season: season, episode: episode)
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 28_000_000_000) // 28s
                await self?.finish()
            }
        }
    }

    // MARK: balancer -> Alloha embed url
    private func allohaEmbed(imdb: String) async throws -> String? {
        guard let url = URL(string: "\(balancer)/api/players?imdb=\(imdb)") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("https://fbfind.top/", forHTTPHeaderField: "Referer")
        req.setValue(Self.iphoneUA, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let root = try? JSONSerialization.jsonObject(with: data),
              let list = (root as? [String: Any])?["data"] as? [[String: Any]] ?? root as? [[String: Any]] else { return nil }
        for p in list where (p["type"] as? String) == "Alloha" {
            if let u = p["iframeUrl"] as? String { return u }
        }
        return nil
    }

    // MARK: hidden WKWebView running the framed player
    private func startWebView(embed: String, isTV: Bool, season: Int, episode: Int) {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let ucc = WKUserContentController()
        ucc.add(self, name: "kt")
        let seJS = isTV ? "{s:\(season),e:\(episode)}" : "null"
        let script = WKUserScript(source: Self.hookJS(seJS: seJS), injectionTime: .atDocumentStart, forMainFrameOnly: false)
        ucc.addUserScript(script)
        cfg.userContentController = ucc

        // Full-size + nearly transparent (NOT isHidden): a hidden/0-size WKWebView throttles
        // timers & media, so the player may never fire /bnsi. Cover it with the SwiftUI
        // loading UI; it's invisible (alpha 0.02) and passes touches through.
        let window = UIApplication.shared.keyWindowScene
        let frame = window?.bounds ?? CGRect(x: 0, y: 0, width: 390, height: 700)
        let wv = WKWebView(frame: frame, configuration: cfg)
        wv.customUserAgent = Self.iphoneUA
        wv.navigationDelegate = self
        wv.alpha = 0.02
        wv.isUserInteractionEnabled = false
        window?.addSubview(wv)
        self.webView = wv

        // Wrapper page so the embed is FRAMED (passes Alloha's isFramed guard). baseURL =
        // balancer domain -> plausible referrer (not a banned casino referrer).
        let html = """
        <!doctype html><html><head><meta charset=utf-8></head>
        <body style="margin:0">
        <iframe src="\(embed)" allow="autoplay;fullscreen;encrypted-media" style="border:0;width:100%;height:100vh"></iframe>
        </body></html>
        """
        wv.loadHTMLString(html, baseURL: URL(string: "\(balancer)/"))
    }

    // JS injected into EVERY frame (incl. the cross-origin Alloha iframe).
    private static func hookJS(seJS: String) -> String {
        """
        (function(){
          if (window.__ktHooked) return; window.__ktHooked = true;
          var SE = \(seJS);
          function post(o){ try{ window.webkit.messageHandlers.kt.postMessage(o);}catch(e){} }
          function isBnsi(u){ return /\\/bnsi\\/(movies|serials)\\//.test(String(u||'')); }
          var O = XMLHttpRequest.prototype.open, S = XMLHttpRequest.prototype.send;
          XMLHttpRequest.prototype.open = function(m,u){ this.__u=u; return O.apply(this,arguments); };
          XMLHttpRequest.prototype.send = function(){
            var x=this; this.addEventListener('load', function(){
              try{ if(isBnsi(x.__u)) post({type:'bnsi', body:x.responseText}); }catch(e){}
            }); return S.apply(this,arguments);
          };
          var F = window.fetch;
          if (F) window.fetch = function(){ var a=arguments; return F.apply(this,a).then(function(r){
            try{ var u=(a[0]&&a[0].url)||a[0]||''; if(isBnsi(u)) r.clone().text().then(function(t){ post({type:'bnsi',body:t}); }); }catch(e){}
            return r; }); };
          function choose(key,id){ var root=document.querySelector('[data-select="'+key+'"]'); if(!root)return;
            var head=root.querySelector('.select__item,button'); if(head)head.click();
            var it=[].slice.call(root.querySelectorAll('.select__drop-item,[data-id]')).filter(function(e){return (e.getAttribute('data-id')||'').trim()==String(id);})[0];
            if(it)it.click(); }
          function go(){
            try {
              if (SE) { choose('seasonType1', SE.s); setTimeout(function(){ choose('episodeType1', SE.e); }, 900); }
              setTimeout(function(){
                var ov=document.querySelector('.plyr__control--overlaid'); if(ov)ov.click();
                [].forEach.call(document.querySelectorAll('video'), function(v){ v.muted=true; try{v.play();}catch(e){} });
              }, SE?1700:400);
            } catch(e){}
          }
          if (document.readyState!=='loading') setTimeout(go,600);
          else document.addEventListener('DOMContentLoaded', function(){ setTimeout(go,600); });
        })();
        """
    }

    // MARK: receive bnsi from JS
    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any], dict["type"] as? String == "bnsi",
              let body = dict["body"] as? String, let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        // keep the LAST bnsi that actually carries streams (skip "Серия 0" placeholders)
        if let src = json["hlsSource"] as? [[String: Any]], !src.isEmpty {
            bestBnsi = json
            // movies fire once -> resolve quickly; series may re-fire, wait a bit more
            Task { try? await Task.sleep(nanoseconds: 1_500_000_000); await self.finishIfReady() }
        }
    }

    private func finishIfReady() async { if bestBnsi != nil { await finish() } }

    private func finish() async {
        guard let cont = continuation else { return }
        continuation = nil
        timeoutTask?.cancel()
        webView?.removeFromSuperview(); webView = nil
        guard let bnsi = bestBnsi, let voices = Self.parse(bnsi), !voices.isEmpty else {
            cont.resume(throwing: ExtractError.notCaptured("регион/анти-бот/таймаут")); return
        }
        cont.resume(returning: ExtractResult(voices: voices))
    }

    // MARK: parse /bnsi -> voices/qualities
    private static func parse(_ bnsi: [String: Any]) -> [VoiceTrack]? {
        guard let src = bnsi["hlsSource"] as? [[String: Any]] else { return nil }
        var out: [VoiceTrack] = []
        for s in src {
            let label = (s["label"] as? String) ?? "Озвучка"
            guard let q = s["quality"] as? [String: Any] else { continue }
            var quals: [Quality] = []
            for (h, v) in q {
                guard let height = Int(h) else { continue }
                let raw = String(describing: v)
                let url = raw.components(separatedBy: " or ").first?.trimmingCharacters(in: .whitespaces) ?? raw
                if url.hasPrefix("http") { quals.append(Quality(height: height, url: url)) }
            }
            if !quals.isEmpty { out.append(VoiceTrack(label: label, qualities: quals.sorted { $0.height > $1.height })) }
        }
        return out
    }
}

extension UIApplication {
    var keyWindowScene: UIWindow? {
        connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }.first { $0.isKeyWindow } ?? (connectedScenes.compactMap { $0 as? UIWindowScene }.first?.windows.first)
    }
}
