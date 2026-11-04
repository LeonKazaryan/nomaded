import SwiftUI

extension EnvironmentValues {
    /// The places on the globe in its worldview (see `CountryCatalog.limited(to:)`): screens
    /// list and count from it, so China's App Store never lists Taiwan on its own.
    @Entry var countryCatalog = CountryCatalog.bundled
}
