import SwiftUI

@main
struct VeltrioApp: App {
    @State private var store = AppStore()
    @State private var watch = WatchStore()
    @State private var prefs = UserPrefs.shared

    init() {
        // The core's torrent engine writes under $HOME/.cache: in a tvOS
        // container that's the Caches folder (tvOS has no other writable
        // place that lasts).
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        setenv("HOME", caches.path, 1)
        initLogging()
    }

    var body: some Scene {
        WindowGroup {
            TVRootView(reload: { store = AppStore() })
                .id(ObjectIdentifier(store))
                .environment(store)
                .environment(watch)
                .environment(\.locale, prefs.resolvedLocale)
        }
    }
}
