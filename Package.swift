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
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.12-ceec3f300/linphone.xcframework.zip",
            checksum: "be638955364a0acd6404ebbea9589b80d538076a63902fcc714b8595d94e25d0"
        ),
        .binaryTarget(
            name: "bctoolbox-ios",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.12-ceec3f300/bctoolbox-ios.xcframework.zip",
            checksum: "0cd565dcde94f7414e611d23e15bf10c0b26aece909c43523ea7cc9779faaded"
        ),
        .binaryTarget(
            name: "bctoolbox",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.12-ceec3f300/bctoolbox.xcframework.zip",
            checksum: "b0ed3aa0c78040200c6069b119829d91c79c86f9b99d99347b0cc9a41e3fee23"
        ),
        .binaryTarget(
            name: "belr",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.12-ceec3f300/belr.xcframework.zip",
            checksum: "26dbade8fb898faf74b2fa92e2bc8aaa2d102211729d02b2637e67ff967edbc5"
        ),
        .binaryTarget(
            name: "belle-sip",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.12-ceec3f300/belle-sip.xcframework.zip",
            checksum: "6f857267d64bf457cfc0457393448ebe0043c5ed962330335cacbbc2cc3a5d18"
        ),
        .binaryTarget(
            name: "mediastreamer2",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.12-ceec3f300/mediastreamer2.xcframework.zip",
            checksum: "6b47e0649fe64ecebfb6f75a31364f644276fa6f0be1f389b697877109e0f1b4"
        ),
        .binaryTarget(
            name: "msamr",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.12-ceec3f300/msamr.xcframework.zip",
            checksum: "de1b4b8ee6e26aaf9c99e18f17d3e58db88d9d9a5c47fbddc62201db9c890b49"
        ),
        .binaryTarget(
            name: "mscodec2",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.12-ceec3f300/mscodec2.xcframework.zip",
            checksum: "32b798ed7b2e14f9b5f0aafadcafe1dd02546de7b36b61431a411eaaef1ff2b9"
        ),
        .binaryTarget(
            name: "msopenh264",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.12-ceec3f300/msopenh264.xcframework.zip",
            checksum: "d1902b6f5ac734e0e78a91ca8bcba01d4688eba094edc1b7abfcd2689cd6b740"
        ),
        .binaryTarget(
            name: "mbedcrypto",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.12-ceec3f300/mbedcrypto.xcframework.zip",
            checksum: "6fb9ac23887dc9066dd3c7d954fa9496c5e4c2f8933506120b427fad4e8ee395"
        ),
        .binaryTarget(
            name: "mbedtls",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.12-ceec3f300/mbedtls.xcframework.zip",
            checksum: "399012537b1054ef20d2d1f53f16af3f730ce5e017b64250f2b7b9a19336231f"
        ),
        .binaryTarget(
            name: "mbedx509",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.12-ceec3f300/mbedx509.xcframework.zip",
            checksum: "c27cb2e597de640931076489f3140dfb1cba2cbf4fc745f5e4f75847003d180d"
        ),
        .binaryTarget(
            name: "ortp",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.12-ceec3f300/ortp.xcframework.zip",
            checksum: "1ef03a93645f6fe60fb300fad1e49e232f0c54fd656f508b8037cd3a0f1348da"
        )
    ]
)
