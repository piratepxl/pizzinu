// swift-tools-version: 6.0
//
//  Pizzinu — post-it digitali per macOS
//  Package SwiftPM (app nativa + libreria di dominio + runner di self-test).
//
//  NOTA SULL'AMBIENTE
//  Il SDK macOS 27 introduce `@State` come macro esterna il cui plugin
//  (SwiftUIMacros) è distribuito soltanto con Xcode. Su una macchina con i soli
//  Command Line Tools la compilazione di SwiftUI fallirebbe. `build.sh` rileva
//  la condizione e ripiega sul più recente SDK precedente disponibile
//  (es. MacOSX26.5.sdk), dove `@State` è ancora un normale property wrapper.
//
import PackageDescription

let strictConcurrency: [SwiftSetting] = [
    .swiftLanguageMode(.v6)
]

let package = Package(
    name: "Pizzinu",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PizzinuKit", targets: ["PizzinuKit"]),
        .executable(name: "Pizzinu", targets: ["Pizzinu"]),
        .executable(name: "PizzinuSelfTest", targets: ["PizzinuSelfTest"]),
    ],
    targets: [
        .target(
            name: "PizzinuKit",
            path: "Sources/PizzinuKit",
            swiftSettings: strictConcurrency
        ),
        .executableTarget(
            name: "Pizzinu",
            dependencies: ["PizzinuKit"],
            path: "Sources/Pizzinu",
            swiftSettings: strictConcurrency
        ),
        .executableTarget(
            name: "PizzinuSelfTest",
            dependencies: ["PizzinuKit"],
            path: "Sources/PizzinuSelfTest",
            swiftSettings: strictConcurrency
        ),
    ]
)
