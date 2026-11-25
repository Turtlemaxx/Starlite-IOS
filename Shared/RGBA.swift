import SwiftUI
import UIKit

/// A colour that can be saved.
struct RGBA: Codable, Hashable {
    var r: Double, g: Double, b: Double, a: Double = 1

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(_ c: Color) {
        let u = UIColor(c)
        var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 1)
        u.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(Double(r), Double(g), Double(b), Double(a))
    }

    var color: Color { Color(red: r, green: g, blue: b, opacity: a) }
    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
}
