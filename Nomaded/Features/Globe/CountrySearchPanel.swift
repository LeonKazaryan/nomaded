import SwiftUI

/// Floating search over the globe: a field on top and the matches in a glass card below.
/// Picking a country hands it back; the globe flies there.
struct CountrySearchPanel: View {
    let index: CountrySearchIndex
    let visited: Set<String>
    let onPick: (String) -> Void
    let onCancel: () -> Void

    @State private var query: String
    @FocusState private var isFieldFocused: Bool
    @ScaledMetric(relativeTo: .body) private var rowHeight = 56

    init(
        index: CountrySearchIndex,
        visited: Set<String>,
        initialQuery: String = "",
        onPick: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.index = index
        self.visited = visited
        self.onPick = onPick
        self.onCancel = onCancel
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        let results = index.results(for: query)

        VStack(spacing: 12) {
            HStack(spacing: 12) {
                field(firstResult: results.first)
                Button("Cancel", action: onCancel)
                    .font(Typography.label)
                    .foregroundStyle(.primary)
                    .frame(minHeight: 44)
                    .buttonStyle(.pressable)
            }

            if results.isEmpty {
                Text("No countries found")
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: rowHeight)
                    .glassCard(cornerRadius: 24)
                    .transition(.opacity)
            } else {
                resultList(results)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(Motion.snappy, value: results.isEmpty)
        .onAppear { isFieldFocused = true }
    }

    private func field(firstResult: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search countries", text: $query)
                .focused($isFieldFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .submitLabel(.search)
                .onSubmit {
                    if let firstResult { onPick(firstResult) }
                }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Clear")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .font(Typography.body)
        .padding(.leading, 16)
        .padding(.trailing, query.isEmpty ? 16 : 0)
        .frame(minHeight: 48)
        .glass(Capsule())
        .animation(Motion.snappy, value: query.isEmpty)
    }

    private func resultList(_ results: [String]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(results, id: \.self) { code in
                    Button {
                        onPick(code)
                    } label: {
                        CountrySearchRow(code: code, isVisited: visited.contains(code))
                            .frame(minHeight: rowHeight)
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.vertical, 6)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        // Hug short result lists; long ones scroll inside the space above the keyboard.
        .frame(maxHeight: CGFloat(results.count) * rowHeight + 12)
        .glassCard(cornerRadius: 24)
    }
}

private struct CountrySearchRow: View {
    let code: String
    let isVisited: Bool

    var body: some View {
        HStack(spacing: 14) {
            Text(verbatim: RegionDisplay.flag(for: code))
                .font(.system(size: 28))
                .accessibilityHidden(true)
            Text(verbatim: RegionDisplay.name(for: code))
                .font(Typography.body)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if isVisited {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Palette.accentLight)
                    .accessibilityLabel("Visited")
            }
        }
        .padding(.horizontal, 18)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ZStack {
        SpaceBackground()
        CountrySearchPanel(
            index: CountrySearchIndex(codes: ["IT", "IS", "IN", "ID", "IE", "IL", "KZ"]),
            visited: ["IT"],
            initialQuery: "I",
            onPick: { _ in },
            onCancel: {}
        )
        .padding(16)
    }
    .preferredColorScheme(.dark)
}
