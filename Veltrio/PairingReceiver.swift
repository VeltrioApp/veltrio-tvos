import Foundation
import Network
import CryptoKit
import Observation

/// "From a phone": receives another device's settings, so a TV isn't set up
/// with a remote. The Android TV app's protocol (see veltrio-android's
/// README), which the iPhone, Mac and Android apps already send:
///
/// The TV advertises `_veltrio-pair._tcp` over DNS-SD and shows a 6-digit
/// code. `GET /veltrio-pair` answers `{name, publicKey, version}`: an
/// ephemeral P-256 key (X9.63, base64). The sender derives the AES-256-GCM
/// key with ECDH and HKDF-SHA256 (salt: the code; info: "veltrio-pair-v1")
/// and posts `{publicKey, nonce, data}`, data being the settings JSON
/// sealed, tag appended. A wrong code fails the tag check (403); after five
/// the TV draws a new code and key.
@MainActor
@Observable
final class PairingReceiver {
    static let serviceType = "_veltrio-pair._tcp"
    static let port: UInt16 = 8765

    private(set) var code = ""
    private(set) var name = ""
    /// "192.168.1.20:8765", to type on the phone when discovery is blocked.
    private(set) var addresses: [String] = []
    private(set) var isRunning = false
    private(set) var isApplying = false
    private(set) var result: String?
    private(set) var error: String?

    private var key = P256.KeyAgreement.PrivateKey()
    private var failures = 0
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "veltrio.pairing")
    /// Applies a received bundle; returns the summary to show.
    var apply: (_ bundle: [String: Any]) async -> String = { _ in "" }

    func start() {
        guard !isRunning else { return }
        name = String(localized: "Veltrio · \(PairingSender.deviceName)")
        code = Self.newCode()
        key = P256.KeyAgreement.PrivateKey()
        failures = 0
        result = nil
        error = nil
        // A fixed port when free, so it can be typed (and forwarded).
        let listener = (try? NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: Self.port)!)) ?? (try? NWListener(using: .tcp))
        guard let listener else {
            error = String(localized: "Could not listen on the network.")
            return
        }
        listener.service = NWListener.Service(name: name, type: Self.serviceType)
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: self?.queue ?? .main)
            Task { @MainActor in self?.receive(on: connection, buffer: Data()) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    let port = listener.port?.rawValue ?? Self.port
                    self.addresses = Self.localIPv4().map { "\($0):\(port)" }
                case .failed(let e):
                    self.error = String(localized: "Could not listen on the network (\(e.localizedDescription)).")
                default: break
                }
            }
        }
        listener.start(queue: queue)
        self.listener = listener
        isRunning = true
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private static func newCode() -> String { String(format: "%06d", Int.random(in: 0..<1_000_000)) }

    // MARK: - HTTP, just enough

    /// Reads until the headers and the announced body are in, then answers.
    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] chunk, _, done, failure in
            Task { @MainActor in
                guard let self else { return }
                var data = buffer
                if let chunk { data.append(chunk) }
                if let request = Self.parse(data) {
                    await self.handle(request, on: connection)
                } else if done || failure != nil || data.count > 64 << 20 {
                    connection.cancel()
                } else {
                    self.receive(on: connection, buffer: data)
                }
            }
        }
    }

    private struct Request { let method: String; let path: String; let body: Data }

    /// A complete request, or nil while bytes are missing.
    private static func parse(_ data: Data) -> Request? {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[..<end.lowerBound], as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        guard parts.count >= 2 else { return Request(method: "", path: "", body: Data()) }
        var length = 0
        for line in lines.dropFirst() where line.lowercased().hasPrefix("content-length:") {
            length = Int(line.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) ?? 0
        }
        let bodyStart = end.upperBound
        guard data.count - bodyStart >= length else { return nil }
        return Request(method: String(parts[0]), path: String(parts[1]),
                       body: data[bodyStart..<(bodyStart + length)])
    }

    private func handle(_ request: Request, on connection: NWConnection) async {
        guard request.path.split(separator: "?").first == "/veltrio-pair" else {
            return respond(connection, 404, ["error": "not found"])
        }
        switch request.method {
        case "GET":
            respond(connection, 200, [
                "name": name,
                "publicKey": key.publicKey.x963Representation.base64EncodedString(),
                "version": 1,
            ])
        case "POST":
            await receiveBundle(request.body, on: connection)
        default:
            respond(connection, 405, ["error": "method"])
        }
    }

    private func receiveBundle(_ body: Data, on connection: NWConnection) async {
        let plain: Data
        do {
            guard let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let theirsRaw = (json["publicKey"] as? String).flatMap({ Data(base64Encoded: $0) }),
                  let nonce = (json["nonce"] as? String).flatMap({ Data(base64Encoded: $0) }),
                  let sealed = (json["data"] as? String).flatMap({ Data(base64Encoded: $0) }),
                  sealed.count > 16 else { throw CocoaError(.coderReadCorrupt) }
            let theirs = try P256.KeyAgreement.PublicKey(x963Representation: theirsRaw)
            let symmetric = try key.sharedSecretFromKeyAgreement(with: theirs).hkdfDerivedSymmetricKey(
                using: SHA256.self, salt: Data(code.utf8),
                sharedInfo: Data("veltrio-pair-v1".utf8), outputByteCount: 32)
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce),
                                            ciphertext: sealed.dropLast(16), tag: sealed.suffix(16))
            plain = try AES.GCM.open(box, using: symmetric)
        } catch {
            // A wrong code: after five, a new code and key.
            failures += 1
            if failures >= 5 {
                failures = 0
                key = P256.KeyAgreement.PrivateKey()
                code = Self.newCode()
                self.error = String(localized: "Too many tries: new code.")
            } else {
                self.error = String(localized: "Wrong code.")
            }
            return respond(connection, 403, ["error": "Code incorrect."])
        }
        guard let bundle = try? JSONSerialization.jsonObject(with: plain) as? [String: Any] else {
            return respond(connection, 400, ["error": "bad bundle"])
        }
        error = nil
        isApplying = true
        let summary = await apply(bundle)
        isApplying = false
        let from = bundle["from"] as? String ?? ""
        result = String(localized: "Received from \(from): \(summary).")
        respond(connection, 200, ["result": summary])
    }

    private func respond(_ connection: NWConnection, _ status: Int, _ body: [String: Any]) {
        let payload = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        var out = Data("HTTP/1.1 \(status) OK\r\nContent-Type: application/json\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n".utf8)
        out.append(payload)
        connection.send(content: out, completion: .contentProcessed { _ in connection.cancel() })
    }

    // MARK: - addresses

    /// This TV's IPv4 addresses on the local network.
    private static func localIPv4() -> [String] {
        var result: [String] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = pointer.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  (ifa.ifa_flags & UInt32(IFF_LOOPBACK)) == 0, (ifa.ifa_flags & UInt32(IFF_UP)) != 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                result.append(String(cString: host))
            }
        }
        return result
    }
}

// MARK: - applying a bundle

/// What a received bundle changes here: additive, nothing already set up is
/// removed or replaced. Accounts and keys land in the Keychain and the
/// defaults under this app's names; the caller then rebuilds the store so
/// every service reads them.
@MainActor
enum PairingImport {
    /// The bundle's secret names → this app's Keychain services (the
    /// reverse of `PairingSender.collect`).
    private static let keychain: [String: String] = [
        "debrid.realdebrid": "com.veltrio.debrid.realdebrid", "debrid.alldebrid": "com.veltrio.debrid.alldebrid",
        "debrid.premiumize": "com.veltrio.debrid.premiumize", "debrid.torbox": "com.veltrio.debrid.torbox",
        "stremio.authkey": "com.veltrio.stremio.authkey", "trakt.token": "com.veltrio.trakt.token",
        "simkl.token": "com.veltrio.simkl.token", "mediaserver.jellyfin": "com.veltrio.jellyfin.token",
        "mediaserver.emby": "com.veltrio.emby.token", "mediaserver.plex": "com.veltrio.plex.token",
        "tmdb.key": TmdbService.keyService, "tmdb.lang": TmdbService.langService,
    ]

    static func apply(_ bundle: [String: Any], store: AppStore, watch: WatchStore) async -> String {
        let defaults = UserDefaults.standard

        // Addons, in the sender's order; then the ones it had switched off.
        var addons = 0
        for url in bundle["addons"] as? [String] ?? [] where !store.addons.contains(where: { $0.manifest.transportUrl == url }) {
            let before = store.addons.count
            await store.installAddon(url: url)
            if store.addons.count > before { addons += 1 }
        }
        for url in bundle["disabledAddons"] as? [String] ?? [] {
            if let addon = store.addons.first(where: { $0.manifest.transportUrl == url }) {
                store.setAddonEnabled(id: addon.id, enabled: false)
            }
        }

        // IPTV: Xtream passwords included.
        let refs: [IptvPlaylistRef] = (bundle["playlists"] as? [[String: Any]] ?? []).compactMap { p in
            let name = p["name"] as? String ?? ""
            if let host = p["host"] as? String, !host.isEmpty {
                let creds = XtreamCredentials(host: host, username: p["username"] as? String ?? "",
                                              password: p["password"] as? String ?? "", output: p["output"] as? String ?? "ts")
                return IptvPlaylistRef(id: UUID(), name: name.isEmpty ? (URL(string: creds.normalizedHost)?.host ?? "Xtream") : name,
                                       url: "", xtream: creds, addedAt: Date())
            }
            guard let url = p["url"] as? String, url.hasPrefix("http") else { return nil }
            return IptvPlaylistRef(id: UUID(), name: name.isEmpty ? (URL(string: url)?.host ?? "Playlist") : name,
                                   url: url, xtream: nil, addedAt: Date())
        }
        let playlists = store.importIptvPlaylists(refs)

        // Accounts and keys: what isn't set here yet.
        var accounts = Set<String>()
        for (name, value) in bundle["secrets"] as? [String: String] ?? [:] {
            guard !value.isEmpty else { continue }
            if let service = keychain[name], (Keychain.get(service: service)?.isEmpty ?? true) {
                if Keychain.set(value, service: service) {
                    // A media server per kind; otherwise the service ("debrid", "trakt"…).
                    accounts.insert(name.hasPrefix("mediaserver.") ? name : String(name.prefix { $0 != "." }))
                }
            }
        }
        TmdbService.shared.reload()
        if let appLang = bundle["appLanguage"] as? String, !appLang.isEmpty {
            UserPrefs.shared.appLanguage = appLang
        }
        if let kidsMode = bundle["kidsMode"] as? Bool {
            UserPrefs.shared.kidsMode = kidsMode
        }
        if let kidsPin = bundle["kidsPin"] as? String, !kidsPin.isEmpty {
            UserPrefs.shared.kidsPin = kidsPin
        }
        store.mergeIptvFavoritesAndHidden(
            favorites: bundle["iptvFavorites"] as? [String] ?? [],
            hiddenGroups: bundle["iptvHiddenGroups"] as? [String] ?? []
        )
        if let email = (bundle["secrets"] as? [String: String])?["stremio.email"], defaults.string(forKey: "veltrio.stremio.email") == nil {
            defaults.set(email, forKey: "veltrio.stremio.email")
        }
        for (kind, value) in bundle["mediaServers"] as? [String: [String: Any]] ?? [:] {
            switch kind {
            case "jellyfin", "emby":
                guard defaults.string(forKey: "veltrio.\(kind).userId") == nil else { continue }
                for field in ["url", "userId", "userName", "deviceId"] {
                    if let v = value[field] as? String, !v.isEmpty { defaults.set(v, forKey: "veltrio.\(kind).\(field)") }
                }
            case "plex":
                if defaults.string(forKey: "veltrio.plex.clientId") == nil, let id = value["deviceId"] as? String, !id.isEmpty {
                    defaults.set(id, forKey: "veltrio.plex.clientId")
                }
            default: break
            }
        }

        // The Collection: saved, watched, where each film stopped.
        func date(_ v: Any?) -> Date? { (v as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) } }
        let items: [ImportedWatchItem] = (bundle["watch"] as? [[String: Any]] ?? []).compactMap { e in
            guard let type = e["type"] as? String, type == "movie" || type == "series",
                  let id = e["contentId"] as? String else { return nil }
            var item = ImportedWatchItem(type: type, id: id, name: e["name"] as? String ?? "")
            item.poster = e["poster"] as? String
            item.inLibrary = e["inLibrary"] as? Bool ?? false
            item.watched = e["watched"] as? Bool ?? false
            item.position = (e["position"] as? NSNumber)?.doubleValue
            item.duration = (e["duration"] as? NSNumber)?.doubleValue
            item.lastWatched = date(e["lastWatchedAt"])
            return item
        }
        let titles = watch.merge(items)

        func count(_ n: Int, _ one: String, _ many: String) -> String? {
            n == 0 ? nil : "\(n) \(n > 1 ? many : one)"
        }
        let parts = [
            count(addons, "addon", "addons"),
            count(playlists, "playlist", "playlists"),
            count(accounts.count, String(localized: "account or service"), String(localized: "accounts and services")),
            count(titles, String(localized: "Collection title"), String(localized: "Collection titles")),
        ].compactMap { $0 }
        return parts.isEmpty ? String(localized: "nothing new, everything was already here") : parts.joined(separator: ", ")
    }
}
