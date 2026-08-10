# Linphone SDK iOS package

This package-only branch publishes prebuilt iOS artifacts from Enflick's
`linphone-sdk` source. Keeping the distribution tree free of native git
submodules allows Swift Package Manager to resolve it without cloning the full
SDK toolchain.

Each release commit must identify its source commit, contain device and
simulator XCFrameworks built from that source, and keep the generated Swift
wrapper aligned with the binary API. Applications must pin an exact commit.

Native changes belong on `main`; do not edit generated artifacts here by hand.
