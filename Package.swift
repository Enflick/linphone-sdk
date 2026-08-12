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
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.24-bb3104999/bctoolbox-ios.xcframework.zip",
            checksum: "e6e75519b71671841aa28a484fc98cf2da9ec0e209341ef65ff380c4baa080fd"
        ),
        .binaryTarget(
            name: "bctoolbox",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.24-bb3104999/bctoolbox.xcframework.zip",
            checksum: "3fdd6c9433f5c1a76dd0079e9ba181935514f6c1d19d812a3e323656d93648a3"
        ),
        .binaryTarget(
            name: "belcard",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.24-bb3104999/belcard.xcframework.zip",
            checksum: "d75c3a52ea556bf2f66adc46780f1b4da39a6329f4c14a340d0a4b4b07b5a39a"
        ),
        .binaryTarget(
            name: "belle-sip",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.24-bb3104999/belle-sip.xcframework.zip",
            checksum: "b1670fea45381b33d0f9ef82f503f15357d35a46b2d674276fb6f5d8b68af602"
        ),
        .binaryTarget(
            name: "belr",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.24-bb3104999/belr.xcframework.zip",
            checksum: "25771ad92e269a9431761322841501ed5bf73bddf9a201ca21cab035f01fa483"
        ),
        .binaryTarget(
            name: "lime",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.24-bb3104999/lime.xcframework.zip",
            checksum: "ddf99288a3e9863cda4971610383aaf346933dfcdab61f2bcf96628243f833dd"
        ),
        .binaryTarget(
            name: "linphone",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.24-bb3104999/linphone.xcframework.zip",
            checksum: "f26c777d7833243efb6a0b487759c8c449b89d73a3d71d83983707c617b8dacf"
        ),
        .binaryTarget(
            name: "mbedcrypto",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.24-bb3104999/mbedcrypto.xcframework.zip",
            checksum: "e3cd6d4d20fe1ca3621fe6b9995f9e6264cae5bb22ffffe7b90044d245f61110"
        ),
        .binaryTarget(
            name: "mbedtls",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.24-bb3104999/mbedtls.xcframework.zip",
            checksum: "c0760715e84a1aa3d4785c52b4dbc0c28d5db9c107ea3ffd234b19f9322783fc"
        ),
        .binaryTarget(
            name: "mbedx509",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.24-bb3104999/mbedx509.xcframework.zip",
            checksum: "7a49c31650f771b1f1b26484977296efd1dc9b9c779f374c56b0488409095fe8"
        ),
        .binaryTarget(
            name: "mediastreamer2",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.24-bb3104999/mediastreamer2.xcframework.zip",
            checksum: "1a8ecd934f178aa5b9cd156c9f965d7ff428ebc1377945a2302f0c8e111ff59c"
        ),
        .binaryTarget(
            name: "msamr",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.24-bb3104999/msamr.xcframework.zip",
            checksum: "4b6687a75ec593c455e5eb616fedbb0b315ad2bde124412f82f6dd18399d4e20"
        ),
        .binaryTarget(
            name: "mscodec2",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.24-bb3104999/mscodec2.xcframework.zip",
            checksum: "ddfa92ddc1f69f6b8ce2b12e8c680ba99edb0aed626745bfecf0f091f0f1cc8c"
        ),
        .binaryTarget(
            name: "msopenh264",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.24-bb3104999/msopenh264.xcframework.zip",
            checksum: "1fb81a4272214917d4ed618f4d5a8b4deb93f672796e7f955ae9835901e6d7cd"
        ),
        .binaryTarget(
            name: "ortp",
            url: "https://nexus.tools.textnow.io/repository/ios-release/LinphoneSDK/5.5.13-pre.24-bb3104999/ortp.xcframework.zip",
            checksum: "c19435493ec53956d34d70f0460d1fda7d494b30ba71ae27bda5d78066f33a21"
        ),
        .target(
            name: "linphonesw",
            dependencies: ["bctoolbox-ios", "bctoolbox", "belcard", "belle-sip", "belr", "lime", "linphone", "mbedcrypto", "mbedtls", "mbedx509", "mediastreamer2", "msamr", "mscodec2", "msopenh264", "ortp"]
        )
    ]
)
