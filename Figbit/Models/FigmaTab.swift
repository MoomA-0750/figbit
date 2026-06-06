import Foundation
import WebKit
import Combine

@Observable
class FigmaTab: Identifiable {
    let id = UUID()
    var title: String = "Figma"
    // 最後にこのタブを開いた（選択した）時刻。保持期間の判定に使う。
    var lastAccessedAt: Date = Date()
    var isLoading: Bool = false
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    var currentURL: URL?

    let webView: PencilAwareWebView
    private var cancellables: Set<AnyCancellable> = []

    init(processPool: WKProcessPool, dataStore: WKWebsiteDataStore, isHome: Bool = false) {
        let config = WKWebViewConfiguration()
        config.processPool = processPool
        config.websiteDataStore = dataStore
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        // ホームタブだけ、ファイルカードのクリックを捕捉してネイティブへ通知するJSを仕込む。
        // これによりホームWebView自身は遷移せず（＝ホームはタブにならない）、
        // ファイルは新規タブで開ける。ページ読込前から効くよう生成時に登録する。
        if isHome {
            let script = WKUserScript(
                source: FigmaTab.homeBridgeScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            config.userContentController.addUserScript(script)
        }

        // 端末フォントをFigmaへ供給する橋。documentStartで maxTouchPoints を 0 に偽装し
        // （0でないとFigmaはフォントヘルパーを探さない）、figmadaemon宛の fetch/XHR を横取りして
        // ネイティブ（CoreText）のデータで応答する。Figmaバンドルより先に当てる必要がある。
        let fontBridge = WKUserScript(
            source: FigmaTab.fontBridgeScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(fontBridge)
        // JS から端末フォントデータを取得するための応答付きハンドラ（page world）。
        config.userContentController.addScriptMessageHandler(
            FontHelper.shared, contentWorld: .page, name: "figbitFontHelper"
        )

        let webView = PencilAwareWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        webView.allowsBackForwardNavigationGestures = false
        self.webView = webView

        webView.publisher(for: \.title)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] t in self?.title = FigmaTab.cleanTitle(t) }
            .store(in: &cancellables)

        webView.publisher(for: \.isLoading)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in self?.isLoading = v }
            .store(in: &cancellables)

        webView.publisher(for: \.canGoBack)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in self?.canGoBack = v }
            .store(in: &cancellables)

        webView.publisher(for: \.canGoForward)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in self?.canGoForward = v }
            .store(in: &cancellables)

        webView.publisher(for: \.url)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in self?.currentURL = v }
            .store(in: &cancellables)
    }

    func load(url: URL = URL(string: "https://www.figma.com/files")!) {
        webView.load(URLRequest(url: url))
    }

    // ホームWebViewに仕込むクリック傍受スクリプト。
    // ファイル（design/file/board/slides/proto + キー）へのリンクのクリックを capture フェーズで捕まえ、
    // Figma自身のSPA遷移を止めて（stopImmediatePropagation+preventDefault）、URLをネイティブへ渡す。
    // ネイティブ側はそれを新規タブで開くので、ホーム自体は figma.com/files に留まる。
    static let homeBridgeScript = """
    (function(){
      if (window.__figbitHomeBridge) return;
      window.__figbitHomeBridge = true;
      function fileHref(t){
        var a = t && t.closest ? t.closest('a[href]') : null;
        if(!a) return null;
        try{
          var u = new URL(a.href, location.href);
          if(!/(^|\\.)figma\\.com$/.test(u.hostname)) return null;
          var p = u.pathname.split('/').filter(Boolean);
          if(p.length>=2 && ['design','file','board','slides','proto'].indexOf(p[0])>=0 && p[1]) return u.href;
        }catch(e){}
        return null;
      }
      document.addEventListener('click', function(e){
        var href = fileHref(e.target);
        if(!href) return;
        e.preventDefault();
        e.stopImmediatePropagation();
        try{ window.webkit.messageHandlers.figbitOpenFile.postMessage(href); }catch(err){}
      }, true);
    })();
    """

    // 端末フォントをFigmaへ供給する橋。
    // 1) maxTouchPoints を 0 に偽装（0でないとFigmaはフォントヘルパーを探さない）。
    // 2) figmadaemon.com 宛の fetch / XMLHttpRequest を横取りし、/figma/version・/figma/font-files・
    //    /figma/font-file をネイティブ（figbitFontHelper ハンドラ＝CoreText）の応答で満たす。
    //    それ以外のエンドポイントは素通し（失敗してよい）。
    // page world で動かし、同じworldに登録した応答付きハンドラを await で呼ぶ。
    static let fontBridgeScript = """
    (function(){
      if (window.__figbitFontBridge) return;
      window.__figbitFontBridge = true;

      try { Object.defineProperty(navigator, 'maxTouchPoints', { get: function(){ return 0; }, configurable: true }); } catch(e){}
      try { delete window.ontouchstart; } catch(e){}

      function log(m){ try{ window.webkit.messageHandlers.figbitFontProbe.postMessage(m);}catch(e){} }
      function isDaemon(u){
        try { return /(^|\\.)figmadaemon\\.com$/.test(new URL(String(u), location.href).hostname); }
        catch(e){ return false; }
      }
      function call(op, file){
        return window.webkit.messageHandlers.figbitFontHelper.postMessage(file != null ? {op:op, file:file} : {op:op});
      }
      function b64ToBytes(b64){
        var bin = atob(b64), len = bin.length, bytes = new Uint8Array(len);
        for (var i=0;i<len;i++) bytes[i] = bin.charCodeAt(i);
        return bytes;
      }
      function handledPath(p){
        return p === '/figma/version' || p === '/figma/font-files' || p === '/figma/font-file';
      }

      async function buildBody(path, url){
        if (path === '/figma/version')    { return { json: await call('version') }; }
        if (path === '/figma/font-files') { return { json: await call('font-files') }; }
        var b64 = await call('font-file', url.searchParams.get('file'));
        return { bytes: b64ToBytes(b64) };
      }

      // ---- fetch ----
      var of = window.fetch;
      window.fetch = function(input, init){
        try {
          var u = (typeof input === 'string') ? input : (input && input.url) || '';
          if (isDaemon(u)) {
            var url = new URL(String(u), location.href);
            if (handledPath(url.pathname)) {
              log('served fetch ' + url.pathname);
              return buildBody(url.pathname, url).then(function(r){
                if (r.json !== undefined) {
                  return new Response(JSON.stringify(r.json), { status:200, headers:{'Content-Type':'application/json'} });
                }
                return new Response(r.bytes, { status:200, headers:{'Content-Type':'application/octet-stream'} });
              }).catch(function(e){ return new Response('', { status:404 }); });
            }
          }
        } catch(e){}
        return of.apply(this, arguments);
      };

      // ---- XMLHttpRequest ----
      function define(o,k,v){ try{ Object.defineProperty(o,k,{configurable:true,get:function(){return v;}}); }catch(e){} }
      var xo = XMLHttpRequest.prototype.open;
      var xs = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function(method, url){
        try {
          if (isDaemon(url)) {
            var u = new URL(String(url), location.href);
            if (handledPath(u.pathname)) this.__figbitDaemon = u;
          }
        } catch(e){}
        return xo.apply(this, arguments);
      };
      XMLHttpRequest.prototype.send = function(body){
        var u = this.__figbitDaemon;
        if (!u) return xs.apply(this, arguments);
        var xhr = this;
        log('served xhr ' + u.pathname);
        (async function(){
          try {
            var r = await buildBody(u.pathname, u);
            var text, resp, ctype;
            if (r.json !== undefined) {
              text = JSON.stringify(r.json); ctype = 'application/json';
              resp = (xhr.responseType === 'json') ? r.json : text;
            } else {
              text = ''; ctype = 'application/octet-stream';
              resp = (xhr.responseType === 'arraybuffer') ? r.bytes.buffer : text;
            }
            define(xhr, 'readyState', 4);
            define(xhr, 'status', 200);
            define(xhr, 'statusText', 'OK');
            define(xhr, 'responseText', text);
            define(xhr, 'response', resp);
            define(xhr, 'responseURL', u.href);
            xhr.getResponseHeader = function(h){ return /content-type/i.test(h) ? ctype : null; };
            xhr.getAllResponseHeaders = function(){ return 'content-type: ' + ctype + '\\r\\n'; };
            if (typeof xhr.onreadystatechange === 'function') xhr.onreadystatechange();
            xhr.dispatchEvent(new Event('readystatechange'));
            if (typeof xhr.onload === 'function') xhr.onload();
            xhr.dispatchEvent(new Event('load'));
            xhr.dispatchEvent(new Event('loadend'));
          } catch(e){
            define(xhr, 'readyState', 4);
            define(xhr, 'status', 0);
            if (typeof xhr.onerror === 'function') xhr.onerror();
            xhr.dispatchEvent(new Event('error'));
          }
        })();
      };
    })();
    """

    // ブラウザのページタイトル末尾に付く「 – Figma」等のサフィックスを取り除く。
    // 「Figma Slides」を「Figma」より先に判定して " Slides" の取り残しを防ぐ。
    static func cleanTitle(_ raw: String?) -> String {
        guard var t = raw, !t.isEmpty else { return "Figma" }
        let suffixes = [
            " – Figma Slides", " - Figma Slides",
            " – FigJam", " - FigJam",
            " – Figma", " - Figma",
        ]
        for s in suffixes where t.hasSuffix(s) {
            t = String(t.dropLast(s.count))
            break
        }
        t = t.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Figma" : t
    }

    // 開いているページの種類。URLパスから判定し、タブのアイコンに使う。
    enum Kind {
        case design, figjam, slides, other
        var symbol: String {
            switch self {
            case .design: return "paintbrush.pointed"
            case .figjam: return "hand.draw"
            case .slides: return "play.rectangle"
            case .other:  return "doc"
            }
        }
    }

    var kind: Kind {
        guard let path = currentURL?.path else { return .other }
        if path.hasPrefix("/design/") || path.hasPrefix("/file/") { return .design }
        if path.hasPrefix("/board/") { return .figjam }
        if path.hasPrefix("/slides/") { return .slides }
        return .other
    }
}
