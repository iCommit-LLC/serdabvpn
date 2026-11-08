# WireGuardKit (vendored)

The Swift and Go sources of [wireguard-apple](https://github.com/WireGuard/wireguard-apple)
at commit `2fec12a6` (tag 1.0.16-27), MIT, copied unchanged except for two lines:

- `Package.swift` says `swift-tools-version:5.5`; upstream's `5.3` cannot
  declare `.iOS(.v15)` and Xcode 26 refuses to resolve the manifest.
- `Sources/WireGuardKitC/WireGuardKitC.h` includes `<sys/types.h>`; Xcode 26's
  explicit module builds no longer find `u_int32_t` by accident.

`Sources/WireGuardKitGo` is the Go engine. Swift Package Manager cannot build
it, so the Xcode target `WireGuardGoBridgeiOS` runs its Makefile (needs `go`,
`brew install go`) and the extension links the resulting `libwg-go.a`.
