import SwiftUI
import UIKit

/// The places DoomScroll can scroll. Each opens the web version in the DoomScroll
/// browser: iOS doesn't let one app control another app's own screen.
enum ScrollApp: String, CaseIterable, Identifiable {
    case tiktok, instagram, youtube, snapchat, web

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tiktok: "TikTok"
        case .instagram: "Instagram"
        case .youtube: "YouTube"
        case .snapchat: "Snapchat"
        case .web: "Web"
        }
    }

    var startURL: String {
        switch self {
        case .tiktok: "https://www.tiktok.com/foryou"
        case .instagram: "https://www.instagram.com/reels/"
        case .youtube: "https://www.youtube.com/shorts"
        case .snapchat: "https://www.snapchat.com/spotlight"
        case .web: "https://duckduckgo.com"
        }
    }

    /// Host suffix used to tell whether the browser is already on this app's site.
    var domain: String? {
        switch self {
        case .tiktok: "tiktok.com"
        case .instagram: "instagram.com"
        case .youtube: "youtube.com"
        case .snapchat: "snapchat.com"
        case .web: nil
        }
    }

    /// Name of an optional logo image in the asset catalog (see docs/LOGOS.md).
    var logoAsset: String { "Logo-\(rawValue)" }

    fileprivate var symbol: String {
        switch self {
        case .tiktok: "music.note"
        case .instagram: "camera.fill"
        case .youtube: "play.fill"
        case .snapchat: "bolt.fill"
        case .web: "globe"
        }
    }

    fileprivate var glyphColor: Color {
        self == .snapchat ? .black : .white
    }
}

/// A round app icon: the user's own logo image if one is in the asset catalog,
/// otherwise the app's brand colour with a simple icon.
struct AppBubble: View {
    let app: ScrollApp
    var size: CGFloat = 92
    var selected = false

    var body: some View {
        ZStack {
            if let logo = UIImage(named: app.logoAsset) {
                Image(uiImage: logo).resizable().scaledToFill()
            } else {
                fill
                VStack(spacing: 3) {
                    Image(systemName: app.symbol)
                        .font(.system(size: size * 0.34, weight: .bold))
                    if size >= 70 {
                        Text(app.title).font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                }
                .foregroundStyle(app.glyphColor)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.ink, lineWidth: selected ? 3 : 0).padding(-4))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var fill: some View {
        switch app {
        case .tiktok: Color.black
        case .instagram:
            LinearGradient(colors: [Color(red: 0.99, green: 0.69, blue: 0.24),
                                    Color(red: 0.89, green: 0.20, blue: 0.45),
                                    Color(red: 0.35, green: 0.25, blue: 0.70)],
                           startPoint: .bottomLeading, endPoint: .topTrailing)
        case .youtube: Color(red: 0.92, green: 0.13, blue: 0.13)
        case .snapchat: Color(red: 1.0, green: 0.99, blue: 0.0)
        case .web: Color(red: 0.0, green: 0.48, blue: 1.0)
        }
    }
}

/// The five apps in a honeycomb, like the Apple Watch app screen: two circles
/// nestled above three.
struct AppHoneycomb: View {
    let selected: ScrollApp?
    let onSelect: (ScrollApp) -> Void

    private let size: CGFloat = 92
    private let gap: CGFloat = 12

    var body: some View {
        // Hexagonal packing: rows are about 0.87 of a step apart.
        VStack(spacing: (size + gap) * 0.866 - size) {
            HStack(spacing: gap) { bubble(.tiktok); bubble(.instagram) }
            HStack(spacing: gap) { bubble(.youtube); bubble(.snapchat); bubble(.web) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func bubble(_ app: ScrollApp) -> some View {
        Button {
            Haptics.select()
            onSelect(app)
        } label: {
            AppBubble(app: app, size: size, selected: selected == app)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(app.title)
        .accessibilityHint("Opens \(app.title) in the DoomScroll browser")
    }
}
