import CoreGraphics
import SwiftUI

/// The four local photo looks on the story editor dial.
/// Hick's law: four named choices, plus Original in the centre to clear.
enum PhotoFilterDialLook: String, CaseIterable, Identifiable, Sendable {
    case bw
    case dreamy
    case softLight = "soft-light"
    case dither

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bw: "B/W"
        case .dreamy: "Dreamy"
        case .softLight: "Soft light"
        case .dither: "Dither"
        }
    }

    var systemImage: String {
        switch self {
        case .bw: "circle.lefthalf.filled"
        case .dreamy: "sparkles"
        case .softLight: "sun.min"
        case .dither: "square.grid.3x3"
        }
    }

    var storyFilter: StoryFilter {
        StoryFilter(id: id, title: title, systemImage: systemImage)
    }

    static var ids: Set<String> { Set(allCases.map(\.id)) }
}

/// Angle math for the dial. 0° is 12 o'clock, increasing clockwise.
enum PhotoFilterDialMath {
    static func positiveMod(_ value: Double, _ modulus: Double) -> Double {
        guard modulus > 0 else { return 0 }
        let remainder = value.truncatingRemainder(dividingBy: modulus)
        return remainder < 0 ? remainder + modulus : remainder
    }

    /// Clockwise degrees from the top, in `0..<360`.
    static func degreesClockwiseFromTop(dx: Double, dy: Double) -> Double {
        positiveMod(atan2(dx, -dy) * 180 / .pi, 360)
    }

    /// Index of the sector under `degrees` (clockwise from the top).
    /// Sector boundaries sit halfway between labels so a label's hit area is centred on it.
    static func index(degreesClockwiseFromTop degrees: Double, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let sector = 360.0 / Double(count)
        let shifted = positiveMod(degrees + sector / 2, 360)
        return Int(shifted / sector) % count
    }

    static func degrees(for index: Int, count: Int) -> Double {
        guard count > 0 else { return 0 }
        let wrapped = ((index % count) + count) % count
        return 360.0 * Double(wrapped) / Double(count)
    }
}

/// Rotary picker for B/W, Dreamy, Soft light and Dither.
/// Drag around the ring (Fitts: the whole disc is the target). Labels are also buttons.
struct PhotoFilterDial: View {
    @Binding var selection: StoryFilter
    var accent: Color
    var reduceMotion: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let looks = PhotoFilterDialLook.allCases
    @State private var dialSize = CGSize(width: 280, height: 210)

    var body: some View {
        VStack(spacing: 6) {
            Text(selection.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .accessibilityIdentifier("story.filter.dial.title")
            ZStack {
                plate
                needle
                ForEach(Array(looks.enumerated()), id: \.element.id) { index, look in
                    label(look, index: index)
                }
                originalButton
            }
            .frame(maxWidth: .infinity)
            .frame(height: 210)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { dialSize = proxy.size }
                        .onChange(of: proxy.size) { _, size in dialSize = size }
                }
            }
            .contentShape(Rectangle())
            .gesture(drag)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("story.filter.dial")
        }
    }

    private var plate: some View {
        Circle()
            .fill(reduceTransparency ? Color(white: 0.16) : Color.white.opacity(0.08))
            .overlay {
                Circle().strokeBorder(Color.white.opacity(reduceTransparency ? 0.35 : 0.18), lineWidth: 1)
            }
            .frame(width: 168, height: 168)
            .allowsHitTesting(false)
    }

    private var needle: some View {
        let active = looks.firstIndex { $0.id == selection.id }
        return Capsule()
            .fill(accent)
            .frame(width: 4, height: 46)
            .offset(y: -36)
            .rotationEffect(.degrees(active.map { PhotoFilterDialMath.degrees(for: $0, count: looks.count) } ?? 0))
            .opacity(active == nil ? 0 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: selection.id)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var originalButton: some View {
        let selected = selection.id == "none"
        return Button {
            guard let original = StoryFilter.catalog.first(where: { $0.id == "none" }) else { return }
            selection = original
            HapticEngine.shared.play(.selection)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "circle")
                    .font(.system(size: 16, weight: .semibold))
                Text("Original")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(width: 74, height: 74)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .modulaGlass(in: Circle(), interactive: true, tint: selected ? accent : nil, prominent: selected, specular: true)
        .accessibilityLabel("Original")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("story.filter.dial.original")
    }

    private func label(_ look: PhotoFilterDialLook, index: Int) -> some View {
        let selected = selection.id == look.id
        let point = labelPoint(index: index)
        return Button {
            selection = look.storyFilter
            HapticEngine.shared.play(.selection)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: look.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(look.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(selected ? Color.black : Color.white)
            .frame(width: 72, height: 44)
            .background(selected ? Color.white : Color.white.opacity(reduceTransparency ? 0.22 : 0.12), in: Capsule())
            .overlay {
                Capsule().strokeBorder(Color.white.opacity(selected ? 0 : 0.28), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .position(point)
        .accessibilityLabel(look.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("story.filter.dial.\(look.id)")
    }

    private func labelPoint(index: Int) -> CGPoint {
        let radius = min(dialSize.width, dialSize.height) * 0.42
        let degrees = PhotoFilterDialMath.degrees(for: index, count: looks.count)
        let radians = (degrees - 90) * .pi / 180
        return CGPoint(
            x: dialSize.width / 2 + CGFloat(cos(radians)) * radius,
            y: dialSize.height / 2 + CGFloat(sin(radians)) * radius
        )
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let dx = Double(value.location.x - dialSize.width / 2)
                let dy = Double(value.location.y - dialSize.height / 2)
                guard hypot(dx, dy) > 36 else { return }
                let degrees = PhotoFilterDialMath.degreesClockwiseFromTop(dx: dx, dy: dy)
                let index = PhotoFilterDialMath.index(degreesClockwiseFromTop: degrees, count: looks.count)
                let next = looks[index].storyFilter
                guard selection.id != next.id else { return }
                selection = next
                HapticEngine.shared.play(.selection)
            }
    }
}
