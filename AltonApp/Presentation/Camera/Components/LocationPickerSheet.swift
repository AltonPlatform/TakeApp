import CoreLocation
import SwiftUI

struct LocationSuggestion: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let detail: String?
    let lat: Double
    let lon: Double
}

@MainActor
final class LocationPickerModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var query = ""
    @Published var suggestions: [LocationSuggestion] = []
    @Published var nearby: [LocationSuggestion] = []
    @Published var isSearching = false
    @Published var errorMessage: String?

    private let manager = CLLocationManager()
    private var searchTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    func searchDebounced() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            suggestions = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await searchNominatim(query: q)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { await self.reverseGeocode(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.errorMessage = error.localizedDescription
        }
    }

    private func reverseGeocode(_ location: CLLocation) async {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let urlString =
            "https://nominatim.openstreetmap.org/reverse?format=json&lat=\(lat)&lon=\(lon)&zoom=16&addressdetails=1"
        guard let url = URL(string: urlString) else { return }
        do {
            var request = URLRequest(url: url)
            request.setValue("AltonApp/1.0 (location picker)", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let name = (json["display_name"] as? String) ?? "Поточне місце"
                nearby = [
                    LocationSuggestion(name: shortName(from: name), detail: name, lat: lat, lon: lon)
                ]
            }
        } catch {
            nearby = [
                LocationSuggestion(name: "Поточне місце", detail: nil, lat: lat, lon: lon)
            ]
        }
    }

    private func searchNominatim(query: String) async {
        isSearching = true
        defer { isSearching = false }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString =
            "https://nominatim.openstreetmap.org/search?q=\(encoded)&format=json&limit=8"
        guard let url = URL(string: urlString) else { return }
        do {
            var request = URLRequest(url: url)
            request.setValue("AltonApp/1.0 (location picker)", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                suggestions = []
                return
            }
            suggestions = array.compactMap { item in
                guard let display = item["display_name"] as? String,
                      let latStr = item["lat"] as? String,
                      let lonStr = item["lon"] as? String,
                      let lat = Double(latStr),
                      let lon = Double(lonStr) else { return nil }
                return LocationSuggestion(
                    name: shortName(from: display),
                    detail: display,
                    lat: lat,
                    lon: lon
                )
            }
        } catch {
            errorMessage = error.localizedDescription
            suggestions = []
        }
    }

    private func shortName(from display: String) -> String {
        display.split(separator: ",").first.map(String.init) ?? display
    }
}

struct LocationPickerSheet: View {
    @Binding var selected: CameraViewModel.SelectedLocation?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = LocationPickerModel()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Пошук місця…", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: model.query) { _, _ in model.searchDebounced() }

                if !model.nearby.isEmpty {
                    Text("Поруч")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(model.nearby) { item in
                                chip(item)
                            }
                        }
                    }
                }

                if model.isSearching {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }

                List {
                    ForEach(model.suggestions) { item in
                        Button {
                            select(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .foregroundStyle(.primary)
                                if let detail = item.detail {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .navigationTitle("Розташування")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрити") { dismiss() }
                }
                if selected != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Видалити") {
                            selected = nil
                            dismiss()
                        }
                    }
                }
            }
            .onAppear { model.start() }
        }
    }

    private func chip(_ item: LocationSuggestion) -> some View {
        Button {
            select(item)
        } label: {
            Text(item.name)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func select(_ item: LocationSuggestion) {
        selected = .init(name: item.name, lat: item.lat, lon: item.lon)
        dismiss()
    }
}
