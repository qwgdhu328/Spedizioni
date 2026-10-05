import SwiftUI

/// Selettore di rete con ricerca: tutte le reti del catalogo
/// raggruppate per paese (Italia prima).
struct CarrierPickerView: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var groups: [(country: String, carriers: [Carrier])] {
        CarrierCatalog.groupedByCountry(CarrierCatalog.search(searchText))
    }

    var body: some View {
        List {
            ForEach(groups, id: \.country) { group in
                Section(group.country) {
                    ForEach(group.carriers) { carrier in
                        Button {
                            selection = carrier.id
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Text(carrier.flag)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(carrier.name)
                                        .foregroundStyle(.primary)
                                    Text(carrier.category.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selection == carrier.id {
                                    Image(systemName: "checkmark")
                                        .font(.headline)
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Rete di spedizione")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Cerca una rete (es. Poste, DHL…)")
    }
}

#Preview {
    NavigationStack {
        CarrierPickerView(selection: .constant("poste-italiane"))
    }
}
