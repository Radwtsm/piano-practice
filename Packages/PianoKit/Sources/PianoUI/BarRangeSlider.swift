import DesignKit
import SwiftUI

/// The bars to practise: one track,
/// two thumbs = first and last bar. A drag moves the nearer thumb (on top of each other: left = start, right = end),
/// the numbers follow the finger, the trainer gets the range when you let go.
struct BarRangeSlider: View {
    let count: Int
    let a: Int
    let b: Int
    let scale: CGFloat
    let onChange: (Int, Int) -> Void
    @State private var drag: (a: Int, b: Int)?
    @State private var moving: Bool?          // true = end thumb, false = start thumb

    init(count: Int, a: Int, b: Int, scale: CGFloat, onChange: @escaping (Int, Int) -> Void) {
        self.count = count
        self.a = a
        self.b = b
        self.scale = scale
        self.onChange = onChange
    }

    var body: some View {
        let thumb = 30 * scale
        GeometryReader { geo in
            let w = max(1, geo.size.width - thumb), mid = geo.size.height / 2
            let cur = drag ?? (a, b)
            let x = { (v: Int) in thumb / 2 + CGFloat(v - 1) / CGFloat(max(1, count - 1)) * w }
            let bar = { (px: CGFloat) in min(count, max(1, Int(((px - thumb / 2) / w * CGFloat(count - 1)).rounded()) + 1)) }
            ZStack(alignment: .topLeading) {
                Capsule().fill(Color.white.opacity(0.18))   // the whole piece, visible on the glass
                    .frame(width: w, height: 6 * scale).position(x: geo.size.width / 2, y: mid)
                Capsule().fill(Theme.accent)
                    .frame(width: max(6 * scale, x(cur.b) - x(cur.a)), height: 6 * scale)
                    .position(x: (x(cur.a) + x(cur.b)) / 2, y: mid)
                knob(cur.a).position(x: x(cur.a), y: mid)
                knob(cur.b).position(x: x(cur.b), y: mid)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    var r = drag ?? (a, b)
                    let v = bar(g.location.x)
                    if moving == nil {
                        if r.a == r.b { if v != r.a { moving = v > r.a } }   // stacked: the direction decides
                        else { moving = abs(g.startLocation.x - x(r.b)) < abs(g.startLocation.x - x(r.a)) }
                    }
                    if moving == true { r.b = max(r.a, v) } else if moving == false { r.a = min(r.b, v) }
                    drag = r
                }
                .onEnded { _ in
                    if let r = drag, r != (a, b) { onChange(r.a, r.b) }
                    drag = nil
                    moving = nil
                })
        }
        .frame(height: 44 * scale)
        .frame(minWidth: 160 * scale)
        .accessibilityElement()
        .accessibilityLabel("Battute da \(a) a \(b) di \(count)")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: if b < count { onChange(a, b + 1) }
            case .decrement: if b > a { onChange(a, b - 1) }
            @unknown default: break
            }
        }
    }

    private func knob(_ v: Int) -> some View {
        Text("\(v)")
            .font(.system(size: 13 * scale, weight: .bold)).monospacedDigit()
            .foregroundStyle(Theme.dark)
            .frame(width: 30 * scale, height: 30 * scale)
            .background(Theme.paper, in: Circle())
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
    }
}
