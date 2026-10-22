// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "linphonesw",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "linphonesw",
            targets: ["linphonesw"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "bctoolbox-ios",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.33-25d076001/bctoolbox-ios.xcframework.zip",
            checksum: "621763594ef5325c03f0dbbc466b81a80df7d2fa82064bfc672b6c702c3a4b7d"
        ),
        .binaryTarget(
            name: "bctoolbox",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.33-25d076001/bctoolbox.xcframework.zip",
            checksum: "ee885c84a7f6a46a0286032d3fdd3a8bf16d095a3d696440eb9dd3e473cf36aa"
        ),
        .binaryTarget(
            name: "belcard",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.33-25d076001/belcard.xcframework.zip",
            checksum: "00ef1fa73843a8f73c17ac0ab66c76136dbe258defc7a145389e9eda7344a8e4"
        ),
        .binaryTarget(
            name: "belle-sip",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.33-25d076001/belle-sip.xcframework.zip",
            checksum: "5d67367c5f82d35475daacd45888423f6dbd21e8594e027cceae6536d536922b"
        ),
        .binaryTarget(
            name: "belr",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.33-25d076001/belr.xcframework.zip",
            checksum: "c5b2612dce3e5795e0387b0c351869dbeaaf8acecb25e7a7715ed216f33d6888"
        ),
        .binaryTarget(
            name: "lime",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.33-25d076001/lime.xcframework.zip",
            checksum: "b5b1bfe8276f886f005266abcbdaee5e9b9f566c07f213cf8ea7a491a7f28406"
        ),
        .binaryTarget(
            name: "linphone",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.33-25d076001/linphone.xcframework.zip",
            checksum: "1d735dbede8ded48b3b331f9a92f997366c2f560402ae7b17034537c89d6515e"
        ),
        .binaryTarget(
            name: "mbedcrypto",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.33-25d076001/mbedcrypto.xcframework.zip",
            checksum: "af5171f4386cfad9118d412d8a8e08458ee33a8193abfeb19525141e6301da19"
        ),
        .binaryTarget(
            name: "mbedtls",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.33-25d076001/mbedtls.xcframework.zip",
            checksum: "ea9a5d8137e1004271b8331cc04e76575a229930a7088d928b6a596e2a10cc45"
        ),
        .binaryTarget(
            name: "mbedx509",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.33-25d076001/mbedx509.xcframework.zip",
            checksum: "e78cd2d52c2bead2c44071fd93b9baf01bb29eb6d6385882c745513080b84c07"
        ),
        .binaryTarget(
            name: "mediastreamer2",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.33-25d076001/mediastreamer2.xcframework.zip",
            checksum: "d588fc24279cff258151ffc39fceebef9b667dc066c27c831a05079d807608ae"
        ),
        .binaryTarget(
            name: "msamr",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.33-25d076001/msamr.xcframework.zip",
            checksum: "8198f3b1ce9cab55681dee241d3e88110f327737a3afb47164805a1ad20789e4"
        ),
        .binaryTarget(
            name: "mscodec2",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.33-25d076001/mscodec2.xcframework.zip",
            checksum: "5291ff0253b7b0af465b0b8a2223859d5525233d6ce5b616bfd810dbfac817ce"
        ),
        .binaryTarget(
            name: "msopenh264",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.33-25d076001/msopenh264.xcframework.zip",
            checksum: "2bc363835836322647dfbee2e773a4b9dffc9064eaf44d6719c2f56809f14c6e"
        ),
        .binaryTarget(
            name: "ortp",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.33-25d076001/ortp.xcframework.zip",
            checksum: "ccac45a9ba48b88ad61b3486dcc5bb9abade1e1fbba07a84047bd7ef000cefab"
        ),
        .target(
            name: "linphonesw",
            dependencies: ["bctoolbox-ios", "bctoolbox", "belcard", "belle-sip", "belr", "lime", "linphone", "mbedcrypto", "mbedtls", "mbedx509", "mediastreamer2", "msamr", "mscodec2", "msopenh264", "ortp"]
        )
    ]
)
