# Veltrio for Apple TV

Native SwiftUI app for tvOS 18+, designed for Siri Remote navigation.

The app shares everything except its shell with macOS and iOS: the
`macos/` submodule ([veltrio-macos](https://github.com/VeltrioApp/veltrio-macos)) brings VeltrioKit (`macos/Shared`:
services, player engine, theme, translations) and the shared screens
(`macos/Veltrio/Views`). This repository adds:

- `Veltrio/TVRootView.swift` — the side navigation rail (Home, Library, Live, Sources, From a phone, Search, Settings);
- `Veltrio/Player/MPVMetalView.swift` — libmpv rendered with Metal ([MPVKit](https://github.com/mpvkit/MPVKit));
- `Veltrio/PairingReceiver.swift` — "From a phone": receives a phone's or Mac's settings (addons, IPTV, debrid keys, accounts, media servers, Collection) over the local network, encrypted.

## Build & run

Prerequisites: Xcode 16+, [`xcodegen`](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
git clone --recurse-submodules https://github.com/VeltrioApp/veltrio-tvos
cd veltrio-tvos
./scripts/fetch-core.sh
xcodegen generate && open Veltrio.xcodeproj
```

Debug builds accept launch arguments (`-veltrioTab`, `-veltrioDetail`, `-veltrioPlay`, `-veltrioSettings`, `-veltrioPair`, `-veltrioKeepControls`) to open any screen directly in the simulator.

## The core

`core.version` pins the [veltrio-core](https://github.com/VeltrioApp/veltrio-core) release to use;
`scripts/fetch-core.sh` downloads `veltrio-core-apple-mobile-tvos.zip` into `Core/`
(gitignored), or set `VELTRIO_CORE_DIR=../veltrio-core` to build from a local checkout.

## CI/CD

- `ci.yml` — pushes to main, pull requests, manual runs: fetches the core, generates the project with XcodeGen, and builds for the tvOS Simulator.
- `release.yml` — tag `vX.Y.Z` or manual run: archives, signs via App Store Connect API, and uploads to TestFlight.

Organisation secrets used: `CORE_RELEASES_TOKEN` (optional), `ASC_KEY_P8`; variables `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`.

## License

Dual-licensed under either of [Apache-2.0](LICENSE-APACHE) or [MIT](LICENSE-MIT). libmpv is linked via [MPVKit](https://github.com/mpvkit/MPVKit) (LGPL).
