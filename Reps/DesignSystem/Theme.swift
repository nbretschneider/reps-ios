import SwiftUI

// Design tokens. The HSL initializer is carried over from Grams (which took it from
// GradeDays) -- it lets a light/dark pair be written inline from a web palette with no
// asset catalog entries at all.
//
// Three apps now share this spine, so the palette has to separate them at a glance in a
// home-screen folder: GradeDays is cyan/lime, Grams is indigo/amber, Reps is magenta with
// a green "done" state. The neutrals keep Grams' ladder but retint from hue 240 to 330 so
// the greys sit under magenta instead of fighting it.
//
// Designed dark-first. A gym app is used in a dark room with the phone on the floor, and
// the light palette is the variant, not the reference.

extension Color {
    /// Dynamic color from CSS-style HSL values, resolving per trait collection.
    init(lightHSL: (h: Double, s: Double, l: Double), darkHSL: (h: Double, s: Double, l: Double)) {
        self.init(uiColor: UIColor { traits in
            let hsl = traits.userInterfaceStyle == .dark ? darkHSL : lightHSL
            return UIColor(cssHue: hsl.h, saturation: hsl.s, lightness: hsl.l)
        })
    }

    // Surfaces
    static let rBackground = Color(lightHSL: (330, 16, 98), darkHSL: (330, 12, 7))
    static let rCard       = Color(lightHSL: (0, 0, 100),   darkHSL: (330, 10, 11))
    static let rCardBorder = Color(lightHSL: (330, 10, 90), darkHSL: (330, 8, 17))
    static let rMuted      = Color(lightHSL: (330, 12, 95), darkHSL: (330, 8, 16))

    // Text
    static let rForeground      = Color(lightHSL: (330, 16, 12), darkHSL: (330, 10, 96))
    static let rMutedForeground = Color(lightHSL: (330, 6, 46),  darkHSL: (330, 6, 64))

    // Brand
    static let rPrimary = Color(lightHSL: (335, 78, 48), darkHSL: (335, 82, 64))
    /// The "set complete" / "goal met" state. Green, because done is done -- and because
    /// the brand color is already the color of effort, so a win needs its own.
    static let rAccent      = Color(lightHSL: (152, 72, 36), darkHSL: (152, 66, 52))
    static let rDestructive = Color(lightHSL: (4, 74, 50),  darkHSL: (4, 74, 60))

    // Charts
    static let rChart1 = Color(lightHSL: (335, 78, 54), darkHSL: (335, 82, 66))
    static let rChart2 = Color(lightHSL: (152, 72, 40), darkHSL: (152, 66, 54))
    static let rChart3 = Color(lightHSL: (268, 70, 56), darkHSL: (268, 72, 68))
}

private extension UIColor {
    /// CSS HSL (hue 0-360, saturation/lightness 0-100) to UIColor, via HSB.
    /// The identity is exact, so a value written here and the same value in the marketing
    /// CSS or the Python icon renderer produce the same pixel.
    convenience init(cssHue h: Double, saturation s: Double, lightness l: Double) {
        let s = s / 100.0
        let l = l / 100.0
        let brightness = l + s * min(l, 1 - l)
        let saturation = brightness == 0 ? 0 : 2 * (1 - l / brightness)
        self.init(hue: h / 360.0, saturation: saturation, brightness: brightness, alpha: 1)
    }
}

enum RTheme {
    enum Spacing {
        static let page:   CGFloat = 16
        static let card:   CGFloat = 16
        static let stack:  CGFloat = 12
        static let inline: CGFloat = 8
        static let tight:  CGFloat = 4
    }

    enum Radius {
        static let card:    CGFloat = 16
        static let control: CGFloat = 12
        static let chip:    CGFloat = 10
    }

    /// System rounded throughout. No custom font is bundled -- if a face is added later,
    /// register it via `UIAppFonts` in project.yml and swap the body of this function.
    /// Keep `relativeTo:` on any `.custom` call: the fixed-size overload silently ignores
    /// Dynamic Type.
    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// The rep counter during a set. Far larger than anything in Grams because it is read
    /// from the floor at arm's length, upside down, mid-effort.
    static let counter       = font(size: 120, weight: .bold)
    static let hero          = font(size: 56, weight: .bold)
    static let title         = font(size: 28, weight: .bold)
    static let heading       = font(size: 20, weight: .bold)
    static let body          = font(size: 15)
    static let bodyMedium    = font(size: 15, weight: .medium)
    static let caption       = font(size: 13)
    static let captionMedium = font(size: 13, weight: .medium)

    /// The full-bleed gradient behind an active set. The one place the app leaves the card
    /// language behind, because a working set is not a document.
    static let sessionGradient = LinearGradient(
        colors: [
            Color(lightHSL: (335, 82, 56), darkHSL: (335, 80, 52)),
            Color(lightHSL: (350, 84, 46), darkHSL: (350, 82, 42))
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Text and controls drawn on top of `sessionGradient`. Fixed rather than dynamic:
    /// the gradient is the same in both appearances, so the contrast pair must be too.
    static let onSession = Color.white
    static let onSessionDim = Color.white.opacity(0.72)
}
