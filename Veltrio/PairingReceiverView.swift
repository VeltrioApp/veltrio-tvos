import SwiftUI

/// "From a phone", as on Android TV: the code to type on the phone, this
/// TV's name and address, and what was received.
struct PairingReceiverView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @Environment(WatchStore.self) private var watch
    /// Rebuilds the store once settings arrived, so every service reads
    /// the accounts and keys that were written.
    let onImported: () -> Void

    @State private var receiver = PairingReceiver()

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("Other devices").eyebrow(Theme.Palette.accentText, tracking: 3)
            Text("Receive settings")
                .font(Theme.Font.displaySerif(56, weight: .bold))
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("On your phone or Mac, open Veltrio, Settings, “Send to a TV”, pick this TV (or type its address) and this code.")
                .font(Theme.Font.body(16))
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(maxWidth: 1200, alignment: .leading)
            Rule()
            Text("Code").eyebrow(Theme.Palette.accentText, tracking: 3)
            Text(spaced(receiver.code))
                .font(.system(size: 140, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.Palette.accent)
            VStack(alignment: .leading, spacing: 10) {
                Text(receiver.name)
                if !receiver.addresses.isEmpty {
                    Text("Address: \(receiver.addresses.joined(separator: "  ·  "))")
                }
            }
            .font(Theme.Font.mono(15))
            .foregroundStyle(Theme.Palette.textTertiary)

            Group {
                if receiver.isApplying {
                    HStack(spacing: 16) { ProgressView(); Text("Setting up…") }
                } else if let result = receiver.result {
                    Text(result).foregroundStyle(Theme.Palette.textPrimary)
                } else if let error = receiver.error {
                    Text(error).foregroundStyle(Theme.Palette.danger)
                } else {
                    Text("Waiting for a phone on the same network…").foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            .font(Theme.Font.body(17))

            Text("Sent: addons, IPTV playlists, debrid services, accounts (Stremio, Trakt, SIMKL), media servers and the Collection. Nothing already here is removed. Everything travels encrypted, with a key tied to this code.")
                .font(Theme.Font.caption(12))
                .foregroundStyle(Theme.Palette.textQuaternary)
                .frame(maxWidth: 1300, alignment: .leading)
            Spacer()
            Button(receiver.result == nil ? "Close" : "Done") { dismiss() }
                .buttonStyle(.plainRect)
                .font(Theme.Font.label(16, weight: .bold))
                .padding(.vertical, 8)
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Palette.background.ignoresSafeArea())
        .onAppear {
            receiver.apply = { [store, watch] bundle in
                await PairingImport.apply(bundle, store: store, watch: watch)
            }
            receiver.start()
        }
        .onDisappear {
            receiver.stop()
            if receiver.result != nil { onImported() }
        }
    }

    /// "606355" → "606 355".
    private func spaced(_ code: String) -> String {
        code.count == 6 ? "\(code.prefix(3)) \(code.suffix(3))" : code
    }
}
