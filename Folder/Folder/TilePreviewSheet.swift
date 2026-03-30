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

    private var text: String {
        (post.rawContent ?? post.displayTitle)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? post.displayTitle : text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
        }
        .presentationDetents([.fraction(1 / 3), .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Video tile preview

/// Full-screen AVPlayerViewController cover that begins playback automatically.
struct VideoTilePreviewCover: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.entersFullScreenWhenPlaybackBegins = true
        vc.exitsFullScreenWhenPlaybackEnds = false
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player {
            vc.player = player
        }
    }
}
