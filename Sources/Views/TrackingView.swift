import SwiftUI
import MapKit

/// Tracciamento IN-APP: interroga l'API pubblica Cainiao e mostra
/// ogni movimento in dettaglio (timeline completa), avanzamento,
/// e la mappa GPS del corriere quando disponibile — tutto dentro
/// l'app, senza uscire in Safari.
struct TrackingView: View {
    let number: String
    let carrier: Carrier?

    @State private var result: TrackingResult?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var showLiveMap = false
    @State private var showBrowserFallback = false

    private var liveMapURL: URL? {
        carrier?.trackingURL(for: number) ?? Carrier.universalTrackingURL(for: number)
    }

    private var coordinateEvents: [TrackingEvent] {
        (result?.events ?? []).filter(\.hasCoordinates)
    }

    var body: some View {
        List {
            if let result {
                summarySection(result)
                movementsSection(result)
                gpsSection
            } else if let errorMessage {
                errorSection
            } else {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    Text("Interrogazione API in corso…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Tracciamento")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load() }
                } label: {
                    if loading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(loading)
                .accessibilityLabel("Aggiorna tracciamento")
            }
        }
        .refreshable { await load() }
        .task {
            // Caricamento iniziale + polling ogni 60s finché la
            // vista è visibile (aggiornamenti continuativi).
            await load()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if Task.isCancelled { break }
                await load()
            }
        }
        .sheet(isPresented: $showLiveMap) {
            NavigationStack {
                VStack(spacing: 0) {
                    if let url = liveMapURL {
                        WebView(url: url)
                    }
                }
                .navigationTitle("Mappa live del corriere")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Chiudi") { showLiveMap = false }
                            .buttonStyle(.glass)
                    }
                }
            }
        }
        .sheet(isPresented: $showBrowserFallback) {
            if let url = liveMapURL {
                SafariView(url: url)
            }
        }
    }

    // MARK: - Riepilogo

    private func summarySection(_ result: TrackingResult) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: result.statusIcon)
                        .foregroundStyle(result.statusColor)
                    Text(result.statusDesc)
                        .font(.headline)
                    Spacer()
                }

                if let rate = result.progressRate {
                    let normalized = rate > 1.001 ? rate / 100 : rate
                    ProgressView(value: min(max(normalized, 0), 1))
                        .tint(result.statusColor)
                    Text("Avanzamento: \(Int((normalized * 100).rounded()))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let origin = result.originCountry, let dest = result.destCountry {
                    Label("\(origin) → \(dest)", systemImage: "airplane.departure")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !result.progressPoints.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(result.progressPoints, id: \.self) { point in
                                Text(point)
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.tint.opacity(0.15), in: Capsule())
                            }
                        }
                    }
                }

                Text("Fonte: \(result.source) · numero \(result.number)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Movimenti (ogni checkpoint)

    private func movementsSection(_ result: TrackingResult) -> some View {
        Section("Movimenti (\(result.events.count))") {
            if result.events.isEmpty {
                Text(result.emptyDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(result.events.enumerated()), id: \.element.id) { index, event in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 4) {
                        Image(systemName: index == 0 ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(index == 0 ? Color.accentColor : Color.secondary)
                            .font(.footnote)
                        if index < result.events.count - 1 {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.35))
                                .frame(width: 2)
                                .frame(minHeight: 8)
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(timeLabel(for: event))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(event.title)
                            .font(.subheadline.weight(.semibold))
                        if !event.detail.isEmpty && event.detail != event.title {
                            Text(event.detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if !event.actionCode.isEmpty {
                            Text(event.actionCode)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.bottom, 6)
                }
            }
        }
    }

    // MARK: - GPS / mappe

    private var gpsSection: some View {
        Section("GPS e mappe") {
            if !coordinateEvents.isEmpty {
                CoordinatesMapView(events: coordinateEvents)
                    .frame(height: 200)
                    .listRowInsets(EdgeInsets())
                ForEach(coordinateEvents) { event in
                    Label(
                        "\(event.title) — coordinate disponibili",
                        systemImage: "mappin.circle.fill"
                    )
                    .font(.caption)
                }
            }

            Button {
                showLiveMap = true
            } label: {
                Label("Mappa live del corriere (GPS veicolo)", systemImage: "location.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(liveMapURL == nil)

            Text("""
            Apre la pagina ufficiale del corriere DENTRO l'app: \
            quando il corriere espone la posizione GPS del veicolo \
            (consegna in corso), la mappa live appare qui senza \
            uscire dall'app.
            """)
            .font(.caption2)
            .foregroundStyle(.secondary)

            Button {
                showBrowserFallback = true
            } label: {
                Label("Apri nel browser (fallback)", systemImage: "safari")
            }
            .buttonStyle(.glass)
            .disabled(liveMapURL == nil)
        }
    }

    // MARK: - Errori

    private var errorSection: some View {
        Section {
            VStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text(errorMessage ?? "Errore sconosciuto")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                Button("Riprova") {
                    Task { await load() }
                }
                .buttonStyle(.glassProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Logica

    private func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            result = try await TrackingService.track(
                number: number,
                source: carrier?.name
            )
            errorMessage = nil
        } catch {
            // Mantiene il vecchio risultato se presente; altrimenti
            // mostra l'errore con la possibilità di riprovare.
            errorMessage = error.localizedDescription
        }
    }

    private func timeLabel(for event: TrackingEvent) -> String {
        if let time = event.time {
            return time.formatted(date: .abbreviated, time: .shortened)
        }
        return event.timeString.isEmpty ? "Data non disponibile" : event.timeString
    }
}

/// Mappa con i marker delle coordinate degli eventi (quando
/// l'API le fornisce). MKMapView nativa.
private struct CoordinatesMapView: UIViewRepresentable {
    let events: [TrackingEvent]

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.isUserInteractionEnabled = false
        var annotations: [MKPointAnnotation] = []
        for event in events {
            guard let lat = event.latitude, let lon = event.longitude else { continue }
            let annotation = MKPointAnnotation()
            annotation.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            annotation.title = event.title
            annotations.append(annotation)
        }
        map.addAnnotations(annotations)
        if let first = annotations.first {
            let region = MKCoordinateRegion(
                center: first.coordinate,
                latitudinalMeters: 200_000,
                longitudinalMeters: 200_000
            )
            map.setRegion(region, animated: false)
        }
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {}
}

#Preview {
    NavigationStack {
        TrackingView(number: "RR123456789CN", carrier: nil)
    }
}
