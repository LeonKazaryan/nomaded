import SwiftUI

/// The glass search field every search panel uses: an icon, the text, and a clear button
/// once there's something to clear.
struct SearchField: View {
    let placeholder: LocalizedStringKey
    var systemImage = "magnifyingglass"
    @Binding var text: String
    let isFocused: FocusState<Bool>.Binding
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .focused(isFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .submitLabel(.search)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button {
                    text = ""
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
        .padding(.trailing, text.isEmpty ? 16 : 0)
        .frame(minHeight: 48)
        .glass(Capsule())
        .animation(Motion.snappy, value: text.isEmpty)
    }
}

#Preview {
    @Previewable @State var text = "Ita"
    @Previewable @FocusState var isFocused: Bool
    SearchField(placeholder: "Search countries", text: $text, isFocused: $isFocused)
        .padding()
        .background(SpaceBackground())
}
