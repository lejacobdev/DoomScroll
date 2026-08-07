import SwiftUI

/// An endless demo feed — a guaranteed-scrollable playground for testing the
/// Watch air-scroll pipeline.
struct FeedView: View {
    private static let icons = [
        "sparkles", "flame.fill", "bolt.fill", "star.fill", "heart.fill",
        "moon.stars.fill", "cloud.rain.fill", "leaf.fill", "pawprint.fill",
        "gamecontroller.fill", "music.note", "camera.fill",
    ]
    private static let hues: [Color] = [
        .blue, .purple, .pink, .orange, .teal, .indigo, .mint, .red,
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(1...300, id: \.self) { index in
                        card(index: index)
                    }
                }
                .padding()
            }
            .navigationTitle("Feed")
        }
    }

    private func card(index: Int) -> some View {
        let icon = Self.icons[index % Self.icons.count]
        let hue = Self.hues[index % Self.hues.count]
        return HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(hue.gradient, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text("Post #\(index)")
                    .font(.headline)
                Text("Tilt your wrist to keep the doom flowing. This card exists purely so you have something to scroll.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16))
    }
}
