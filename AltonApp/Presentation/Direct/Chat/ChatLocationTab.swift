import CoreLocation
import MapKit
import SwiftUI

@Observable
final class ChatLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var authorization: CLAuthorizationStatus
    private(set) var location: CLLocation?

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func request() {
        authorization = manager.authorizationStatus
        switch authorization {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if authorization == .authorizedAlways || authorization == .authorizedWhenInUse {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

struct ChatLocationPlace: Identifiable, Equatable {
    let id: String
    let name: String
    let address: String?
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: ChatLocationPlace, rhs: ChatLocationPlace) -> Bool {
        lhs.id == rhs.id
    }
}

struct ChatLocationTab: View {
    var onSend: (DMLocation) -> Void

    @State private var provider = ChatLocationProvider()
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var center = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    @State private var hasCenter = false
    @State private var query = ""
    @State private var nearby: [ChatLocationPlace] = []
    @State private var results: [ChatLocationPlace] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var nearbyTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            map
                .frame(height: 220)
            List {
                if let location = provider.location {
                    Button {
                        send(coordinate: location.coordinate, name: "My Location", address: nil)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Send My Location")
                                Text(accuracyText(location))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "location.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                } else if provider.authorization == .denied || provider.authorization == .restricted {
                    Text("Location access is off. You can still drop a pin on the map.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if hasCenter {
                    Button {
                        send(coordinate: center, name: nil, address: nil)
                    } label: {
                        Label("Send This Point", systemImage: "mappin.and.ellipse")
                    }
                }
                Section(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Nearby" : "Results") {
                    ForEach(visiblePlaces) { place in
                        Button {
                            send(coordinate: place.coordinate, name: place.name, address: place.address)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name)
                                if let address = place.address, !address.isEmpty {
                                    Text(address)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "Search places")
        }
        .onAppear { provider.request() }
        .onChange(of: query) { _, newValue in
            scheduleSearch(newValue)
        }
    }

    private var visiblePlaces: [ChatLocationPlace] {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nearby : results
    }

    private var map: some View {
        Map(position: $position) {
            UserAnnotation()
        }
        .mapControls {
            MapUserLocationButton()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            center = context.camera.centerCoordinate
            hasCenter = true
            scheduleNearby()
        }
        .overlay {
            Image(systemName: "mappin.circle.fill")
                .font(.title)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.accentColor)
                .offset(y: -14)
                .allowsHitTesting(false)
        }
    }

    private func accuracyText(_ location: CLLocation) -> String {
        let meters = max(1, Int(location.horizontalAccuracy.rounded()))
        return "Accurate to \(meters) m"
    }

    private func scheduleNearby() {
        nearbyTask?.cancel()
        let coordinate = center
        nearbyTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let places = await Self.nearbyPlaces(around: coordinate)
            guard !Task.isCancelled else { return }
            nearby = places
        }
    }

    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        let regionCenter = hasCenter ? center : provider.location?.coordinate
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            results = await Self.search(query: trimmed, near: regionCenter)
        }
    }

    private func send(coordinate: CLLocationCoordinate2D, name: String?, address: String?) {
        let location = DMLocation(
            lat: coordinate.latitude,
            lng: coordinate.longitude,
            name: name,
            address: address
        )
        if name == nil {
            Task {
                let resolved = await Self.reverse(coordinate)
                onSend(DMLocation(
                    lat: coordinate.latitude,
                    lng: coordinate.longitude,
                    name: resolved?.name,
                    address: resolved?.address
                ))
            }
        } else {
            onSend(location)
        }
    }

    private static func nearbyPlaces(around coordinate: CLLocationCoordinate2D) async -> [ChatLocationPlace] {
        let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: 800)
        let search = MKLocalSearch(request: request)
        guard let response = try? await search.start() else { return [] }
        return response.mapItems.prefix(12).map(place(from:))
    }

    private static func search(query: String, near coordinate: CLLocationCoordinate2D?) async -> [ChatLocationPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let coordinate {
            request.region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 8_000,
                longitudinalMeters: 8_000
            )
        }
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems.prefix(12).map(place(from:))
    }

    private static func reverse(_ coordinate: CLLocationCoordinate2D) async -> (name: String?, address: String?)? {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else { return nil }
        let name = placemark.name
        let address = [placemark.thoroughfare, placemark.locality]
            .compactMap { $0 }
            .joined(separator: ", ")
        return (name, address.isEmpty ? nil : address)
    }

    private static func place(from item: MKMapItem) -> ChatLocationPlace {
        let coordinate = item.placemark.coordinate
        let name = item.name ?? "Place"
        let address = item.placemark.title
        return ChatLocationPlace(
            id: "\(coordinate.latitude),\(coordinate.longitude),\(name)",
            name: name,
            address: address,
            coordinate: coordinate
        )
    }
}

enum ChatMapSnapshot {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(
        for location: DMLocation,
        size: CGSize,
        scale: CGFloat,
        colorScheme: ColorScheme
    ) async -> UIImage? {
        let style = colorScheme == .dark ? "d" : "l"
        let key = String(
            format: "%.5f,%.5f,%.0fx%.0f,%.0f,%@",
            location.lat,
            location.lng,
            size.width,
            size.height,
            scale,
            style
        ) as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: location.lat, longitude: location.lng),
            latitudinalMeters: 450,
            longitudinalMeters: 450
        )
        options.size = size
        options.scale = max(scale, 1)
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        let snapshotter = MKMapSnapshotter(options: options)
        guard let snapshot = try? await snapshotter.start() else { return nil }
        cache.setObject(snapshot.image, forKey: key)
        return snapshot.image
    }
}
