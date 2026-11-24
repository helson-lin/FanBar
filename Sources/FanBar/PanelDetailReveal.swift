import SwiftUI

/// Presentation values for the resource detail entrance: height stays instant,
/// while drawing eases in unless motion is disabled.
struct PanelDetailRevealStyle: Equatable {
    static let duration: Double = 0.15
    static let hiddenScale: CGFloat = 0.98

    let opacity: Double
    let scale: CGFloat

    static func initialRevealed(animates: Bool) -> Bool {
        !animates
    }

    static func values(revealed: Bool, animates: Bool) -> Self {
        let isVisible = revealed || !animates
        return Self(
            opacity: isVisible ? 1 : 0,
            scale: isVisible ? 1 : hiddenScale
        )
    }
}

/// Fades and scales a resource detail view in without animating layout height.
/// Each detail branch owns its own modifier instance, so switching between disk
/// and CPU details always mounts fresh reveal state that only moves to visible.
struct PanelDetailRevealModifier: ViewModifier {
    let animates: Bool
    @State private var isRevealed: Bool

    init(animates: Bool) {
        self.animates = animates
        _isRevealed = State(initialValue: PanelDetailRevealStyle.initialRevealed(animates: animates))
    }

    func body(content: Content) -> some View {
        let style = PanelDetailRevealStyle.values(revealed: isRevealed, animates: animates)
        content
            .opacity(style.opacity)
            .scaleEffect(style.scale, anchor: .top)
            .onAppear {
                guard !isRevealed else { return }
                withAnimation(.easeOut(duration: PanelDetailRevealStyle.duration)) {
                    isRevealed = true
                }
            }
    }
}

extension View {
    func panelDetailReveal(animates: Bool) -> some View {
        modifier(PanelDetailRevealModifier(animates: animates))
    }
}
