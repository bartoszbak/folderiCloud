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
}
