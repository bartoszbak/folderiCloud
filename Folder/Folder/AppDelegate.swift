import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Called by iOS when a background URLSession finishes its tasks while the app was suspended.
    /// Re-attaching to MediaUploadSession ensures its delegate receives the completion events,
    /// and the stored completion handler tells iOS we're done processing them.
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == MediaUploadSession.sessionIdentifier else { return }
        MediaUploadSession.shared.backgroundCompletionHandler = completionHandler
    }
}
