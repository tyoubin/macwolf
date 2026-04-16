// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "macwolf",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "macwolf", targets: ["macwolf"])
    ],
    targets: [
        .executableTarget(
            name: "macwolf",
            path: ".",
            exclude: [
                ".git",
                "Tests",
                "README.md",
                "LICENSE",
                "Info.plist",
                ".gitignore"
            ],
            sources: [
                "main.swift",
                "Interface.swift",
                "InterfacePersistence.swift",
                "WakeOnLanSender.swift",
                "ShortcutMapper.swift",
                "InterfaceTableViewController.swift",
                "SettingsWindow.swift",
                "MacWolfApp.swift"
            ]
        ),
        .testTarget(
            name: "macwolfTests",
            dependencies: ["macwolf"],
            path: "Tests/macwolfTests"
        )
    ]
)
