import AppKit
import CoreGraphics
import ScrollCore

/// Decides where scroll events land.
enum TargetResolver {
    /// Returns the point to post at, or nil to use the current pointer position.
    static func point(for target: ScrollTarget) -> CGPoint? {
        switch target {
        case .pointer:
            return nil
        case .iPhoneMirroring:
            return iPhoneMirroringCenter()
        }
    }

    static func iPhoneMirroringCenter() -> CGPoint? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        for window in list {
            guard (window[kCGWindowOwnerName as String] as? String) == "iPhone Mirroring",
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width > 100, bounds.height > 100
            else { continue }
            return CGPoint(x: bounds.midX, y: bounds.midY)
        }
        return nil
    }

    static var isiPhoneMirroringVisible: Bool { iPhoneMirroringCenter() != nil }
}
