# Linphone SDK iOS package

This package-only branch publishes the Swift manifest and generated wrapper for
prebuilt iOS artifacts from Enflick's `linphone-sdk` source. The XCFramework
archives live in the `ios-release` Nexus repository; they are not checked into
Git. Keeping the distribution tree free of binaries and native git submodules
allows Swift Package Manager to resolve it without cloning the full SDK
toolchain.

Each release commit must identify its source commit, reference checksummed
device and simulator XCFramework archives built from that source, and keep the
generated Swift wrapper aligned with the binary API. Applications must pin an
exact commit. Nexus credentials must be available through `.netrc` when SwiftPM
resolves the binary targets.

Native changes belong on `main`; publish rebuilt archives to an immutable Nexus
version path before updating their URLs and checksums here.

## 5.5.12

The current package was built from the 5.5.12 native source stack represented
by `ceec3f300fc0adfcfb28acb71afeb5918d1b1591` on `main`. It includes the
TextNow call/reconnect changes, decoded-audio instrumentation, mobile Opus OSCE,
and private receive-side Opus decoder complexity control.
