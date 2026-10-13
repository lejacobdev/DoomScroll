import SwiftUI
import WebKit

/// Owns the one web view, so the page survives closing and reopening the browser.
@MainActor
final class BrowserModel: NSObject, ObservableObject, WKUIDelegate {
    static let shared = BrowserModel()
    private static let home = URL(string: ScrollApp.instagram.startURL)!
    private static let lastURLKey = "browserLastURL"

    let webView: WKWebView
    @Published var addressText = ""
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    /// Bumped on every like so the browser can show a heart.
    @Published private(set) var likeCount = 0
    private var observers: [NSKeyValueObservation] = []
    /// Host of the page being shown or loading, known before the web view reports it.
    private var currentHost: String?

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        // After the Watch moves to the next reel nobody taps the page, so videos
        // must be allowed to start playing on their own.
        config.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: config)
        view.allowsBackForwardNavigationGestures = true
        webView = view
        super.init()
        webView.uiDelegate = self
        observers = [
            webView.observe(\.canGoBack) { [weak self] _, _ in
                Task { @MainActor in self?.refreshState() }
            },
            webView.observe(\.canGoForward) { [weak self] _, _ in
                Task { @MainActor in self?.refreshState() }
            },
            webView.observe(\.isLoading) { [weak self] _, _ in
                Task { @MainActor in self?.refreshState() }
            },
            webView.observe(\.url) { [weak self] _, _ in
                Task { @MainActor in self?.refreshState() }
            },
        ]
        let saved = UserDefaults.standard.string(forKey: Self.lastURLKey).flatMap(URL.init(string:))
        load(saved ?? Self.home)
    }

    private func load(_ url: URL) {
        currentHost = url.host
        webView.load(URLRequest(url: url))
    }

    /// Opens the chosen app's site, unless the browser is already on it.
    func open(_ app: ScrollApp) {
        let host = currentHost ?? ""
        if let domain = app.domain {
            if host.hasSuffix(domain) { return }
        } else {
            // "Web" keeps whatever page you're on, unless that is one of the app sites.
            let onAppSite = ScrollApp.allCases.contains { $0.domain.map(host.hasSuffix) ?? false }
            if !host.isEmpty && !onAppSite { return }
        }
        if let url = URL(string: app.startURL) { load(url) }
    }

    private func refreshState() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        if let host = webView.url?.host { currentHost = host }
        if let url = webView.url?.absoluteString {
            addressText = url
            if url.hasPrefix("http") { UserDefaults.standard.set(url, forKey: Self.lastURLKey) }
        }
    }

    /// Turns what the user typed into a page: a full URL, a bare domain, or a search.
    func go(to input: String) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if text.contains("://"), let url = URL(string: text) {
            load(url)
        } else if text.contains("."), !text.contains(" "), let url = URL(string: "https://" + text) {
            load(url)
        } else {
            var components = URLComponents(string: "https://duckduckgo.com/")!
            components.queryItems = [URLQueryItem(name: "q", value: text)]
            if let url = components.url { load(url) }
        }
    }

    /// Moves a full-screen feed by one video. Reel pages scroll an inner container
    /// in whole screens, so find the scrollable element under the middle of the
    /// page and move it by one screen; fall back to the page itself, then to the
    /// arrow keys that some players listen for. `direction` is +1 for next, -1 for previous.
    func stepReel(_ direction: Int) {
        let script = """
        (function (dir) {
          function scrollable(el) {
            while (el && el !== document.body && el !== document.documentElement) {
              var s = getComputedStyle(el);
              var y = s.overflowY;
              if ((y === 'auto' || y === 'scroll' || y === 'overlay') && el.scrollHeight > el.clientHeight + 4) return el;
              el = el.parentElement;
            }
            return null;
          }
          var el = document.elementFromPoint(window.innerWidth / 2, window.innerHeight / 2);
          var box = scrollable(el);
          if (box) { box.scrollBy({ top: dir * box.clientHeight, behavior: 'smooth' }); return 'container'; }
          var root = document.scrollingElement || document.documentElement;
          if (root.scrollHeight > window.innerHeight + 4) {
            window.scrollBy({ top: dir * window.innerHeight, behavior: 'smooth' }); return 'page';
          }
          var key = dir > 0 ? 'ArrowDown' : 'ArrowUp';
          var code = dir > 0 ? 40 : 38;
          ['keydown', 'keyup'].forEach(function (type) {
            document.dispatchEvent(new KeyboardEvent(type, { key: key, code: key, keyCode: code, which: code, bubbles: true }));
          });
          return 'key';
        })(\(direction > 0 ? 1 : -1));
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    /// Likes the post in view. Feeds show many posts, so this presses the like button
    /// closest to the middle of the screen, and never one that is already liked (a
    /// double tap only ever likes). Sites without a recognisable button get a double-click
    /// in the middle of the page instead.
    func likeCurrent() {
        likeCount += 1
        let script = """
        (function () {
          var selectors = [
            'svg[aria-label="Like"]',
            '[data-e2e="like-icon"]', '[data-e2e="browse-like-icon"]', '[data-e2e="video-player-like-icon"]',
            'ytm-like-button-renderer button', 'like-button-view-model button',
            'button[aria-label^="like this" i]', 'button[aria-label="Like" i]', '[role="button"][aria-label="Like" i]'
          ];
          var mid = window.innerHeight / 2, best = null, bestDist = Infinity;
          selectors.forEach(function (sel) {
            document.querySelectorAll(sel).forEach(function (el) {
              var btn = el.closest('button,[role="button"]') || el;
              var label = (btn.getAttribute('aria-label') || el.getAttribute('aria-label') || '').toLowerCase();
              if (label.indexOf('unlike') >= 0 || btn.getAttribute('aria-pressed') === 'true') return;
              var r = btn.getBoundingClientRect();
              if (r.width === 0 || r.bottom < 0 || r.top > window.innerHeight) return;
              var d = Math.abs((r.top + r.bottom) / 2 - mid);
              if (d < bestDist) { bestDist = d; best = btn; }
            });
          });
          if (best) { best.click(); return 'button'; }
          var x = window.innerWidth / 2, y = window.innerHeight / 2;
          var target = document.elementFromPoint(x, y);
          if (!target) return 'none';
          ['click', 'click', 'dblclick'].forEach(function (type, i) {
            target.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, clientX: x, clientY: y, detail: i + 1 }));
          });
          return 'dblclick';
        })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() {
        if isLoading {
            webView.stopLoading()
        } else {
            webView.reload()
        }
    }

    // Links that ask for a new window would otherwise do nothing.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }
}

/// Full-screen browser that the Watch scrolls. This is how DoomScroll scrolls
/// the iPhone with no Mac: iOS only lets an app scroll its own content.
struct BrowserScreen: View {
    @ObservedObject private var browser = BrowserModel.shared
    @ObservedObject private var scroller = PhoneScroller.shared
    @Environment(\.dismiss) private var dismiss
    @FocusState private var addressFocused: Bool
    @State private var barHidden = false
    @State private var heartVisible = false

    var body: some View {
        VStack(spacing: 0) {
            if !barHidden { toolbar }
            ZStack(alignment: .top) {
                WebViewContainer(webView: browser.webView)
                Button { withAnimation(.snappy) { barHidden.toggle() } } label: {
                    Image(systemName: barHidden ? "chevron.down" : "chevron.up")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel(barHidden ? "Show address bar" : "Hide address bar for full screen")
                Image(systemName: "heart.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 12)
                    .scaleEffect(heartVisible ? 1 : 0.4)
                    .opacity(heartVisible ? 1 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                if scroller.watchActive {
                    Label("Scrolling with your Watch", systemImage: "applewatch.radiowaves.left.and.right")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: scroller.watchActive)
            .onChange(of: browser.likeCount) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) { heartVisible = true }
                Task {
                    try? await Task.sleep(nanoseconds: 650_000_000)
                    withAnimation(.easeOut(duration: 0.25)) { heartVisible = false }
                }
            }
        }
        .background(Color.canvas)
    }

    private var toolbar: some View {
        VStack(spacing: 6) {
            addressRow
            HStack(spacing: 10) {
                ForEach(ScrollApp.allCases) { app in
                    Button { browser.open(app) } label: { AppBubble(app: app, size: 34) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(app.title)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var addressRow: some View {
        HStack(spacing: 6) {
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .accessibilityLabel("Close browser")
            Button { browser.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!browser.canGoBack)
                .accessibilityLabel("Back")
            Button { browser.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!browser.canGoForward)
                .accessibilityLabel("Forward")
            TextField("Search or enter website", text: $browser.addressText)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.webSearch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($addressFocused)
                .onSubmit {
                    browser.go(to: browser.addressText)
                    addressFocused = false
                }
            Button { browser.reload() } label: {
                Image(systemName: browser.isLoading ? "xmark.circle" : "arrow.clockwise")
            }
            .accessibilityLabel(browser.isLoading ? "Stop loading" : "Reload")
        }
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(Color.ink)
    }
}

/// Hosts the shared web view and tells the scroller which scroll view to drive.
private struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        PhoneScroller.shared.attach(webView.scrollView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: ()) {
        PhoneScroller.shared.detach(uiView.scrollView)
    }
}
