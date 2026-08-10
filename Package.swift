// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "linphonesw",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(name: "linphonesw", targets: ["linphonesw"])
    ],
    targets: [
        .target(
            name: "linphonesw",
            dependencies: [
                "linphone",
                "bctoolbox-ios",
                "bctoolbox",
                "belr",
                "belle-sip",
                "mediastreamer2",
                "msamr",
                "mscodec2",
                "msopenh264",
                "mbedcrypto",
                "mbedtls",
                "mbedx509",
                "ortp"
            ]
        ),
        .binaryTarget(
            name: "linphone",
            path: "XCFrameworks/linphone.xcframework"
        ),
        .binaryTarget(
            name: "bctoolbox-ios",
            path: "XCFrameworks/bctoolbox-ios.xcframework"
        ),
        .binaryTarget(
            name: "bctoolbox",
            path: "XCFrameworks/bctoolbox.xcframework"
        ),
        .binaryTarget(
            name: "belr",
            path: "XCFrameworks/belr.xcframework"
        ),
        .binaryTarget(
            name: "belle-sip",
            path: "XCFrameworks/belle-sip.xcframework"
        ),
        .binaryTarget(
            name: "mediastreamer2",
            path: "XCFrameworks/mediastreamer2.xcframework"
        ),
        .binaryTarget(
            name: "msamr",
            path: "XCFrameworks/msamr.xcframework"
        ),
        .binaryTarget(
            name: "mscodec2",
            path: "XCFrameworks/mscodec2.xcframework"
        ),
        .binaryTarget(
            name: "msopenh264",
            path: "XCFrameworks/msopenh264.xcframework"
        ),
        .binaryTarget(
            name: "mbedcrypto",
            path: "XCFrameworks/mbedcrypto.xcframework"
        ),
        .binaryTarget(
            name: "mbedtls",
            path: "XCFrameworks/mbedtls.xcframework"
        ),
        .binaryTarget(
            name: "mbedx509",
            path: "XCFrameworks/mbedx509.xcframework"
        ),
        .binaryTarget(
            name: "ortp",
            path: "XCFrameworks/ortp.xcframework"
        )
    ]
)
