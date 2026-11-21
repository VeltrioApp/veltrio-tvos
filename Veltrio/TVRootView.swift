import SwiftUI

/// The app on an Apple TV, laid out as on Android TV: the wordmark and the
/// four numbered sections in a rail on the left, then "From a phone",
/// search and settings; the section on the right, each with its own
/// navigation stack. The pages are the shared views (macos/Veltrio/Views),
/// moved through with the remote's focus; the player goes full screen.
struct TVRootView: View {
    /// Rebuilds the store (settings received from a phone).
    let reload: () -> Void
    @State private var selection: NavItem = .home
    @State private var paths: [NavItem: NavigationPath] = [:]
    @State private var showSettings = false
    @State private var showPairing = false
    @State private var showOnboarding = false
    @FocusState private var focusedRail: RailTarget?
    @Environment(AppStore.self) private var store
    @Environment(WatchStore.self) private var watch

    private enum RailTarget: Hashable { case section(NavItem), pair, search, settings }

    private func path(_ item: NavItem) -> Binding<NavigationPath> {
        Binding(get: { paths[item] ?? NavigationPath() }, set: { paths[item] = $0 })
    }

    /// The rail hides while a page is pushed (a title, the player), as the
    /// tab bar does on a phone.
    private var showsRail: Bool { path(selection).wrappedValue.isEmpty }

    var body: some View {
        HStack(spacing: 0) {
            if showsRail {
                rail
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            NavigationStack(path: path(selection)) {
                section(selection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(Theme.Palette.background)
                    .toolbar(.hidden, for: .navigationBar)
                    .destinations()
            }
            .id(selection)
            // Its own focus section: right from anywhere in the rail lands
            // in the page, even when nothing sits exactly level with it.
            .focusSection()
        }
        .animation(.easeOut(duration: 0.2), value: showsRail)
        .background(Theme.Palette.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(Theme.Palette.accent)
        .fullScreenCover(isPresented: $showSettings) {
            SettingsSheet().tint(Theme.Palette.accent).preferredColorScheme(.dark)
        }
        .fullScreenCover(isPresented: $showPairing) {
            PairingReceiverView(onImported: {
                UserPrefs.shared.hasCompletedOnboarding = true
                showOnboarding = false
                reload()
            }).preferredColorScheme(.dark)
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            TVOnboardingView(
                onPair: {
                    showOnboarding = false
                    showPairing = true
                },
                onFinish: {
                    showOnboarding = false
                }
            )
        }
        .task {
            await store.stremioAccount.syncOnLaunchIfNeeded(into: watch)
            await debugLaunch()
            if !UserPrefs.shared.hasCompletedOnboarding
                && !UserDefaults.standard.bool(forKey: "veltrioSkipOnboarding")
                && !showSettings && !showPairing {
                let alreadyConfigured = !store.addons.isEmpty
                    || !store.iptvPlaylists.isEmpty
                    || store.jellyfin.isConnected
                    || store.emby.isConnected
                    || store.plex.isConnected
                if alreadyConfigured {
                    UserPrefs.shared.hasCompletedOnboarding = true
                } else {
                    showOnboarding = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .veltrioShowOnboarding)) { _ in
            showSettings = false
            showOnboarding = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .veltrioGoto)) { note in
            if let item = note.object as? NavItem { selection = item }
        }
        .onReceive(NotificationCenter.default.publisher(for: .veltrioPlay)) { note in
            if let destination = note.object as? PlayerDestination { path(selection).wrappedValue.append(destination) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .veltrioZap)) { note in
            guard let destination = note.object as? PlayerDestination else { return }
            var p = path(selection).wrappedValue
            if !p.isEmpty { p.removeLast() }
            p.append(destination)
            path(selection).wrappedValue = p
        }
        .onReceive(NotificationCenter.default.publisher(for: .veltrioOpenSearch)) { _ in
            path(selection).wrappedValue.append(SearchDestination())
        }
    }

    // MARK: - rail

    private var rail: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Veltrio")
                .font(Theme.Font.displaySerif(30, weight: .bold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .padding(.leading, 28)
                .padding(.bottom, 40)
            ForEach(NavItem.allCases) { item in
                RailButton(number: String(format: "%02d", item.index), label: item.rawValue,
                           isActive: selection == item) { selection = item }
                    .focused($focusedRail, equals: .section(item))
            }
            Spacer()
            // Setting a TV up with a remote is tedious: a phone's settings,
            // one step away.
            RailButton(icon: "iphone", label: "From a phone") { showPairing = true }
                .focused($focusedRail, equals: .pair)
            RailButton(icon: "magnifyingglass", label: "Search") {
                path(selection).wrappedValue.append(SearchDestination())
            }
            .focused($focusedRail, equals: .search)
            RailButton(icon: "gearshape", label: "Settings") { showSettings = true }
                .focused($focusedRail, equals: .settings)
        }
        .padding(.vertical, 50)
        .frame(width: 340)
        .frame(maxHeight: .infinity)
        .background(Theme.Palette.backgroundAlt.ignoresSafeArea())
        .focusSection()
        // Coming back from the page, the focus lands on the open section,
        // not on whatever sits level with the button left behind.
        .defaultFocus($focusedRail, .section(selection), priority: .userInitiated)
        .onAppear { if focusedRail == nil { focusedRail = .section(selection) } }
    }

    @ViewBuilder
    private func section(_ item: NavItem) -> some View {
        switch item {
        case .home:    HomeView()
        case .library: LibraryView()
        case .iptv:    IPTVView()
        case .addons:  SourcesView()
        }
    }

    // MARK: - debug

    /// Debug builds: `-veltrioInstall <manifest url>`, `-veltrioTab home|library|iptv|addons`,
    /// `-veltrioDetail <type>:<id>`, `-veltrioPlay <url>`, `-veltrioSettings YES`,
    /// `-veltrioPair YES` set the app up for screenshots in the simulator.
    private func debugLaunch() async {
        #if DEBUG
        let args = UserDefaults.standard
        if let url = args.string(forKey: "veltrioInstall"), !store.addons.contains(where: { $0.manifest.transportUrl == url }) {
            await store.installAddon(url: url)
        }
        if let tab = args.string(forKey: "veltrioTab"), let item = NavItem.allCases.first(where: { "\($0)" == tab }) { selection = item }
        if args.bool(forKey: "veltrioSettings") { showSettings = true }
        if args.bool(forKey: "veltrioPair") { showPairing = true }
        if let raw = args.string(forKey: "veltrioPlay"), let url = URL(string: raw) {
            path(selection).wrappedValue.append(PlayerDestination(
                kind: .libraryItem(.init(url: url, serverName: "Test", itemId: "test", poster: nil, itemType: "Movie")),
                title: "Test"))
        }
        if args.bool(forKey: "veltrioSearch") { path(selection).wrappedValue.append(SearchDestination()) }
        if let detail = args.string(forKey: "veltrioDetail"), let addon = store.addons.first {
            let parts = detail.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 { path(selection).wrappedValue.append(DetailDestination(addon: addon, type: parts[0], id: parts[1], name: parts[1])) }
        }
        #endif
    }
}

/// One line of the rail: a numbered section, or an icon and a label.
private struct RailButton: View {
    var number: String? = nil
    var icon: String? = nil
    let label: String
    var isActive = false
    let action: () -> Void
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Rectangle()
                    .fill(isActive ? Theme.Palette.accent : .clear)
                    .frame(width: 4, height: 26)
                if let number {
                    Text(number).font(Theme.Font.mono(12, weight: .semibold)).foregroundStyle(Theme.Palette.accentText)
                }
                if let icon {
                    Image(systemName: icon).font(.system(size: 22, weight: .medium)).frame(width: 30)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Text(label.localized.uppercased())
                    .font(Theme.Font.eyebrow(number != nil ? 13 : 11, weight: .bold))
                    .tracking(2.4)
                    .foregroundStyle(isActive ? Theme.Palette.textPrimary : Theme.Palette.textTertiary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .padding(.trailing, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plainRect)
        .padding(.horizontal, 12)
    }
}

private extension View {
    /// The pages any section can open, as on the iPhone and the Mac.
    func destinations() -> some View {
        self
            .navigationDestination(for: DetailDestination.self) { DetailView(destination: $0) }
            .navigationDestination(for: PlayerDestination.self) { dest in
                // One player per destination: zapping replaces the top of
                // the stack, and a reused view would keep the old stream.
                PlayerView(destination: dest)
                    .id(dest)
                    .toolbar(.hidden, for: .navigationBar)
                    .ignoresSafeArea()
            }
            .navigationDestination(for: MediaServerSeriesDestination.self) { MediaServerSeriesView(destination: $0) }
            .navigationDestination(for: IptvSeriesDestination.self) { IptvSeriesView(destination: $0) }
            .navigationDestination(for: SearchDestination.self) { _ in SearchView() }
            .navigationDestination(for: CatalogDestination.self) { CatalogGridView(destination: $0) }
    }
}
