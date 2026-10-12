import ScrollCore
import SwiftUI

/// Two quick flicks so "forward" and "sideways" match how this person holds the phone.
struct PhoneCalibrationSheet: View {
    @ObservedObject var model: RelayModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            switch model.phoneCalibration {
            case let .waiting(step):
                prompt(step, warning: nil)
            case let .wrongAxis(step):
                prompt(step, warning: step == .down ? "That looked sideways. Try tipping the top toward or away from you."
                                                    : "That looked forward and back. Try tilting it left or right.")
            case let .accepted(step):
                HeroBadge(symbol: "checkmark", tint: Color.good, size: 130)
                Text(step == .down ? "Got it" : "Nice").font(.display(30))
            case .done:
                HeroBadge(symbol: "checkmark.seal.fill", tint: Color.good, size: 130)
                Text("All set").font(.display(30))
                Text("Your phone now scrolls the way you flick it.")
                    .font(.bodyRounded).foregroundStyle(.secondary).multilineTextAlignment(.center)
            case .idle:
                EmptyView()
            }
            Spacer(minLength: 0)

            if model.phoneCalibration == .done {
                Button("Done") { model.finishPhoneCalibrationScreen() }.buttonStyle(.primary)
            } else {
                Button("Cancel") { model.cancelPhoneCalibration() }.buttonStyle(.secondary)
            }
        }
        .padding(DS.pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas.ignoresSafeArea())
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private func prompt(_ step: CalibrationSession.Step, warning: String?) -> some View {
        Text(step == .down ? "Step 1 of 2" : "Step 2 of 2")
            .font(.system(.subheadline, design: .rounded, weight: .semibold)).foregroundStyle(.secondary)
        HeroBadge(symbol: step == .down ? "arrow.down" : "arrow.right", size: 130)
            .symbolEffect(.pulse)
        Text(step == .down ? "Flick your phone the way you want to scroll down"
                           : "Tilt your phone the way you want to scroll right")
            .font(.display(26)).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        Text("Hold it upright like you're reading it, then give it one quick flick.")
            .font(.bodyRounded).foregroundStyle(.secondary).multilineTextAlignment(.center)
        if let warning {
            Label(warning, systemImage: "exclamationmark.triangle.fill")
                .font(.captionRounded).foregroundStyle(Color.warn).multilineTextAlignment(.center)
        }
    }
}
