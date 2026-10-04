// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "GitHubStar", platforms: [.macOS(.v14)], products: [.executable(name: "GitHubStar", targets: ["GitHubStar"])], targets: [.executableTarget(name: "GitHubStar")], swiftLanguageModes: [.v5])
