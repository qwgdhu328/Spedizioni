import SwiftUI

/// Tab "Reti": catalogo completo di tutte le reti di spedizione
/// con ricerca e tracciamento rapido di un numero.
struct CarriersView: View {
    @State private var searchText = ""
    @State private var safariURL: URL?
    @State private var trackedNumber: [String: String] = [:]

    private var groups: [(country: String, carriers: [Carrier])] {
        CarrierCatalog.groupedByCountry(CarrierCatalog.search(searchText))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(groups, id: \.country) { group in
                        Section(group.country) {
                            ForEach(group.carriers) { carrier in
                                carrierRow(carrier)
                            }
                        }
                    }
                } header: {
                    Text("\(CarrierCatalog.all.count) reti disponibili")
                }
            }
            .navigationTitle("Reti")
            .searchable(text: $searchText, prompt: "Cerca rete o paese…")
            .sheet(item: Binding(
                get: { safariURL.map { IdentifiedURL(url: $0) } },
                set: { safariURL = $0?.url }
            )) { item in
                SafariView(url: item.url)
            }
        }
    }

    private func carrierRow(_ carrier: Carrier) -> some View {
        HStack(spacing: 12) {
            Text(carrier.flag)
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text(carrier.name)
                    .font(.body.weight(.medium))
                Text(carrier.category.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                TextField("N°", text: binding(for: carrier))
                    .keyboardType(.asciiCapable)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 96)
                    .font(.caption.monospaced())
                    .textFieldStyle(.roundedBorder)

                Button {
                    track(carrier)
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.glass)
                .disabled((trackedNumber[carrier.id] ?? "").isEmpty)
                .accessibilityLabel("Traccia con \(carrier.name)")
            }
        }
        .padding(.vertical, 2)
    }

    private func binding(for carrier: Carrier) -> Binding<String> {
        Binding(
            get: { trackedNumber[carrier.id, default: ""] },
            set: { trackedNumber[carrier.id] = $0 }
        )
    }

    private func track(_ carrier: Carrier) {
        let number = (trackedNumber[carrier.id] ?? "")
            .trimmingCharacters(in: .whitespaces)
        guard !number.isEmpty else { return }
        safariURL = carrier.trackingURL(for: number)
    }
}

/// Wrapper per usare URL in `.sheet(item:)`.
private struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

#Preview {
    CarriersView()
}
