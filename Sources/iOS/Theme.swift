import SwiftUI
import UIKit

/// Visual language: calm grouped background, white rounded cards, big rounded
/// type, black pill buttons. Only semantic colors are used, so dark mode and
/// Increase Contrast work without extra code.
enum DS {
    static let corner: CGFloat = 26
    static let pad: CGFloat = 20
}

extension Color {
    static let canvas = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)
    static let ink = Color.primary
    static let inkInverse = Color(.systemBackground)
    static let softFill = Color.primary.opacity(0.06)
    static let good = Color(red: 0.20, green: 0.78, blue: 0.35)
    static let warn = Color(red: 1.00, green: 0.62, blue: 0.04)
    static let bad = Color(red: 1.00, green: 0.27, blue: 0.23)
}

extension Font {
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static let titleRounded = Font.system(.title2, design: .rounded, weight: .bold)
    static let bodyRounded = Font.system(.body, design: .rounded)
    static let captionRounded = Font.system(.footnote, design: .rounded)
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded, weight: .bold))
            .foregroundStyle(Color.inkInverse)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Color.ink, in: Capsule())
            .opacity(isEnabled ? 1 : 0.3)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded, weight: .semibold))
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Color.card, in: Capsule())
            .overlay(Capsule().stroke(Color.ink.opacity(0.12), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

// MARK: - Containers

struct Card<Content: View>: View {
    var padding: CGFloat = DS.pad
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card, in: RoundedRectangle(cornerRadius: DS.corner, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
            .padding(.horizontal, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Big round icon used as the hero of each screen.
struct HeroBadge: View {
    let symbol: String
    var tint: Color = .ink
    var size: CGFloat = 112

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.08)).frame(width: size, height: size)
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
        }
        .accessibilityHidden(true)
    }
}

struct StatusDot: View {
    let color: Color
    var body: some View {
        Circle().fill(color).frame(width: 9, height: 9).accessibilityHidden(true)
    }
}

struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.softFill)
                Capsule().fill(Color.ink)
                    .frame(width: max(8, geo.size.width * value))
                    .animation(.snappy, value: value)
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel("Setup progress")
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}

/// A selectable tile (used for gesture style and scroll target).
struct OptionTile: View {
    let title: String
    let subtitle: String
    let symbol: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(selected ? Color.inkInverse : Color.ink)
                    .frame(width: 44, height: 44)
                    .background(selected ? Color.ink : Color.softFill, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(.headline, design: .rounded, weight: .bold))
                    Text(subtitle).font(.captionRounded).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .foregroundStyle(Color.ink)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(selected ? Color.ink : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

struct InfoRow: View {
    let symbol: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 38, height: 38)
                .background(Color.softFill, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.body, design: .rounded, weight: .semibold))
                if let subtitle {
                    Text(subtitle).font(.captionRounded).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Haptics

enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
}

#Preview("Components") {
    VStack(spacing: 16) {
        HeroBadge(symbol: "applewatch.watchface")
        Card { InfoRow(symbol: "hand.draw", title: "Flick to scroll", subtitle: "Snap your wrist like turning a page") }
        Button("Continue") {}.buttonStyle(.primary)
        Button("Not now") {}.buttonStyle(.secondary)
    }
    .padding()
    .background(Color.canvas)
}
