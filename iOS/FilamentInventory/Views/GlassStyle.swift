import SwiftUI

// MARK: - iOS 26 Liquid Glass card style helpers
//
// glassEffect() is an iOS 26 SDK API (Xcode 26 / Swift 6.2+).
// #available(iOS 26, *) is a runtime guard — the compiler still needs the
// symbol in the SDK. We add a compile-time #if swift(>=6.2) so older Xcode
// versions (CI on Xcode 16.x) silently fall through to the legacy style.

extension View {

    /// Primary card surface.
    /// Replaces `.background(Color(.secondarySystemBackground)).cornerRadius(r)`.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
#if swift(>=6.2)
        if #available(iOS 26, *) {
            self.glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self
                .background(Color(.secondarySystemBackground))
                .cornerRadius(cornerRadius)
        }
#else
        self
            .background(Color(.secondarySystemBackground))
            .cornerRadius(cornerRadius)
#endif
    }

    /// Inner / nested card surface (slightly more recessed).
    /// Replaces `.background(Color(.tertiarySystemBackground)).cornerRadius(r)`.
    @ViewBuilder
    func glassInnerCard(cornerRadius: CGFloat = 12) -> some View {
#if swift(>=6.2)
        if #available(iOS 26, *) {
            self.glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(cornerRadius)
        }
#else
        self
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(cornerRadius)
#endif
    }

    /// Tinted card — keeps a colour wash on older iOS, uses plain glass on iOS 26.
    @ViewBuilder
    func glassTintCard(cornerRadius: CGFloat = 16, fallback: Color) -> some View {
#if swift(>=6.2)
        if #available(iOS 26, *) {
            self.glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self
                .background(fallback)
                .cornerRadius(cornerRadius)
        }
#else
        self
            .background(fallback)
            .cornerRadius(cornerRadius)
#endif
    }
}
