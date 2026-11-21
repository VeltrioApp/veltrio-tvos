import SwiftUI

/// First-launch welcome flow on Apple TV: typing URLs with a remote is tedious,
/// so pairing from an iPhone or Mac is the primary CTA, with one-click Cinemeta
/// catalog setup right beside it.
struct TVOnboardingView: View {
    let onPair: () -> Void
    let onFinish: () -> Void

    @Environment(AppStore.self) private var store
    @State private var isInstallingCinemeta = false
    @State private var errorMessage: String?

    private static let cinemetaURL = "https://v3-cinemeta.strem.io/manifest.json"

    private var hasCinemeta: Bool {
        store.addons.contains { $0.manifest.transportUrl.localizedCaseInsensitiveContains("cinemeta") }
    }

    var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 36) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text("Veltrio")
                        .font(Theme.Font.displaySerif(48, weight: .bold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text("APPLE TV")
                        .font(Theme.Font.eyebrow(13, weight: .bold))
                        .tracking(2.8)
                        .foregroundStyle(Theme.Palette.accentText)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Bienvenue sur Veltrio")
                        .font(Theme.Font.displaySerif(60, weight: .bold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text("Transférez vos sources, comptes et votre Collection depuis votre iPhone ou votre Mac en un instant, ou démarrez directement avec le catalogue films et séries.")
                        .font(Theme.Font.body(26))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(maxWidth: 960, alignment: .leading)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.Font.body(22))
                        .foregroundStyle(Theme.Palette.danger)
                }

                HStack(spacing: 24) {
                    CTAButton(
                        title: "Configurer depuis un téléphone ou un Mac",
                        icon: "iphone"
                    ) {
                        onPair()
                    }

                    GhostButton(
                        title: hasCinemeta ? "Continuer" : "Démarrer avec Cinemeta",
                        icon: hasCinemeta ? "arrow.right" : "sparkles",
                        isEnabled: !isInstallingCinemeta
                    ) {
                        Task { await startWithCinemeta() }
                    }

                    GhostButton(
                        title: "Plus tard",
                        isEnabled: !isInstallingCinemeta
                    ) {
                        UserPrefs.shared.hasCompletedOnboarding = true
                        onFinish()
                    }
                }
                .padding(.top, 12)
            }
            .padding(80)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .preferredColorScheme(.dark)
        .tint(Theme.Palette.accent)
    }

    private func startWithCinemeta() async {
        if !hasCinemeta {
            isInstallingCinemeta = true
            errorMessage = nil
            await store.installAddon(url: Self.cinemetaURL)
            isInstallingCinemeta = false
            if !hasCinemeta, let err = store.lastError {
                errorMessage = err
                return
            }
        }
        UserPrefs.shared.hasCompletedOnboarding = true
        onFinish()
    }
}
