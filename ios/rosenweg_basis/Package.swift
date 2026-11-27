// swift-tools-version: 5.9
// SPDX-License-Identifier: GPL-3.0-or-later
// iOS-Teil von rosenweg_basis (Swift Package Manager; CocoaPods: ../rosenweg_basis.podspec).
import PackageDescription

let package = Package(
  name: "rosenweg_basis",
  platforms: [.iOS("13.0")],
  products: [.library(name: "rosenweg-basis", targets: ["rosenweg_basis"])],
  dependencies: [],
  targets: [.target(name: "rosenweg_basis", dependencies: [])]
)
