import SwiftUI
import Charts
import ArrcadeKit

// MARK: - Glass containers

/// A rounded Liquid Glass panel used for dashboard cards and grouped content.
struct GlassCard<Content: View>: View {
    var title: String?
    var symbol: String?
    var tint: Color?
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content
    @AppStorage(Prefs.tintedGlass) private var tinted = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Label {
                    Text(title).font(.headline)
                } icon: {
                    if let symbol { Image(systemName: symbol).foregroundStyle(tint ?? .accentColor) }
                }
            }
            content()
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(tinted ? tint?.opacity(0.08) : nil), in: .rect(cornerRadius: 20))
    }
}

/// Section header used inside scroll views.
struct SectionHeader: View {
    var title: String
    var subtitle: String?
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.semibold))
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
            Spacer()
        }
    }
}

/// Small tinted capsule.
struct Pill: View {
    var text: String
    var color: Color = .secondary
    var symbol: String?
    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text).lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(color)
        .background(color.opacity(0.14), in: .capsule)
    }
}

struct StatTile: View {
    var title: String
    var value: String
    var symbol: String
    var tint: Color = .accentColor
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.title3.weight(.semibold)).monospacedDigit().contentTransition(.numericText())
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

struct LinearProgress: View {
    var value: Double
    var tint: Color = .accentColor
    var height: CGFloat = 5
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(tint.gradient)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
        .animation(.smooth, value: value)
    }
}

// MARK: - States

struct LoadingView: View {
    var label = "Loading…"
    var body: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.large)
            Text(label).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorView: View {
    var message: String
    var retry: (() -> Void)?
    var body: some View {
        ContentUnavailableView {
            Label("Couldn't Load", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message).textSelection(.enabled)
        } actions: {
            if let retry {
                Button("Try Again", action: retry).buttonStyle(.glassProminent)
            }
            SettingsLink { Text("Open Settings") }.buttonStyle(.glass)
        }
    }
}

struct NotConfiguredView: View {
    var service: ServiceKind
    var body: some View {
        ContentUnavailableView {
            Label("\(service.displayName) Not Connected", systemImage: service.symbol)
        } description: {
            Text("Add your \(service.displayName) server in Settings to use this section.")
        } actions: {
            SettingsLink { Text("Open Settings…") }.buttonStyle(.glassProminent)
        }
    }
}

/// Switch over a load state, showing loading / error / content.
struct StateSwitch<Content: View>: View {
    var state: LoadState
    var isEmpty: Bool
    var retry: () -> Void
    @ViewBuilder var content: () -> Content
    var body: some View {
        if isEmpty, let e = state.error {
            ErrorView(message: e, retry: retry)
        } else if isEmpty, state.isLoading || state == .idle {
            LoadingView()
        } else {
            content()
        }
    }
}

// MARK: - Toasts

struct ToastOverlay: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        VStack(spacing: 8) {
            ForEach(app.toasts) { toast in
                HStack(spacing: 10) {
                    Image(systemName: icon(toast.style)).foregroundStyle(color(toast.style))
                    Text(toast.message).lineLimit(4).textSelection(.enabled)
                }
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular.tint(color(toast.style).opacity(0.12)), in: .capsule)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onTapGesture { app.toasts.removeAll { $0.id == toast.id } }
            }
        }
        .padding(.bottom, 20)
        .frame(maxWidth: 560)
    }
    func icon(_ s: Toast.Style) -> String {
        switch s { case .success: "checkmark.circle.fill"; case .error: "exclamationmark.triangle.fill"; case .info: "info.circle.fill" }
    }
    func color(_ s: Toast.Style) -> Color {
        switch s { case .success: .green; case .error: .red; case .info: .blue }
    }
}

// MARK: - Layout

/// Wrapping horizontal layout for chips/tags.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxWidth, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}

// MARK: - Charts

struct SpeedSparkline: View {
    var samples: [SpeedSample]
    var showsUpload = true
    var showsAxis = true
    var body: some View {
        Chart {
            ForEach(samples) { s in
                AreaMark(x: .value("t", s.date), y: .value("Down", s.down), series: .value("s", "Down"))
                    .foregroundStyle(.linearGradient(colors: [.blue.opacity(0.45), .blue.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("t", s.date), y: .value("Down", s.down), series: .value("s", "DownLine"))
                    .foregroundStyle(.blue)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                if showsUpload {
                    LineMark(x: .value("t", s.date), y: .value("Up", s.up), series: .value("s", "Up"))
                        .foregroundStyle(.green)
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let n = v.as(Int.self) { Text(Int64(n).byteString + "/s").font(.caption2) }
                }
            }
        }
        .chartYAxis(showsAxis ? .automatic : .hidden)
        .chartLegend(.hidden)
    }
}

// MARK: - Misc

struct KeyValueRow: View {
    var key: String
    var value: String
    var body: some View {
        LabeledContent(key) {
            Text(value).textSelection(.enabled).multilineTextAlignment(.trailing)
        }
    }
}

struct RatingBadge: View {
    var source: String
    var value: String
    var color: Color
    var body: some View {
        HStack(spacing: 4) {
            Text(source).font(.caption2.weight(.heavy)).foregroundStyle(color)
            Text(value).font(.caption.weight(.semibold)).monospacedDigit()
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .glassEffect(.regular, in: .capsule)
    }
}

/// Poster tile with title & subtitle used in library and discover grids.
struct PosterTile<Badge: View>: View {
    var urls: [URL?]
    var title: String
    var subtitle: String?
    var width: CGFloat
    var symbol: String = "film"
    var dimmed = false
    @ViewBuilder var badge: () -> Badge
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImage(urls, pixelWidth: Int(width * 2), symbol: symbol)
                .frame(width: width, height: width * 1.5)
                .clipShape(.rect(cornerRadius: 12))
                .overlay(alignment: .topTrailing) { badge().padding(6) }
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(hovering ? 0.35 : 0.08), lineWidth: 1) }
                .opacity(dimmed ? 0.55 : 1)
                .shadow(color: .black.opacity(hovering ? 0.35 : 0.18), radius: hovering ? 12 : 5, y: hovering ? 6 : 2)
                .scaleEffect(hovering ? 1.03 : 1)
            Text(title).font(.callout.weight(.medium)).lineLimit(1)
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        }
        .frame(width: width)
        .contentShape(.rect)
        .onHover { h in withAnimation(.snappy(duration: 0.18)) { hovering = h } }
    }
}

extension PosterTile where Badge == EmptyView {
    init(urls: [URL?], title: String, subtitle: String?, width: CGFloat, symbol: String = "film", dimmed: Bool = false) {
        self.init(urls: urls, title: title, subtitle: subtitle, width: width, symbol: symbol, dimmed: dimmed) { EmptyView() }
    }
}

struct StatusDot: View {
    var color: Color
    var body: some View { Circle().fill(color).frame(width: 8, height: 8) }
}

/// Large header with backdrop used in detail screens.
struct BackdropHeader<Content: View>: View {
    var backdrop: [URL?]
    var poster: [URL?]
    var posterSymbol = "film"
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(backdrop, pixelWidth: 1600) { Rectangle().fill(.quaternary) }
                .frame(height: 340)
                .frame(maxWidth: .infinity)
                .clipped()
                .backgroundExtensionEffect()
                .overlay {
                    LinearGradient(colors: [.clear, .black.opacity(0.25), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                }
            HStack(alignment: .bottom, spacing: 20) {
                RemoteImage(poster, pixelWidth: 400, symbol: posterSymbol)
                    .frame(width: 150, height: 225)
                    .clipShape(.rect(cornerRadius: 14))
                    .shadow(radius: 16, y: 8)
                content()
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            .padding(24)
        }
    }
}
