import SwiftUI

// MARK: - iOS 26 Liquid Glass card style helpers
//
// On iOS 26+ the system renders a translucent Liquid Glass material.
// On older iOS the views fall back to the standard system fills, so the
// app looks correct on every supported OS version without any extra work.

extension View {

    /// Primary card surface.
    /// Replaces `.background(Color(.secondarySystemBackground)).cornerRadius(r)`.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self
                .background(Color(.secondarySystemBackground))
                .cornerRadius(cornerRadius)
        }
    }

    /// Inner / nested card surface (slightly more recessed).
    /// Replaces `.background(Color(.tertiarySystemBackground)).cornerRadius(r)`.
    @ViewBuilder
    func glassInnerCard(cornerRadius: CGFloat = 12) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(cornerRadius)
        }
    }

    /// Tinted card — keeps a colour wash on older iOS, uses plain glass on iOS 26
    /// (the glass already picks up ambient colour from the background).
    @ViewBuilder
    func glassTintCard(cornerRadius: CGFloat = 16, fallback: Color) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self
                .background(fallback)
                .cornerRadius(cornerRadius)
        }
    }
}
