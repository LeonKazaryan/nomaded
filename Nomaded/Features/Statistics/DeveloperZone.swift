#if DEBUG
import SwiftUI

/// What the developer zone can do, handed down from the globe screen.
///
/// Debug builds only, on purpose: App Review guideline 2.3.1 forbids hidden features in what
/// ships, and a switch that draws Crimea as Ukrainian in Russia's App Store (or the other way
/// round) must never reach a user. Its texts are verbatim: they're never translated.
struct DeveloperTools {
    /// The borders the globe draws now.
    let worldview: Worldview
    /// The storefront StoreKit last reported (ISO 3166-1 alpha-3), if any.
    let storefront: String?
    /// `nil`: follow the storefront again.
    let onWorldview: @MainActor (Worldview?) -> Void
    let onReset: @MainActor () -> Void
}

extension EnvironmentValues {
    @Entry var developerTools: DeveloperTools? = nil
}

extension View {
    /// Lets the statistics open the developer zone: pull past the bottom three times.
    func developerZone(
        worldview: Worldview,
        storefront: String?,
        onWorldview: @escaping @MainActor (Worldview?) -> Void,
        onReset: @escaping @MainActor () -> Void
    ) -> some View {
        environment(\.developerTools, DeveloperTools(worldview: worldview, storefront: storefront, onWorldview: onWorldview, onReset: onReset))
    }
}

/// How many pulls past the end open the zone, and how far each must stretch.
enum DeveloperUnlock {
    static let pulls = 3
    static let distance: CGFloat = 70
}

/// Under the last card: a hammer that jumps and fills a dot with every pull past the end,
/// then, on the third, the zone itself springs open.
struct DeveloperZone: View {
    let tools: DeveloperTools
    let pulls: Int
    let isOpen: Bool

    var body: some View {
        if isOpen {
            DeveloperPanel(tools: tools)
                .transition(.scale(scale: 0.8, anchor: .top).combined(with: .opacity))
        } else if pulls > 0 {
            hint
                .transition(.scale(scale: 0.5).combined(with: .opacity))
        }
    }

    private var hint: some View {
        HStack(spacing: 10) {
            Image(systemName: "hammer.fill")
                .font(Typography.label)
                .symbolEffect(.bounce, value: pulls)
            HStack(spacing: 5) {
                ForEach(0..<DeveloperUnlock.pulls, id: \.self) { index in
                    Circle()
                        .fill(index < pulls ? AnyShapeStyle(Palette.accentLight) : AnyShapeStyle(.white.opacity(0.2)))
                        .frame(width: 7, height: 7)
                        .scaleEffect(index == pulls - 1 ? 1.25 : 1)
                }
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(minHeight: 36)
        .glass(Capsule())
        .animation(Motion.bouncy, value: pulls)
        .accessibilityHidden(true)
    }
}

private struct DeveloperPanel: View {
    /// What the region picker offers: the storefront's own, or one forced.
    private enum Choice: Hashable {
        case automatic
        case forced(Worldview)

        var worldview: Worldview? {
            if case .forced(let worldview) = self { return worldview }
            return nil
        }
    }

    let tools: DeveloperTools

    @State private var choice: Choice
    @State private var confirmingReset = false
    @AppStorage("NomadedDebugShowsFrameRate") private var showsFrameRate = true

    init(tools: DeveloperTools) {
        self.tools = tools
        let forced = UserDefaults.standard.string(forKey: WorldviewSource.overrideKey).flatMap(Worldview.init(rawValue:))
        _choice = State(initialValue: forced.map(Choice.forced) ?? .automatic)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Palette.accentLight)
                    .frame(width: 44, height: 44)
                    .glass(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Разработчик")
                        .font(Typography.title)
                    Text(verbatim: "Только в Debug-сборке, в App Store этого нет")
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: "Границы по региону App Store")
                    .font(Typography.label)
                PillPicker(
                    options: [
                        .init(id: Choice.automatic, title: LocalizedStringKey(Self.title(nil))),
                        .init(id: Choice.forced(.standard), title: LocalizedStringKey(Self.title(.standard))),
                        .init(id: Choice.forced(.russia), title: LocalizedStringKey(Self.title(.russia))),
                        .init(id: Choice.forced(.china), title: LocalizedStringKey(Self.title(.china))),
                    ],
                    selection: $choice
                )
                Text(verbatim: storefrontLine)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            Toggle(isOn: $showsFrameRate) {
                Text(verbatim: "Счётчик кадров")
                    .font(Typography.label)
            }
            .tint(Palette.accent)

            Button {
                confirmingReset = true
            } label: {
                Label {
                    Text(verbatim: "Стереть весь прогресс")
                } icon: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .font(Typography.label)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.red.opacity(0.75), in: Capsule())
            }
            .buttonStyle(.pressable)
        }
        .padding(20)
        .glassCard()
        .onChange(of: choice) { _, choice in
            tools.onWorldview(choice.worldview)
        }
        .confirmationDialog(
            Text(verbatim: "Стереть отметки, города и медали?"),
            isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                tools.onReset()
            } label: {
                Text(verbatim: "Стереть и начать с онбординга")
            }
            Button(role: .cancel) {} label: { Text(verbatim: "Отмена") }
        }
    }

    private var storefrontLine: String {
        let store = tools.storefront.map { "App Store: \($0) → \(Self.title(Worldview(storefront: $0)))" } ?? "App Store: регион не определён"
        return store + " · на глобусе: " + Self.title(tools.worldview)
    }

    private static func title(_ worldview: Worldview?) -> String {
        switch worldview {
        case nil: "Авто"
        case .standard: "Мир"
        case .russia: "Россия"
        case .china: "Китай"
        }
    }
}
#endif
