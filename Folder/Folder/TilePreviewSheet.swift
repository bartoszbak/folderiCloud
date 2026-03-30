import SwiftUI
import SafariServices
import AVKit

// MARK: - Safari sheet

/// Wraps SFSafariViewController so links open in-app immediately.
struct SafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

// MARK: - Text tile preview

/// Bottom sheet showing the full text of an "aside" post.
/// Appears at 1/3 screen height; drag the handle up to expand to full screen.
struct TextTilePreviewSheet: View {
    let post: WordPressPost
    @Environment(\.dismiss) private var dismiss

    private var text: String {
        (post.rawContent ?? post.displayTitle)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Thoughts")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Circle())
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView {
                Text(text.isEmpty ? post.displayTitle : text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
            }
        }
        .presentationDetents([.fraction(1 / 3), .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Video tile preview

/// Full-screen AVPlayerViewController cover that begins playback automatically.
struct VideoTilePreviewCover: UIViewControllerRepresentable {
    let player: AVPlayer
    var onDismiss: (() -> Void)?

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var onDismiss: (() -> Void)?

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willEndFullScreenPresentationWithAnimationCoordinator coordinator: any UIViewControllerTransitionCoordinator
        ) {
            Task { @MainActor [weak self] in self?.onDismiss?() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.entersFullScreenWhenPlaybackBegins = true
        vc.exitsFullScreenWhenPlaybackEnds = false
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
        context.coordinator.onDismiss = onDismiss
    }
}
