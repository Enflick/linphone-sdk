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
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.28-a69177bc6/bctoolbox-ios.xcframework.zip",
            checksum: "69536a4ac4ebe4963b327508cfed8aac351b0fc0ec578d05146288eec10ffa88"
        ),
        .binaryTarget(
            name: "bctoolbox",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.28-a69177bc6/bctoolbox.xcframework.zip",
            checksum: "d8be08bbf17ef155fcffb502439d35fa1b5db515eb134ca90ac6116dd75538ac"
        ),
        .binaryTarget(
            name: "belcard",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.28-a69177bc6/belcard.xcframework.zip",
            checksum: "29b5c42d442688c043bf328e64485cb917d20bf92401a1cae4ac983b29a96f68"
        ),
        .binaryTarget(
            name: "belle-sip",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.28-a69177bc6/belle-sip.xcframework.zip",
            checksum: "081d2280833e02fd6d7bfeca9ef8500a395d6fb15da822d62225c052ee10f3be"
        ),
        .binaryTarget(
            name: "belr",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.28-a69177bc6/belr.xcframework.zip",
            checksum: "83528a8f405a3fe894fbf735ea4cf205ffae4b32d2394d41a51729cbd1b77fde"
        ),
        .binaryTarget(
            name: "lime",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.28-a69177bc6/lime.xcframework.zip",
            checksum: "a2996e64032a177f8a15e46e2f7b0fc5223fe4536ad57a4b52de1d591af0e827"
        ),
        .binaryTarget(
            name: "linphone",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.28-a69177bc6/linphone.xcframework.zip",
            checksum: "c42f8716e7f537abe2e29eaa42703a959937636f27f73f75a197adb5e01327f4"
        ),
        .binaryTarget(
            name: "mbedcrypto",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.28-a69177bc6/mbedcrypto.xcframework.zip",
            checksum: "0bdcaa379b0b64208cf97971f46bcca75e9a7a7729ffd80eeb7bfe099cee8913"
        ),
        .binaryTarget(
            name: "mbedtls",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.28-a69177bc6/mbedtls.xcframework.zip",
            checksum: "fd632a82132901711e22a41437b0eb9618dd1483f232de02b5bda714c40fef19"
        ),
        .binaryTarget(
            name: "mbedx509",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.28-a69177bc6/mbedx509.xcframework.zip",
            checksum: "3d73ccf1793322f57108ddbcb65f7c4de9d0a0a1e30ea136a5e228d11a51d8ad"
        ),
        .binaryTarget(
            name: "mediastreamer2",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.28-a69177bc6/mediastreamer2.xcframework.zip",
            checksum: "abc38630f10113db92b5bebccbe1aa37c25e841d88bab5729621355277016296"
        ),
        .binaryTarget(
            name: "msamr",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.28-a69177bc6/msamr.xcframework.zip",
            checksum: "1bb3c6ac9abad558109f1d8acc52c8d895dc7c4b7010339f71839b051e68e595"
        ),
        .binaryTarget(
            name: "mscodec2",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.28-a69177bc6/mscodec2.xcframework.zip",
            checksum: "d796505801d4ea082a09f3b6950238e39f5ed494674580a427941d7ddc0b14e3"
        ),
        .binaryTarget(
            name: "msopenh264",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.28-a69177bc6/msopenh264.xcframework.zip",
            checksum: "de2e3261cc60b2e87723fbbdce63404220ce588795c8fcf0968e3e319056cf99"
        ),
        .binaryTarget(
            name: "ortp",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.28-a69177bc6/ortp.xcframework.zip",
            checksum: "c918b996b5a542f696eb782edee80ec0a5430fdb0abe6d45f31ddee28eb140f2"
        ),
        .target(
            name: "linphonesw",
            dependencies: ["bctoolbox-ios", "bctoolbox", "belcard", "belle-sip", "belr", "lime", "linphone", "mbedcrypto", "mbedtls", "mbedx509", "mediastreamer2", "msamr", "mscodec2", "msopenh264", "ortp"]
        )
    ]
)
