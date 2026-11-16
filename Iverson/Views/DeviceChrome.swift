/// Shared materials and chrome for the iverson.io interface.

import SwiftUI

enum DeviceChrome {
    /// Cool aluminum shell — quiet metal, not cream or purple.
    static let shellTop = Color(red: 0.78, green: 0.79, blue: 0.81)
    static let shellBottom = Color(red: 0.62, green: 0.64, blue: 0.67)
    static let bezel = Color(red: 0.22, green: 0.23, blue: 0.24)
    static let glass = Color(red: 0.10, green: 0.105, blue: 0.11)
    static let glassHighlight = Color.white.opacity(0.06)
    static let ink = Color(red: 0.92, green: 0.93, blue: 0.94)
    static let inkQuiet = Color(red: 0.92, green: 0.93, blue: 0.94).opacity(0.38)
    static let inkDim = Color(red: 0.92, green: 0.93, blue: 0.94).opacity(0.22)
    static let metal = Color(red: 0.88, green: 0.89, blue: 0.90)
    static let metalDeep = Color(red: 0.45, green: 0.46, blue: 0.48)
    /// Precision red — the one intentional accent, like a hardware lens.
    static let lens = Color(red: 0.78, green: 0.16, blue: 0.14)
    static let lensGlow = Color(red: 0.90, green: 0.28, blue: 0.24)
    static let linkLive = Color(red: 0.55, green: 0.78, blue: 0.62)

    static var shellGradient: LinearGradient {
        LinearGradient(
            colors: [shellTop, shellBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var glassGradient: LinearGradient {
        LinearGradient(
            colors: [glass.opacity(0.92), glass],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

struct DeviceWordmark: View {
    var subtitle: String = "Speech · Input"

    var body: some View {
        VStack(spacing: 6) {
            Text("iverson.io")
                .font(.system(size: 15, weight: .semibold, design: .default))
                .tracking(1.2)
                .foregroundStyle(DeviceChrome.bezel.opacity(0.55))
            Text(subtitle)
                .font(.system(size: 11, weight: .regular, design: .default))
                .tracking(1.5)
                .foregroundStyle(DeviceChrome.bezel.opacity(0.35))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("iverson.io, speech input")
    }
}

struct DeviceStatusLED: View {
    var isOn: Bool
    var label: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isOn ? DeviceChrome.linkLive : DeviceChrome.metalDeep.opacity(0.45))
                .frame(width: 6, height: 6)
                .shadow(color: isOn ? DeviceChrome.linkLive.opacity(0.7) : .clear, radius: isOn ? 5 : 0)
                .animation(.easeInOut(duration: 0.6), value: isOn)
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .default))
                .tracking(0.6)
                .foregroundStyle(DeviceChrome.bezel.opacity(0.45))
                .lineLimit(1)
        }
    }
}

/// Hold-to-talk key — press while speaking, release to type.
struct DeviceTalkKey: View {
    var isListening: Bool
    var isEnabled: Bool
    var onPress: () -> Void
    var onRelease: () -> Void

    @State private var pressed = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        shape
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(pressed || isListening ? 0.22 : 0.14),
                        Color.white.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 120, height: 52)
            .overlay(
                shape.strokeBorder(
                    (pressed || isListening) ? DeviceChrome.lens.opacity(0.85) : Color.white.opacity(0.22),
                    lineWidth: (pressed || isListening) ? 1.4 : 0.8
                )
            )
            .overlay {
                HStack(spacing: 8) {
                    Image(systemName: isListening ? "mic.fill" : "mic")
                        .font(.system(size: 14, weight: .medium))
                    Text(isEnabled ? (isListening ? "Release" : "Hold") : "Live")
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(1.0)
                }
                .foregroundStyle(DeviceChrome.ink)
            }
            .scaleEffect(pressed || isListening ? 0.97 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: pressed || isListening)
            .opacity(isEnabled ? 1 : 0.35)
            .allowsHitTesting(isEnabled)
            .accessibilityLabel(isListening ? "Release to type" : "Hold to talk")
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard isEnabled, !pressed else { return }
                        pressed = true
                        onPress()
                    }
                    .onEnded { _ in
                        guard pressed else { return }
                        pressed = false
                        onRelease()
                    }
            )
    }
}
