# Veltrio for Apple TV

SwiftUI, tvOS 18+, moved through with the Siri Remote's focus.

The app shares everything but its shell with the Mac and the iPhone: the
`macos/` submodule (veltrio-macos) brings VeltrioKit (`macos/Shared`:
services, player engine, theme, translations) and the screens
(`macos/Veltrio/Views`). This repository adds:

- `Veltrio/TVRootView.swift` — the rail on the left (sections, From a
  phone, Search, Settings), as on Android TV;
- `Veltrio/Player/MPVMetalView.swift` — libmpv drawn with Metal (MPVKit);
- `Veltrio/PairingReceiver.swift` — "From a phone": receives a phone's or
  a Mac's settings (addons, IPTV, debrid keys, accounts, media servers,
  Collection) over the local network, encrypted, as the Android TV app
  does.

Build: `./scripts/fetch-core.sh && xcodegen generate`, then open
`Veltrio.xcodeproj`. Debug builds take `-veltrioTab`, `-veltrioDetail`,
`-veltrioPlay`, `-veltrioSettings`, `-veltrioPair` to open a screen in
the simulator.

## The core

`core.version` names the veltrio-core release to use;
`scripts/fetch-core.sh` downloads its `veltrio-core-apple-mobile-tvos.zip` into `Core/`
(gitignored). Needs [`gh`](https://cli.github.com) (signed in), or `VELTRIO_CORE_DIR=../veltrio-core` to
build from a local checkout.

tvOS is a tier-3 Rust target: the core's release builds it with a nightly toolchain and may skip it if nightly breaks. Pin a core release that has `veltrio-core-apple-mobile-tvos.zip`.

## CI/CD

- `ci.yml` — pushes to main, pull requests, manual runs: fetches the core, then builds and tests once
  `project.yml` (XcodeGen) exists. Until then it only checks the core download.
- `release.yml` — tag `vX.Y.Z`: archive, sign and upload to TestFlight. Skipped until the project exists.

Organisation secrets used: `CORE_RELEASES_TOKEN` (optional: the repositories are public, so the workflow token can read core releases), `APPLE_DISTRIBUTION_P12`, `APPLE_DISTRIBUTION_PASSWORD`, `ASC_KEY_P8`; variables `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`.
