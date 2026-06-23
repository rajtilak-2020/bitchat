# Arti Binary Provenance

This repo vendors a prebuilt Arti static-library xcframework at:

`localPackages/Arti/Frameworks/arti.xcframework`

SwiftPM links it through `localPackages/Arti/Package.swift` as the binary target named `arti`. Treat changes to this artifact like dependency updates: review the Rust sources, lockfile, build script, produced headers, and artifact hashes together.

## Source Inputs

- Rust workspace: `localPackages/Arti/Cargo.toml`
- Crate: `localPackages/Arti/arti-bitchat`
- Dependency lockfile: `localPackages/Arti/Cargo.lock`
- Build script: `localPackages/Arti/build-ios.sh`
- Exported C header: `localPackages/Arti/Frameworks/include/arti.h`

The crate declares `rust-version = "1.90"` and uses `arti-client` / `tor-rtcompat` `0.38` with minimal Tokio/Rustls features. The current lockfile requires Rust 1.90 or newer. The build script currently targets:

- `aarch64-apple-ios`
- `aarch64-apple-ios-sim`
- `aarch64-apple-darwin`

It builds release static libraries with size-oriented flags (`opt-level=z`, fat LTO, one codegen unit, `panic=abort`, stripped symbols), normalizes static-archive metadata with `xcrun libtool -static -D`, then packages them with `xcodebuild -create-xcframework`.

## Regenerating The Artifact

From the repo root:

```sh
cd localPackages/Arti
rustup toolchain install 1.96.0
rustup default 1.96.0
rustup target add aarch64-apple-ios aarch64-apple-ios-sim aarch64-apple-darwin
cargo install cbindgen
./build-ios.sh
```

After rebuilding, verify that:

- `Cargo.lock` changes are intentional and reviewed.
- `Frameworks/include/arti.h` still matches the exported FFI functions used by `TorManager`.
- `Frameworks/arti.xcframework` contains iOS device, iOS simulator, and macOS arm64 slices.
- The main app still passes iOS tests and the macOS build.

## Audited Rebuild

The June 2026 artifact below was rebuilt from source on this host with:

```text
rustc 1.96.0 (ac68faa20 2026-05-25)
cargo 1.96.0 (30a34c682 2026-05-25)
rustup 1.29.0 (28d1352db 2026-03-05)
cbindgen 0.29.3
Xcode 26.5
Build version 17F42
```

Rust 1.86.0 was also checked during the audit and no longer builds this lockfile because `typed-index-collections@3.4.0` requires Rust 1.90.0 or newer.

The build script now normalizes static-archive metadata and writes a stable xcframework `Info.plist`. Two consecutive no-source-change rebuilds on this host produced the same hashes below.

## Current Artifact Hashes

Run this from the repo root to verify the checked-in artifact:

```sh
find localPackages/Arti/Frameworks/arti.xcframework -maxdepth 3 -type f -print0 | sort -z | xargs -0 shasum -a 256
```

Current hashes:

```text
2083d44eafc765db1ffa2691a5c5fabe60b4edbb82b574169ca0c6b98e245e3a  localPackages/Arti/Frameworks/arti.xcframework/Info.plist
551655904834748c9dc36034fdbc9465e7533aef1e4a6514b4fcc75875b93058  localPackages/Arti/Frameworks/arti.xcframework/ios-arm64-simulator/Headers/arti.h
85febff37b751df667a3cab8222de2e1450cefe44b5b62c419adcbce48b9663f  localPackages/Arti/Frameworks/arti.xcframework/ios-arm64-simulator/libarti_bitchat.a
551655904834748c9dc36034fdbc9465e7533aef1e4a6514b4fcc75875b93058  localPackages/Arti/Frameworks/arti.xcframework/ios-arm64/Headers/arti.h
fd25ee379d709a794733fc3c052746d1e6f7b25fec23e5f5234008a3434ce879  localPackages/Arti/Frameworks/arti.xcframework/ios-arm64/libarti_bitchat.a
551655904834748c9dc36034fdbc9465e7533aef1e4a6514b4fcc75875b93058  localPackages/Arti/Frameworks/arti.xcframework/macos-arm64/Headers/arti.h
8c426a41dc3eb76cc3e3e22e3356b9d11dbebdf0a0f248c5ac892e1839352c75  localPackages/Arti/Frameworks/arti.xcframework/macos-arm64/libarti_bitchat.a
```

## Review Checklist

- Record `rustc --version`, `cargo --version`, `cbindgen --version`, and `xcodebuild -version` in the PR when refreshing the binary.
- Include the hash output above after any binary change.
- If a rebuild changes only xcframework/library bytes, record the new hashes and app validation evidence in the PR.
- Keep `target/`, `.build/`, and `.swiftpm/` out of source control.
- Do not accept an xcframework-only update without matching source, lockfile, or build-script evidence explaining where it came from.
