import Charts
import SwiftUI

/// Dashboard tiles: icon + name on top (chevron when it opens something), content below, on glass — interactive glass when
/// tappable (Liquid Glass on iOS/macOS 26, the material before). Used by Piano's Statistiche (statistics) and Percorso (path) screens.
public struct DashboardTile<Content: View>: View {
    let title: String
    let icon: String
    let tappable: Bool
    let content: Content

    public init(title: String, icon: String, tappable: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.tappable = tappable
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(AppStyle.accent)
                Text(title).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if tappable {
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                }
            }
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)            // "Prima vista" in a half-width phone tile
            content
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glass(RoundedRectangle(cornerRadius: AppStyle.panelRadius, style: .continuous), interactive: tappable)
        .contentShape(RoundedRectangle(cornerRadius: AppStyle.panelRadius, style: .continuous))
    }
}

/// Tiles side by side, same width, as tall as the tallest one.
public struct TileRow<Content: View>: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) { content }
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The tile's value, big (SF Pro Display), with what it counts next to it.
public struct BigValue: View {
    let text: String
    let caption: String?
    let tint: Color?

    public init(text: String, caption: String? = nil, tint: Color? = nil) {
        self.text = text
        self.caption = caption
        self.tint = tint
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(text)
                .font(.display(34))
                .monospacedDigit()
                .foregroundStyle(tint ?? .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let caption {
                Text(caption).font(.subheadline).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }
}

/// A name with its state dot (green = on/OK, red = problem, grey = offline).
public struct DotRow: View {
    let ok: Bool
    let text: String
    let icon: String?

    public init(ok: Bool, text: String, icon: String? = nil) {
        self.ok = ok
        self.text = text
        self.icon = icon
    }

    public var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ok ? AppStyle.ok : (icon == nil ? AppStyle.bad : Color.secondary))
                .frame(width: 8, height: 8)
            if let icon {
                Image(systemName: icon).font(.caption).foregroundStyle(.secondary).frame(width: 18)
            }
            Text(text).font(.callout).lineLimit(1)
        }
    }
}

/// A metric over time, no axes: the shape, not the numbers (those are in the full charts).
public struct Sparkline: View {
    let points: [(Date, Double)]
    let tint: Color

    public init(points: [(Date, Double)], tint: Color = AppStyle.accent) {
        self.points = points
        self.tint = tint
    }

    public var body: some View {
        if points.count < 2 {
            Color.clear.frame(height: 44)
        } else {
            let low = points.map(\.1).min() ?? 0
            Chart(Array(points.enumerated()), id: \.offset) { _, p in
                AreaMark(x: .value("Time", p.0), yStart: .value("Low", low), yEnd: .value("Value", p.1))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", p.0), y: .value("Value", p.1))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 44)
            .accessibilityHidden(true)
        }
    }
}

/// Progress as a ring with the value in the middle (Piano's Percorso: how much of the tappa is done).
public struct ProgressRing: View {
    let value: Double
    let label: String
    let tint: Color

    public init(value: Double, label: String, tint: Color = AppStyle.accent) {
        self.value = value
        self.label = label
        self.tint = tint
    }

    public var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: 8)
            Circle().trim(from: 0, to: min(max(value, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label).font(.display(17)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6).padding(10)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}
