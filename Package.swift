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
            name: "linphone",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.23-2625360cf/linphone.xcframework.zip",
            checksum: "a323ef9893717391a06a307c755567f3b5f98463be0570b9059480c491cd7f01"
        ),
        .binaryTarget(
            name: "bctoolbox-ios",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.23-2625360cf/bctoolbox-ios.xcframework.zip",
            checksum: "3cb074e6fe1b8df1265d79ace8d6b98aed2802947df58b7023e50d60fcae5fd0"
        ),
        .binaryTarget(
            name: "bctoolbox",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.23-2625360cf/bctoolbox.xcframework.zip",
            checksum: "fa1363d6dfd3d6429fea21aac2666820a307c507b158336237c19e8e1b532817"
        ),
        .binaryTarget(
            name: "belr",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.23-2625360cf/belr.xcframework.zip",
            checksum: "7e0b7e1672a8e5627c0e19530f937f7bb8cbec7fb2709f4a719b43056be66bec"
        ),
        .binaryTarget(
            name: "belle-sip",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.23-2625360cf/belle-sip.xcframework.zip",
            checksum: "0c47833c7549b0a6333996d4f62cffbd7f3c1b7419ac8905734065c4d2cb9113"
        ),
        .binaryTarget(
            name: "mediastreamer2",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.23-2625360cf/mediastreamer2.xcframework.zip",
            checksum: "51ba485b1df978acb4363c659fafad862850add3c5950f4e6b5ff180787924da"
        ),
        .binaryTarget(
            name: "msamr",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.23-2625360cf/msamr.xcframework.zip",
            checksum: "7f623ed15f82e172e7c5fa8790d89a9954460bcb0e8b5f1d7c3a58ca7fc10b2f"
        ),
        .binaryTarget(
            name: "mscodec2",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.23-2625360cf/mscodec2.xcframework.zip",
            checksum: "77aa9ee678083d54e1d1b9d93b65282d564917b634c9e04af2959124adfc9f38"
        ),
        .binaryTarget(
            name: "msopenh264",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.23-2625360cf/msopenh264.xcframework.zip",
            checksum: "d552001c8693d0218502d5eb510de070fc5e2f3428917ac463d11c88119e01fa"
        ),
        .binaryTarget(
            name: "mbedcrypto",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.23-2625360cf/mbedcrypto.xcframework.zip",
            checksum: "5aa396e031c42038efa70bd4c34aceea41f3818399152b23c47da93a003d4807"
        ),
        .binaryTarget(
            name: "mbedtls",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.23-2625360cf/mbedtls.xcframework.zip",
            checksum: "b69e7c7eab32d97a6cc796de7a2f7c18939a07a40a8d98681c2302141244894b"
        ),
        .binaryTarget(
            name: "mbedx509",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.23-2625360cf/mbedx509.xcframework.zip",
            checksum: "cc89c616cf739fe95f37f1ff26eb1855ae1d2c42dbc24a169fd8c0aa1f2c0369"
        ),
        .binaryTarget(
            name: "ortp",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.23-2625360cf/ortp.xcframework.zip",
            checksum: "ea090664766d81e97975847ebcbd7e6d5561338e78dfaffa4260c870fe92b52b"
        ),
        .target(
            name: "linphonesw",
            dependencies: ["linphone", "bctoolbox-ios", "bctoolbox", "belr", "belle-sip", "mediastreamer2", "msamr", "mscodec2", "msopenh264", "mbedcrypto", "mbedtls", "mbedx509", "ortp"]
        )
    ]
)
