import Foundation
import Combine

/// User-tunable scrolling preferences, persisted to UserDefaults.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private enum Key {
        static let sensitivity = "settings.sensitivity"
        static let invertX = "settings.invertX"
        static let invertY = "settings.invertY"
        static let haptics = "settings.haptics"
        static let accessibilityFallback = "settings.accessibilityFallback"
    }

    /// Multiplier applied to incoming gyro velocity (0.2 = precise, 3.0 = fast).
    @Published var sensitivity: Double {
        didSet { defaults.set(sensitivity, forKey: Key.sensitivity) }
    }
    @Published var invertX: Bool {
        didSet { defaults.set(invertX, forKey: Key.invertX) }
    }
    @Published var invertY: Bool {
        didSet { defaults.set(invertY, forKey: Key.invertY) }
    }
    @Published var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Key.haptics) }
    }
    /// Attempts the in-process accessibility scroll action when no scroll view
    /// is found. Deliberately NOT labeled "system-wide" in the UI: public iOS
    /// APIs cannot reach other apps' content, so this only changes which
    /// in-app fallbacks are tried. See docs/LIMITATIONS.md.
    @Published var useAccessibilityFallback: Bool {
        didSet { defaults.set(useAccessibilityFallback, forKey: Key.accessibilityFallback) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.object(forKey: Key.sensitivity) as? Double
        sensitivity = stored ?? 1.0
        invertX = defaults.bool(forKey: Key.invertX)
        invertY = defaults.bool(forKey: Key.invertY)
        hapticsEnabled = defaults.object(forKey: Key.haptics) as? Bool ?? true
        useAccessibilityFallback = defaults.object(forKey: Key.accessibilityFallback) as? Bool ?? true
    }
}
