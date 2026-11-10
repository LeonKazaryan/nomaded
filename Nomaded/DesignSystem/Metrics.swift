import SwiftUI

/// Widths that keep the floating UI as wide as it reads best. On an iPhone they never bind;
/// on an iPad cards and lists stay that wide, centred over the globe, instead of stretching
/// across a 13-inch screen.
enum Metrics {
    /// The country card, the searches, the lists dropping over the globe, onboarding's column.
    static let panelWidth: CGFloat = 540
    /// A list to read down: a continent's countries.
    static let readableWidth: CGFloat = 720
    /// A screen of cards (the statistics): three continents side by side.
    static let pageWidth: CGFloat = 1040
}

extension View {
    /// No wider than `width`, centred in whatever room there is.
    func centered(maxWidth width: CGFloat) -> some View {
        frame(maxWidth: width)
            .frame(maxWidth: .infinity)
    }
}
