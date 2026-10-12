import SwiftUI
import WebKit

/// Owns the one web view, so the page survives closing and reopening the browser.
@MainActor
final class BrowserModel: NSObject, ObservableObject, WKUIDelegate {
    static let shared = BrowserModel()
    private static let home = URL(string: "https://duckduckgo.com")!

    let webView: WKWebView
    @Published var addressText = ""
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    private var observers: [NSKeyValueObservation] = []

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
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
        webView.load(URLRequest(url: Self.home))
    }

    private func refreshState() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        if let url = webView.url?.absoluteString { addressText = url }
    }

    /// Turns what the user typed into a page: a full URL, a bare domain, or a search.
    func go(to input: String) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if text.contains("://"), let url = URL(string: text) {
            webView.load(URLRequest(url: url))
        } else if text.contains("."), !text.contains(" "), let url = URL(string: "https://" + text) {
            webView.load(URLRequest(url: url))
        } else {
            var components = URLComponents(string: "https://duckduckgo.com/")!
            components.queryItems = [URLQueryItem(name: "q", value: text)]
            if let url = components.url { webView.load(URLRequest(url: url)) }
        }
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

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            ZStack(alignment: .top) {
                WebViewContainer(webView: browser.webView)
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
        }
        .background(Color.canvas)
    }

    private var toolbar: some View {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
