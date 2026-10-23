import SwiftUI

@main
struct SeruendeshAIApp: App {
    @State private var app: AppModel
    init() {
        let defaults = UserDefaults.standard
        let live = defaults.string(forKey: "seru.dataMode") == "live"
        let configuredURL = ProcessInfo.processInfo.environment["SERU_API_BASE_URL"] ?? defaults.string(forKey: "seru.apiBaseURL")
        let url = configuredURL.flatMap(URL.init(string:)) ?? BackendAPI.productionURL
        _app = State(initialValue: AppModel(defaults: defaults, backend: live ? BackendAPI(baseURL: url) : nil))
    }
    var body: some Scene {
        WindowGroup {
            SeruSplashContainer { AppRootView() }.environment(app)
                .preferredColorScheme(app.theme == .system ? nil : app.theme == .dark ? .dark : .light)
        }
    }
}
