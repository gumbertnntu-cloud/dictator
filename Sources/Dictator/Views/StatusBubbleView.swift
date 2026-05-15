import DictatorCore
import SwiftUI

struct StatusBubbleView: View {
    @ObservedObject var controller: DictationController
    @ObservedObject var audioCapture: AudioCaptureService

    var body: some View {
        Group {
            if case .transcribing = controller.state {
                bubbleContent
                    .padding(12)
                    .background(.regularMaterial, in: Circle())
            } else {
                bubbleContent
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
        .animation(.easeInOut(duration: 0.18), value: stateKey)
    }

    @ViewBuilder
    private var bubbleContent: some View {
        switch controller.state {
        case .listening:
            AudioWaveformView(level: audioCapture.level)
        case .transcribing:
            MagicIndicator()
        case let .fallback(text):
            FallbackBubble(text: text) {
                controller.copyFallbackText()
            }
        case let .error(message):
            ErrorIndicator(message: message)
        case .idle, .inserted:
            EmptyView()
        }
    }

    private var horizontalPadding: CGFloat {
        switch controller.state {
        case .fallback, .error: 12
        default: 14
        }
    }

    private var verticalPadding: CGFloat {
        switch controller.state {
        case .fallback, .error: 8
        default: 10
        }
    }

    private var stateKey: String {
        switch controller.state {
        case .idle: "idle"
        case .listening: "listening"
        case .transcribing: "transcribing"
        case .inserted: "inserted"
        case .fallback: "fallback"
        case .error: "error"
        }
    }
}

private struct AudioWaveformView: View {
    let level: Double

    private let barCount = 18
    private let minimumHeight: CGFloat = 3
    private let maximumHeight: CGFloat = 18

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate * 8
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(.red.opacity(0.82))
                        .frame(width: 3, height: barHeight(index: index, phase: phase))
                }
            }
            .frame(width: 88, height: maximumHeight, alignment: .center)
        }
        .accessibilityLabel("Listening")
    }

    private func barHeight(index: Int, phase: TimeInterval) -> CGFloat {
        let normalizedLevel = min(max(level, 0), 1)
        let soundLift = CGFloat(pow(normalizedLevel, 0.65))
        let center = Double(barCount - 1) / 2
        let distanceFromCenter = abs(Double(index) - center) / center
        let envelope = 1 - CGFloat(distanceFromCenter * 0.52)
        let wave = (sin(phase + Double(index) * 0.72) + 1) / 2
        let motion = CGFloat(wave) * 0.34 + 0.66
        let targetHeight = minimumHeight + (maximumHeight - minimumHeight) * soundLift * envelope * motion
        return max(minimumHeight, targetHeight)
    }
}

private struct MagicIndicator: View {
    @State private var rotation: Double = 0
    @State private var pulse: CGFloat = 0.85

    private let rainbowCycleSeconds: Double = 4.5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let phase = (timeline.date.timeIntervalSinceReferenceDate / rainbowCycleSeconds)
                .truncatingRemainder(dividingBy: 1.0)

            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    rainbowColor(phase: phase, offset: Double(index) * 0.18),
                                    rainbowColor(phase: phase, offset: Double(index) * 0.18 + 0.12),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 4.5, height: 4.5)
                        .offset(y: -11)
                        .rotationEffect(.degrees(rotation + Double(index) * 120))
                }
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                rainbowColor(phase: phase, offset: 0),
                                rainbowColor(phase: phase, offset: 0.33),
                                rainbowColor(phase: phase, offset: 0.66),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(pulse)
            }
        }
        .frame(width: 30, height: 30)
        .onAppear { startAnimations() }
        .accessibilityLabel("Transcribing")
    }

    private func rainbowColor(phase: Double, offset: Double) -> Color {
        let hue = (phase + offset).truncatingRemainder(dividingBy: 1.0)
        return Color(hue: hue, saturation: 0.68, brightness: 1.0)
    }

    private func startAnimations() {
        withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
            rotation = 360
        }
        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
            pulse = 1.15
        }
    }
}

private struct FallbackBubble: View {
    let text: String
    let copyAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .foregroundStyle(.orange)
            Button("Copy", action: copyAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .accessibilityLabel("Text ready, tap Copy")
    }
}

private struct ErrorIndicator: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .lineLimit(2)
                .frame(maxWidth: 220, alignment: .leading)
        }
        .accessibilityLabel(message)
    }
}
