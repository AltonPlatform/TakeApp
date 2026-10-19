import CoreLocation
import MapKit
import SwiftUI
import UIKit

extension DMLocation: Identifiable {
    var id: String {
        String(format: "%.6f,%.6f,%@", lat, lng, name ?? "")
    }
}

struct ChatLocationMapScreen: View {
    let location: DMLocation

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var provider = ChatLocationProvider()
    @State private var position: MapCameraPosition
    @State private var hybrid = false
    @State private var copied = false

    init(location: DMLocation) {
        self.location = location
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: location.lat, longitude: location.lng),
            latitudinalMeters: 800,
            longitudinalMeters: 800
        )
        _position = State(initialValue: .region(region))
    }

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: location.lat, longitude: location.lng)
    }

    var body: some View {
        Map(position: $position) {
            Marker(location.name ?? "Location", coordinate: coordinate)
                .tint(Color.accentColor)
            UserAnnotation()
        }
        .mapStyle(hybrid
            ? .hybrid(pointsOfInterest: .excludingAll)
            : .standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapPitchToggle()
        }
        .safeAreaInset(edge: .top, spacing: 8) {
            topBar
        }
        .safeAreaInset(edge: .bottom, spacing: 8) {
            infoCard
        }
        .onAppear { provider.request() }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .directGlass(Circle(), interactive: true)
            Spacer()
            Button {
                hybrid.toggle()
            } label: {
                Image(systemName: hybrid ? "map" : "globe.americas.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .directGlass(Circle(), interactive: true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(location.name ?? "Location")
                    .font(.title3.weight(.semibold))
                if let address = location.address, !address.isEmpty {
                    Text(address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let distance {
                    Text(distance)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if copied {
                    Text("Copied")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                mapActionButton(
                    title: "Directions",
                    systemImage: "arrow.triangle.turn.up.right.diamond",
                    prominent: true,
                    action: openDirections
                )
                Menu {
                    Button("Apple Maps", systemImage: "map", action: openAppleMaps)
                    Button("Google Maps", systemImage: "globe", action: openGoogleMaps)
                    Button("Copy Address", systemImage: "doc.on.doc", action: copyAddress)
                    Button("Copy Coordinates", systemImage: "number", action: copyCoordinates)
                } label: {
                    mapActionLabel("Open in", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.plain)
                .directGlass(RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
            }

            if provider.location != nil {
                mapActionButton(
                    title: "Show both",
                    systemImage: "arrow.left.and.right",
                    prominent: false,
                    action: showBoth
                )
            }
        }
        .padding(16)
        .directGlass(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func mapActionButton(
        title: String,
        systemImage: String,
        prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: action) {
            mapActionLabel(title, systemImage: systemImage)
                .foregroundStyle(prominent ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        if prominent {
            button.background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black)
                    .overlay {
                        if colorScheme == .dark {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                        }
                    }
            }
        } else {
            button.directGlass(
                RoundedRectangle(cornerRadius: 14, style: .continuous),
                interactive: true
            )
        }
    }

    private func mapActionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
    }

    private var distance: String? {
        guard let user = provider.location else { return nil }
        let meters = user.distance(from: CLLocation(latitude: location.lat, longitude: location.lng))
        if meters < 1000 {
            return "\(max(1, Int(meters.rounded()))) m away"
        }
        return String(format: "%.1f km away", meters / 1000)
    }

    private var mapItem: MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = location.name ?? "Location"
        return item
    }

    private func openDirections() {
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    private func openAppleMaps() {
        mapItem.openInMaps()
    }

    private func openGoogleMaps() {
        let lat = location.lat
        let lng = location.lng
        let app = URL(string: "comgooglemaps://?q=\(lat),\(lng)&center=\(lat),\(lng)")
        let web = URL(string: "https://maps.google.com/?q=\(lat),\(lng)")
        if let app, UIApplication.shared.canOpenURL(app) {
            UIApplication.shared.open(app)
        } else if let web {
            UIApplication.shared.open(web)
        }
    }

    private func copyAddress() {
        let text = [location.name, location.address]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        UIPasteboard.general.string = text.isEmpty ? coordinateText : text
        showCopied()
    }

    private func copyCoordinates() {
        UIPasteboard.general.string = coordinateText
        showCopied()
    }

    private var coordinateText: String {
        String(format: "%.6f, %.6f", location.lat, location.lng)
    }

    private func showCopied() {
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            copied = false
        }
    }

    private func showBoth() {
        guard let user = provider.location else { return }
        let pin = MKMapPoint(coordinate)
        let me = MKMapPoint(user.coordinate)
        var rect = MKMapRect(
            x: min(pin.x, me.x),
            y: min(pin.y, me.y),
            width: abs(pin.x - me.x),
            height: abs(pin.y - me.y)
        )
        let padX = max(rect.size.width * 0.45, 200)
        let padY = max(rect.size.height * 0.45, 200)
        rect = rect.insetBy(dx: -padX, dy: -padY)
        withAnimation(.easeInOut(duration: 0.35)) {
            position = .rect(rect)
        }
    }
}
