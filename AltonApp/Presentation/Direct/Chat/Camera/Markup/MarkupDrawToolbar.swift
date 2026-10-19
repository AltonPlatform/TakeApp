import SwiftUI

struct MarkupDrawToolbar: View {
    @Binding var brush: MarkupBrush
    @Binding var colorHex: String
    @Binding var widthSlider: CGFloat

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(MarkupBrush.allCases) { item in
                    Button {
                        brush = item
                    } label: {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(brush == item ? Color.black : Color.white)
                            .frame(width: 40, height: 40)
                            .background(
                                brush == item ? Color.white : Color.white.opacity(0.18),
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.rawValue)
                }
                Spacer(minLength: 0)
            }

            if brush != .eraser {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(MarkupPalette.swatches, id: \.self) { hex in
                            Button {
                                colorHex = hex
                            } label: {
                                Circle()
                                    .fill(Color(markupHex: hex) ?? .white)
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        Circle()
                                            .strokeBorder(
                                                colorHex.caseInsensitiveCompare(hex) == .orderedSame
                                                    ? Color.white
                                                    : Color.white.opacity(0.25),
                                                lineWidth: colorHex.caseInsensitiveCompare(hex) == .orderedSame
                                                    ? 2.5
                                                    : 1
                                            )
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                        ColorPicker("", selection: colorBinding, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(markupHex: colorHex) ?? .white },
            set: { newValue in
                colorHex = UIColor(newValue).markupHexString()
            }
        )
    }
}

/// Vertical slider along the left edge (stroke width or font size).
struct MarkupVerticalSlider: View {
    @Binding var value: CGFloat
    var showsStrokePreview: Bool = true
    var trackHeight: CGFloat = 140

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let thumbRadius: CGFloat = showsStrokePreview ? 11 : 8
            let travel = max(1, height - thumbRadius * 2)
            let thumbY = thumbRadius + (1 - value) * travel
            ZStack(alignment: .top) {
                Capsule()
                    .fill(Color.white.opacity(showsStrokePreview ? 0.25 : 0.38))
                    .frame(width: showsStrokePreview ? 4 : 2)
                    .padding(.vertical, thumbRadius)
                    .frame(maxHeight: .infinity)
                Circle()
                    .fill(Color.white)
                    .frame(width: thumbRadius * 2, height: thumbRadius * 2)
                    .shadow(color: .black.opacity(showsStrokePreview ? 0 : 0.35), radius: 3, y: 1)
                    .offset(y: thumbY - thumbRadius)
                if showsStrokePreview {
                    Circle()
                        .fill(Color.white.opacity(0.9))
                        .frame(
                            width: 4 + value * 18,
                            height: 4 + value * 18
                        )
                        .offset(y: thumbY - (2 + value * 9))
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let y = min(max(drag.location.y, thumbRadius), height - thumbRadius)
                        let t = 1 - (y - thumbRadius) / travel
                        value = min(max(t, 0), 1)
                    }
            )
        }
        .frame(width: 36, height: trackHeight)
    }
}

typealias MarkupWidthSlider = MarkupVerticalSlider

extension Color {
    init?(markupHex: String) {
        var cleaned = markupHex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
