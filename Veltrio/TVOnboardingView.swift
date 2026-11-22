import SwiftUI

/// First-launch welcome flow on Apple TV: typing URLs with a remote is tedious,
/// so pairing from an iPhone or Mac is the primary CTA, with language selection
/// and direct TMDB API key entry right beside it.
struct TVOnboardingView: View {
    let onPair: () -> Void
    let onFinish: () -> Void

    @Environment(AppStore.self) private var store
    @State private var prefs = UserPrefs.shared
    @State private var tmdb = TmdbService.shared
    @State private var showTmdbField = false
    @State private var tmdbKey = ""

    var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 36) {
                HStack(alignment: .center, spacing: 16) {
                    Text("Veltrio")
                        .font(Theme.Font.displaySerif(48, weight: .bold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text("APPLE TV")
                        .font(Theme.Font.eyebrow(13, weight: .bold))
                        .tracking(2.8)
                        .foregroundStyle(Theme.Palette.accentText)
                    Spacer()
                    HStack(spacing: 12) {
                        ForEach([("fr", "Français"), ("en", "English")], id: \.0) { code, label in
                            let selected = prefs.appLanguage == code || (prefs.appLanguage.isEmpty && (code == "fr") == AppLocalization.isFrench)
                            FrameButton(
                                title: label,
                                color: selected ? Theme.Palette.onAccent : Theme.Palette.textSecondary,
                                fill: selected ? Theme.Palette.accent : Theme.Palette.surface
                            ) {
                                prefs.appLanguage = code
                                tmdb.setLanguage(code == "en" ? "en-US" : "fr-FR")
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text(AppLocalization.isFrench ? "Bienvenue sur Veltrio" : "Welcome to Veltrio")
                        .font(Theme.Font.displaySerif(60, weight: .bold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text(AppLocalization.isFrench
                         ? "Transférez votre clé TMDB, vos sources, comptes et votre Collection depuis votre iPhone ou votre Mac en un instant, ou saisissez directement votre clé TMDB."
                         : "Transfer your TMDB key, sources, accounts and Collection from your iPhone or Mac in seconds, or enter your TMDB API key directly.")
                        .font(Theme.Font.body(26))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(maxWidth: 960, alignment: .leading)
                }

                if showTmdbField {
                    VStack(alignment: .leading, spacing: 16) {
                        SecureField(AppLocalization.isFrench ? "Clé API ou jeton TMDB" : "TMDB API key or Read Access Token", text: $tmdbKey)
                            .frame(maxWidth: 720)
                        if let err = tmdb.error {
                            Text(err)
                                .font(Theme.Font.body(22))
                                .foregroundStyle(Theme.Palette.danger)
                        }
                        HStack(spacing: 20) {
                            CTAButton(
                                title: tmdb.isBusy
                                    ? (AppLocalization.isFrench ? "Connexion…" : "Connecting…")
                                    : (AppLocalization.isFrench ? "Connecter TMDB" : "Connect TMDB"),
                                icon: "checkmark"
                            ) {
                                Task {
                                    if await tmdb.connect(rawKey: tmdbKey) {
                                        tmdbKey = ""
                                        prefs.hasCompletedOnboarding = true
                                        onFinish()
                                    }
                                }
                            }
                            .disabled(tmdb.isBusy || tmdbKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            GhostButton(title: AppLocalization.isFrench ? "Retour" : "Back") {
                                showTmdbField = false
                            }
                        }
                    }
                } else {
                    HStack(spacing: 24) {
                        CTAButton(
                            title: AppLocalization.isFrench
                                ? "Configurer depuis un téléphone ou un Mac"
                                : "Set up from a phone or Mac",
                            icon: "iphone"
                        ) {
                            onPair()
                        }

                        GhostButton(
                            title: tmdb.isConnected
                                ? (AppLocalization.isFrench ? "Continuer" : "Continue")
                                : (AppLocalization.isFrench ? "Configurer TMDB" : "Configure TMDB"),
                            icon: tmdb.isConnected ? "arrow.right" : "key"
                        ) {
                            if tmdb.isConnected {
                                prefs.hasCompletedOnboarding = true
                                onFinish()
                            } else {
                                showTmdbField = true
                            }
                        }

                        GhostButton(title: AppLocalization.isFrench ? "Plus tard" : "Later") {
                            prefs.hasCompletedOnboarding = true
                            onFinish()
                        }
                    }
                    .padding(.top, 12)
                }
            }
            .padding(80)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .preferredColorScheme(.dark)
        .tint(Theme.Palette.accent)
    }
}
