import SwiftUI

/// Floating search over the globe: a field on top and the matches in a glass card below.
/// Picking a country hands it back; the globe flies there.
struct CountrySearchPanel: View {
    let index: CountrySearchIndex
    let visited: Set<String>
    /// Owned by the screen, so every way of closing the search drops the keyboard at once.
    let isFieldFocused: FocusState<Bool>.Binding
    let onPick: (String) -> Void
    let onCancel: () -> Void

    @State private var query: String
    @ScaledMetric(relativeTo: .body) private var rowHeight = 56

    init(
        index: CountrySearchIndex,
        visited: Set<String>,
        initialQuery: String = "",
        isFieldFocused: FocusState<Bool>.Binding,
        onPick: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.index = index
        self.visited = visited
        self.isFieldFocused = isFieldFocused
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
                CountryList(codes: results, marked: visited, onPick: onPick)
                    .scrollDismissesKeyboard(.interactively)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(Motion.snappy, value: results.isEmpty)
        .onAppear { isFieldFocused.wrappedValue = true }
    }

    private func field(firstResult: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search countries", text: $query)
                .focused(isFieldFocused)
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
}

#Preview {
    @Previewable @FocusState var isFocused: Bool
    ZStack {
        SpaceBackground()
        CountrySearchPanel(
            index: CountrySearchIndex(codes: ["IT", "IS", "IN", "ID", "IE", "IL", "KZ"]),
            visited: ["IT"],
            initialQuery: "I",
            isFieldFocused: $isFocused,
            onPick: { _ in },
            onCancel: {}
        )
        .padding(16)
    }
    .preferredColorScheme(.dark)
}
