import SwiftUI
import WebKit

/// In-app browser tab. Because system-wide scrolling of Safari is impossible
/// from a sandboxed app (see docs/LIMITATIONS.md), this WKWebView is how you
/// air-scroll arbitrary websites: the AccessibilityScroller finds and drives
/// its internal scroll view like any other.
struct BrowserView: View {
    @State private var addressText = "https://en.wikipedia.org/wiki/Special:Random"
    @State private var currentURL = URL(string: "https://en.wikipedia.org/wiki/Special:Random")!

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Enter URL", text: $addressText)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(loadAddress)
                Button(action: loadAddress) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                }
            }
            .padding(10)
            WebView(url: currentURL)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func loadAddress() {
        var text = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") {
            text = "https://" + text
        }
        guard let url = URL(string: text) else { return }
        currentURL = url
    }
}

private struct WebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.lastRequestedURL = url
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Reload only when the address bar changed the URL, not on every
        // SwiftUI update — otherwise in-page navigation would keep resetting.
        guard context.coordinator.lastRequestedURL != url else { return }
        context.coordinator.lastRequestedURL = url
        webView.load(URLRequest(url: url))
    }

    final class Coordinator {
        var lastRequestedURL: URL?
    }
}
