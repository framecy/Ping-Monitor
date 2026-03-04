import SwiftUI

struct Theme {
    struct Colors {
        static var background: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                if appearance.name == .darkAqua || appearance.name == .vibrantDark {
                    return NSColor(hex: "141414")
                } else {
                    return NSColor(hex: "F5F5F7")
                }
            })
        }
        
        static var cardBackground: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                if appearance.name == .darkAqua || appearance.name == .vibrantDark {
                    return NSColor(hex: "1F1F1F")
                } else {
                    return NSColor.white
                }
            })
        }
        
        static var sidebarBackground: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                if appearance.name == .darkAqua || appearance.name == .vibrantDark {
                    return NSColor(hex: "1A1A1A")
                } else {
                    return NSColor(hex: "EBEBEB")
                }
            })
        }
        
        static let accentBlue = Color(hex: "007AFF")
        static let accentGreen = Color(hex: "34C759")
        static let accentPurple = Color(hex: "AF52DE")
        static let accentOrange = Color(hex: "FF9500")
        static let accentRed = Color(hex: "FF3B30")
        static let accentCyan = Color(hex: "32ADE6")
        
        static var textPrimary: Color {
            Color(nsColor: .labelColor)
        }
        
        static var textSecondary: Color {
            Color(nsColor: .secondaryLabelColor)
        }
        
        static var textTertiary: Color {
            Color(nsColor: .tertiaryLabelColor)
        }
        
        static var separator: Color {
            Color(nsColor: .separatorColor)
        }
    }
    
    struct Fonts {
        static func display(_ size: CGFloat) -> Font {
            .system(size: size, weight: .bold, design: .rounded)
        }
        
        static func body(_ size: CGFloat) -> Font {
            .system(size: size, weight: .regular, design: .rounded)
        }
        
        static func number(_ size: CGFloat) -> Font {
            .system(size: size, weight: .medium, design: .monospaced)
        }
    }
    
    struct Layout {
        static let cardCornerRadius: CGFloat = 12
        static let cardPadding: CGFloat = 16
        static let gridSpacing: CGFloat = 16
    }
}

extension Color {
    init(hex: String) {
        self.init(nsColor: NSColor(hex: hex))
    }
}

extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}

