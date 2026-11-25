import SwiftUI

/// What's behind every page: the theme's colour, its moving decoration
/// (petals, stars, bubbles), your picture, or the playing cover's colours.
struct ThemeBackground: View {
    var look: Look

    var body: some View {
        let p = look.prefs
        ZStack {
            look.palette.background
            if p.coverBackground, let c = look.coverColor {
                LinearGradient(colors: [c.opacity(look.palette.dark ? 0.45 : 0.3), .clear], startPoint: .top, endPoint: .bottom)
            } else {
                switch p.theme {
                case .cherry: Moving(kind: .petals, look: look)
                case .stars: Moving(kind: .stars, look: look)
                case .bubbles: Moving(kind: .bubbles, look: look)
                case .custom:
                    if let name = p.customPicture, let img = UIImage(contentsOfFile: Storage.support.appendingPathComponent(name).path) {
                        Image(uiImage: img).resizable().scaledToFill()
                            .overlay(look.palette.background.opacity(0.35))
                    }
                default: EmptyView()
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct Moving: View {
    enum Kind { case petals, stars, bubbles }
    var kind: Kind
    var look: Look

    var body: some View {
        let speed = look.prefs.motionSpeed
        let amount = look.prefs.motionAmount
        TimelineView(.animation(minimumInterval: 1 / 30, paused: speed < 0.01)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate * speed
                switch kind {
                case .stars: stars(ctx, size, t, amount)
                case .petals: petals(ctx, size, t, amount)
                case .bubbles: bubbles(ctx, size, t, amount)
                }
            }
        }
    }

    private func rnd(_ i: Int, _ k: Double) -> Double {
        let x = sin(Double(i) * 12.9898 + k * 78.233) * 43758.5453
        return x - floor(x)
    }

    private func stars(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double, _ amount: Double) {
        let n = Int(110 * amount)
        for i in 0..<n {
            let x = rnd(i, 1) * size.width, y = rnd(i, 2) * size.height
            let r = 0.5 + rnd(i, 3) * 1.4
            let tw = 0.45 + 0.55 * (0.5 + 0.5 * sin(t * (0.6 + rnd(i, 4) * 1.6) + rnd(i, 5) * 6.28))
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(Color(red: 0.9, green: 0.93, blue: 1).opacity(tw)))
        }
        // Now and then a shooting star.
        let cycle = 7.0
        let k = floor(t / cycle), f = (t - k * cycle) / 1.1
        if f < 1 {
            let sx = rnd(Int(k), 6) * size.width * 0.8 + size.width * 0.2, sy = rnd(Int(k), 7) * size.height * 0.4
            let head = CGPoint(x: sx - f * 220, y: sy + f * 120)
            var p = Path()
            p.move(to: head)
            p.addLine(to: CGPoint(x: head.x + 90, y: head.y - 49))
            ctx.stroke(p, with: .linearGradient(Gradient(colors: [.white.opacity(0.9 * (1 - f)), .clear]), startPoint: head, endPoint: CGPoint(x: head.x + 90, y: head.y - 49)), lineWidth: 1.6)
        }
    }

    private func petals(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double, _ amount: Double) {
        let n = Int(34 * amount)
        for i in 0..<n {
            let dur = 11 + rnd(i, 1) * 8
            let f = ((t + rnd(i, 2) * dur) / dur).truncatingRemainder(dividingBy: 1)
            let x = rnd(i, 3) * size.width + sin(t * 0.8 + Double(i)) * 26 + f * 60
            let y = -20 + f * (size.height + 40)
            let s = 5 + rnd(i, 4) * 6
            var c = ctx
            c.translateBy(x: x, y: y)
            c.rotate(by: .radians(t * (0.6 + rnd(i, 5)) + Double(i)))
            c.scaleBy(x: 1, y: 0.55 + 0.45 * abs(sin(t * 1.3 + Double(i))))
            c.fill(Path(ellipseIn: CGRect(x: -s, y: -s * 0.6, width: 2 * s, height: 1.2 * s)), with: .color(Color(red: 1, green: 0.72, blue: 0.78).opacity(0.75)))
        }
    }

    private func bubbles(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double, _ amount: Double) {
        let n = Int(18 * amount)
        for i in 0..<n {
            let dur = 9 + rnd(i, 1) * 9
            let cyc = (t + rnd(i, 2) * dur) / dur
            let k = floor(cyc), f = cyc - k
            // Each bubble pops at its own height, a different one every time.
            let popAt = 0.35 + rnd(i * 7 + Int(k), 3) * 0.6
            guard f < popAt else { continue }
            let r = 8 + rnd(i * 3 + Int(k), 4) * 22
            let x = rnd(i * 5 + Int(k), 5) * size.width + sin(t * 0.9 + Double(i)) * 14
            let y = size.height + r - f / popAt * popAt * (size.height + 2 * r)
            let rect = CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)
            let fade = min(1, (popAt - f) * 12)
            ctx.stroke(Path(ellipseIn: rect), with: .conicGradient(Gradient(colors: [Color.cyan, .purple, .pink, .yellow, .green, .cyan].map { $0.opacity(0.55 * fade) }), center: CGPoint(x: x, y: y)), lineWidth: 1.4)
            ctx.fill(Path(ellipseIn: CGRect(x: x - r * 0.55, y: y - r * 0.6, width: r * 0.45, height: r * 0.3)), with: .color(.white.opacity(0.35 * fade)))
        }
    }
}
