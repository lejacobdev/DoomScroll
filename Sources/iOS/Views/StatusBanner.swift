import SwiftUI

/// Floating banner shown while a scroll session is active: gyro icon, live
/// state, and a compact sensitivity slider for on-the-fly tuning.
struct StatusBanner: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var dispatcher: ScrollDispatcher
    @EnvironmentObject private var session: PhoneSessionManager

    var body: some View {
        if dispatcher.isScrolling {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "gyroscope")
                        .symbolEffect(.pulse, isActive: true)
                    Text("Scroll Mode Active")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: session.isWatchReachable
                          ? "applewatch.radiowaves.left.and.right"
                          : "applewatch.slash")
                        .foregroundStyle(session.isWatchReachable ? .green : .orange)
                }
                HStack(spacing: 8) {
                    Image(systemName: "tortoise.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Slider(value: $settings.sensitivity, in: 0.2...3.0)
                    Image(systemName: "hare.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
