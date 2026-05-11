import DictatorCore
import SwiftUI

struct StatusBubbleView: View {
    @ObservedObject var controller: DictationController
    @ObservedObject var audioCapture: AudioCaptureService

    var body: some View {
        HStack(spacing: 10) {
            icon
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if case .fallback = controller.state {
                Button("Copy") {
                    controller.copyFallbackText()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 190, maxWidth: 360, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var icon: some View {
        switch controller.state {
        case .listening:
            Image(systemName: "mic.fill")
                .foregroundStyle(.red)
        case .transcribing:
            ProgressView()
                .controlSize(.small)
        case .inserted:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .fallback:
            Image(systemName: "doc.on.clipboard")
                .foregroundStyle(.orange)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .idle:
            EmptyView()
        }
    }

    private var title: String {
        switch controller.state {
        case .idle: ""
        case .listening: "Listening"
        case .transcribing: "Transcribing"
        case .inserted: "Inserted"
        case .fallback: "Text ready"
        case .error: "Needs attention"
        }
    }

    private var subtitle: String? {
        switch controller.state {
        case .listening:
            "Microphone level \(Int(audioCapture.level * 100))%"
        case .transcribing:
            "Running local recognition"
        case .inserted:
            "Text was sent to the active field"
        case let .fallback(text):
            text
        case let .error(message):
            message
        case .idle:
            nil
        }
    }
}
