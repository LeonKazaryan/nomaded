import SwiftUI

/// Compact card for the selected country with the main action and its cities.
///
/// Once the country is marked, the button splits: a small ✓ stays (tap to unmark) and
/// "Next destination" grows out of it and opens the search, so adding places one after
/// another is a single tap.
/// Below, the cities you've been to there, and "+ City", which lights up right after a mark
/// until the first city (`AddCityChip`). A visited country's passport stamp sits on the
/// card's top edge; marking the country slams it down.
struct CountryPeekCard: View {
    let code: String
    let isVisited: Bool
    let cities: [CityPin]
    let highlightedCity: UUID?
    /// When it was first marked; `nil` while not visited.
    let visitedSince: Date?
    let stampInk: Color
    let stampSlams: Bool
    /// Something covers the card, like a milestone: "+ City" waits for it to go.
    let isCovered: Bool
    /// Unmarking a country with cities asks first, in a dialog that comes out of the ✓ (a
    /// popover on an iPad, a sheet from the bottom on an iPhone).
    @Binding var isConfirmingUnmark: Bool
    let onConfirmUnmark: () -> Void
    let onToggleVisited: () -> Void
    let onFindNext: () -> Void
    let onAddCity: () -> Void
    let onSelectCity: (UUID) -> Void
    let onRemoveCity: (UUID) -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var buttonHeight = 54

    var body: some View {
        let name = RegionDisplay.name(for: code)
        let isLarge = dynamicTypeSize.isAccessibilitySize
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Text(verbatim: RegionDisplay.flag(for: code))
                    .font(.system(size: isLarge ? 36 : 48))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: name)
                        .font(Typography.title)
                        // A one-word name shrinks rather than breaking mid-word ("Фран-ция");
                        // a longer one wraps between its words.
                        .lineLimit(name.contains(" ") ? 2 : 1)
                        .minimumScaleFactor(isLarge ? 0.5 : 0.8)
                    Text(isVisited ? "Visited" : "Not visited yet")
                        .font(Typography.label)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }

                Spacer(minLength: 0)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.12), in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .contentShape(.hoverEffect, Circle().inset(by: 7))
                }
                .buttonStyle(.pressable)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
            }

            // With the largest text the two buttons can't share a row.
            (isLarge ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))) {
                Button(action: onToggleVisited) {
                    HStack(spacing: 8) {
                        Image(systemName: isVisited ? "checkmark.seal.fill" : "plus.circle.fill")
                            .contentTransition(.symbolEffect(.replace))
                        if !isVisited {
                            Text("Mark as visited")
                                .lineLimit(1)
                                .minimumScaleFactor(isLarge ? 0.6 : 0.8)
                                .transition(.opacity)
                        }
                    }
                }
                .buttonStyle(.capsule(isVisited ? .inverted : .accent))
                .frame(width: isVisited ? buttonHeight : nil)
                .accessibilityLabel(isVisited ? "Visited" : "Mark as visited")
                .accessibilityAddTraits(isVisited ? .isSelected : [])
                .accessibilityHint(isVisited ? "Removes the country from your visited list" : "")
                .confirmationDialog(
                    Text("Remove \(name) from visited?"),
                    isPresented: $isConfirmingUnmark,
                    titleVisibility: .visible
                ) {
                    Button("Remove", role: .destructive, action: onConfirmUnmark)
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("\(cities.count) cities will be removed with it.")
                }

                if isVisited {
                    Button(action: onFindNext) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                            Text("Next destination")
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    .buttonStyle(.capsule(.accent))
                    .transition(nextTransition)
                }
            }

            CityChips(
                cities: cities,
                highlighted: highlightedCity,
                justMarked: stampSlams,
                isCovered: isCovered,
                onSelect: onSelectCity,
                onRemove: onRemoveCity,
                onAdd: onAddCity
            )
        }
        .padding(20)
        .glassCard(cornerRadius: 30)
        .overlay(alignment: .topTrailing) {
            if isVisited, let visitedSince {
                PassportStamp(code: code, date: visitedSince, ink: stampInk, slamsIn: stampSlams)
                    // Pressed across the card's top edge, left of the close button.
                    .offset(x: -58, y: -26)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? Motion.snappy : Motion.bouncy, value: isVisited)
    }

    /// Grows out of the ✓ next to it; Reduce Motion just fades it in.
    private var nextTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .scale(scale: 0.4, anchor: .leading).combined(with: .opacity),
                removal: .opacity
            )
    }
}

/// The country's cities as chips. Tap one to fly to it, hold it to remove it; the last
/// chip adds a city. A new chip springs in, and the row scrolls to the highlighted one.
private struct CityChips: View {
    let cities: [CityPin]
    let highlighted: UUID?
    let justMarked: Bool
    let isCovered: Bool
    let onSelect: (UUID) -> Void
    let onRemove: (UUID) -> Void
    let onAdd: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(cities) { city in
                        chip(city)
                            .id(city.id)
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
                    }
                    AddCityChip(justMarked: justMarked, isCovered: isCovered, action: onAdd)
                }
            }
            .scrollIndicators(.hidden)
            // With no chips to scroll, "+ City" alone: its hint's glow and rings spill past the row.
            .scrollClipDisabled(cities.isEmpty)
            // Runs to the card's edges, so chips scroll out under its rim instead of being
            // cut off inside the padding.
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .padding(.horizontal, -20)
            .animation(reduceMotion ? Motion.snappy : Motion.bouncy, value: cities.map(\.id))
            // Also when the card opens on a highlighted city, or its chip has only just been added.
            .onChange(of: [highlighted] + cities.map(\.id), initial: true) {
                guard let highlighted else { return }
                withAnimation(Motion.smooth) { proxy.scrollTo(highlighted, anchor: .center) }
            }
        }
    }

    private func chip(_ city: CityPin) -> some View {
        let isHighlighted = city.id == highlighted
        return Button {
            onSelect(city.id)
        } label: {
            Label {
                Text(verbatim: city.name)
            } icon: {
                Image(systemName: "mappin")
            }
            .font(Typography.label)
            .foregroundStyle(isHighlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background(isHighlighted ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(.white.opacity(0.12)), in: Capsule())
            .padding(.vertical, 2)
            .contentShape(Capsule())
            .contentShape(.hoverEffect, Capsule())
        }
        .buttonStyle(.pressable)
        .contextMenu {
            Button(role: .destructive) {
                onRemove(city.id)
            } label: {
                Label("Remove city", systemImage: "trash")
            }
        }
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
        .accessibilityHint("Shows the city on the globe")
        .animation(Motion.snappy, value: isHighlighted)
    }
}

#if DEBUG
// The scratch store exists in Debug only; Release builds (and archives) skip the preview.
#Preview {
    let rome = CityPin(id: UUID(), name: "Rome", region: "Lazio", countryCode: "IT", latitude: 41.9, longitude: 12.5, createdAt: .now)
    let florence = CityPin(id: UUID(), name: "Florence", region: "Tuscany", countryCode: "IT", latitude: 43.77, longitude: 11.25, createdAt: .now)
    ZStack {
        SpaceBackground()
        VStack(spacing: 16) {
            CountryPeekCard(
                code: "IT", isVisited: true, cities: [rome, florence], highlightedCity: rome.id,
                visitedSince: .now, stampInk: Palette.candy[0], stampSlams: false, isCovered: false,
                isConfirmingUnmark: .constant(false), onConfirmUnmark: {},
                onToggleVisited: {}, onFindNext: {}, onAddCity: {}, onSelectCity: { _ in }, onRemoveCity: { _ in }, onClose: {}
            )
            CountryPeekCard(
                code: "KZ", isVisited: false, cities: [], highlightedCity: nil,
                visitedSince: nil, stampInk: Palette.candy[3], stampSlams: false, isCovered: false,
                isConfirmingUnmark: .constant(false), onConfirmUnmark: {},
                onToggleVisited: {}, onFindNext: {}, onAddCity: {}, onSelectCity: { _ in }, onRemoveCity: { _ in }, onClose: {}
            )
        }
        .padding(16)
    }
    .environment(WorldStore.scratch())
    .preferredColorScheme(.dark)
}
#endif
