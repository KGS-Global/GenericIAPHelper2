// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "GenericIAPHelper2",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "GenericIAPHelper2",
            targets: ["GenericIAPHelper2"]
        )
    ],
    targets: [
        .target(
            name: "GenericIAPHelper2",
            path: "GenericIAPHelper2",
            exclude: ["GenericIAPHelper2.h"]
        )
    ],
    swiftLanguageVersions: [.v5]
)

