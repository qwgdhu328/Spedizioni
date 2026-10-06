import SwiftUI

/// Editor di codice per un file del sito: testo monospazio,
/// salvataggio automatico all'apertura/chiusura e con `Salva`.
struct EditorView: View {
    @EnvironmentObject private var store: SiteStore
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .padding(.horizontal, 4)
                .navigationTitle(fileName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .keyboard) {
                        Spacer()
                        Button("Fine") { focused = false }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            store.save(text)
                            focused = false
                        } label: {
                            Label("Salva", systemImage: "checkmark.circle.fill")
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(text == (store.openFile?.text ?? text))
                    }
                }
                .onAppear { text = store.openFile?.text ?? "" }
                .onDisappear { store.save(text) }
        }
    }

    private var fileName: String {
        ((store.openFile?.path ?? "file") as NSString).lastPathComponent
    }
}

#Preview {
    EditorView()
        .environmentObject(SiteStore())
}
