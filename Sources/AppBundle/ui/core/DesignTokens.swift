import SwiftUI

// Shared geometry, opacity and motion tokens. Resolve semantic colors and material
// through ChromeAppearance so helper surfaces follow the selected app theme.

enum GlassToken {
    // Surface recipe (originally the sidebar surface, now shared by all chrome)
    static let tint = Color(hue: 0, saturation: 0, brightness: 0.50)
    static let tintOpacity: Double = 0.06
    static let scrimOpacity: Double = 0.58
    static let highlightPeak: Double = 0.08
    static let borderOpacity: Double = 0.10
    // Width of the refractive Liquid Glass edge band (macOS 26). Wider = more visible
    // refraction; the main knob for how pronounced the glassy border reads.
    static let refractiveBorderWidth: CGFloat = 3

    // Interactive fills layered on glass

    // Strokes around interactive elements

    // Text emphasis on glass
    static let textPrimary: Double = 0.92
}

enum RadiusToken {
    static let row: CGFloat = 8 // rows, drag proxies, small chips
    static let card: CGFloat = 10 // status cards, dropdown menus
    static let section: CGFloat = 12 // sidebar sections, tab strip, alert panels
    static let panel: CGFloat = 14 // panel outer edges
}

enum StrokeToken {
    static let hairline: CGFloat = 0.5
    static let control: CGFloat = 0.75
    static let emphasis: CGFloat = 1.0
}

struct ShadowToken {
    let opacity: Double
    let radius: CGFloat
    let y: CGFloat

    static let resting = ShadowToken(opacity: 0.15, radius: 6, y: 2)
    static let raised = ShadowToken(opacity: 0.18, radius: 8, y: 4)
    static let hover = ShadowToken(opacity: 0.35, radius: 12, y: 6)
}

extension View {
}

/// The shared glass surface: glass/blur base, dark scrim, neutral tint, top highlight,
/// hairline border.
struct GlassSurface<S: Shape>: View {
    let shape: S
    var hasHighlight: Bool = true
    var hasBorder: Bool = true

    var body: some View {
        ZStack {
            base
            shape.fill(Color.black.opacity(GlassToken.scrimOpacity))
            shape.fill(GlassToken.tint.opacity(GlassToken.tintOpacity))
                .blendMode(.plusLighter)
            if hasHighlight {
                shape.fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(GlassToken.highlightPeak), location: 0),
                            .init(color: Color.white.opacity(GlassToken.highlightPeak * 0.25), location: 0.12),
                            .init(color: Color.clear, location: 0.45),
                        ],
                        startPoint: .top,
                        endPoint: .bottom,
                    )
                )
                .blendMode(.screen)
            }
            if hasBorder {
                borderEdge
            }
        }
        .compositingGroup()
        // `glassEffect` is backed by a rectangular AppKit layer. Clip the composed result,
        // not only its SwiftUI fills, so that backing layer cannot show beyond a shaped edge.
        .clipShape(shape)
    }

    @ViewBuilder
    private var base: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular.interactive(false), in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
    }

    /// The outer edge. On macOS 26 it's a ring of real Liquid Glass masked to just the
    /// border band, so the edge refracts — light bends along the rounded corner like the
    /// native material — over a faint hairline that keeps the outline defined. Older systems
    /// get the plain hairline.
    @ViewBuilder
    private var borderEdge: some View {
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: shape)
                .mask(shape.stroke(lineWidth: GlassToken.refractiveBorderWidth))
                .overlay(shape.stroke(Color.white.opacity(GlassToken.borderOpacity), lineWidth: StrokeToken.hairline))
        } else {
            shape.stroke(Color.white.opacity(GlassToken.borderOpacity), lineWidth: StrokeToken.hairline)
        }
    }
}
