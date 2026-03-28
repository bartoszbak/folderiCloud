import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()

        if let largeBase = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle).withDesign(.rounded) {
            let bold = largeBase.withSymbolicTraits(.traitBold) ?? largeBase
            appearance.largeTitleTextAttributes = [.font: UIFont(descriptor: bold, size: 0)]
        }
        if let inlineBase = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .headline).withDesign(.rounded) {
            let bold = inlineBase.withSymbolicTraits(.traitBold) ?? inlineBase
            appearance.titleTextAttributes = [.font: UIFont(descriptor: bold, size: 0)]
        }

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        return true
    }

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
