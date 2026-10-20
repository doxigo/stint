import AppKit
import SwiftUI

/// Teamwork's palette (teamwork.com/brand) and the app's spacing scale.
enum Brand {
    /// tw-slate #1D1C39, the primary dark: header band.
    static let slate = Color(red: 29 / 255, green: 28 / 255, blue: 57 / 255)
    /// tw-purple #6438E0 for interactive accents. Dark Mode uses a lighter tint of it,
    /// because #6438E0 on a dark surface falls below 4.5:1 for small text.
    static let purple = Color(nsColor: NSColor(name: "twPurple") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 156 / 255, green: 130 / 255, blue: 245 / 255, alpha: 1)
            : NSColor(red: 100 / 255, green: 56 / 255, blue: 224 / 255, alpha: 1)
    })
    /// tw-purple #6438E0, fixed, for filled controls in both appearances: white labels stay at 6.9:1,
    /// where the lighter Dark Mode purple would drop them to about 3:1.
    static let purpleFill = Color(red: 100 / 255, green: 56 / 255, blue: 224 / 255)
    /// #5329CF, the filled purple under the pointer (the site's --purple-press).
    static let purplePress = Color(red: 83 / 255, green: 41 / 255, blue: 207 / 255)
    /// tw-pink #FF22B1. Dots only: the brand rules forbid it on buttons and large text.
    static let pink = Color(red: 1, green: 34 / 255, blue: 177 / 255)
}

/// 4-pt spacing scale: tight steps inside a group, generous steps between groups.
enum Space {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

/// The pink "live" dot on a running timer (the logo's dot).
/// ponytail: static on purpose. A pulse (repeatForever animation or symbol effect) redrew the window every
/// frame: 30–50 % CPU while open. If it should breathe again, use a CABasicAnimation on a layer (render server).
struct LiveDot: View {
    var body: some View {
        Circle()
            .fill(Brand.pink)
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }
}
