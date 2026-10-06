// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "MouseLinkCore", products: [.library(name: "MouseLinkCore", targets: ["MouseLinkCore"])], targets: [.target(name: "MouseLinkCore"), .testTarget(name: "MouseLinkCoreTests", dependencies: ["MouseLinkCore"])])
