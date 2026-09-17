// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "onnxruntime",
    platforms: [
        .iOS("15.1"),
        .macOS("14.0")
    ],
    products: [
        .library(name: "onnxruntime", type: .static, targets: ["onnxruntime_ffi"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .binaryTarget(
            name: "onnxruntime",
            url: "https://download.onnxruntime.ai/pod-archive-onnxruntime-c-1.30.0.zip",
            checksum: "e6f1670c14406fd9f082bb400ab197a9b0a9646058ca6366e440642e2b54a2ea"
        ),
        .target(
            name: "onnxruntime_ffi",
            dependencies: [
                "onnxruntime",
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("Foundation"),
                .linkedFramework("Network"),
                .linkedFramework("Security"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("UIKit", .when(platforms: [.iOS])),
                .linkedFramework("IOKit", .when(platforms: [.macOS])),
                // Flutter consumes this package as a local path dependency.
                // Preserve the upstream weak CoreML link and the C entry points
                // looked up by Dart FFI, even when the host strips unused code.
                .unsafeFlags([
                    "-Xlinker", "-weak_framework", "-Xlinker", "CoreML",
                    "-Xlinker", "-u", "-Xlinker", "_OrtGetApiBase",
                    "-Xlinker", "-u", "-Xlinker", "_OrtSessionOptionsAppendExecutionProvider_CPU",
                    "-Xlinker", "-u", "-Xlinker", "_OrtSessionOptionsAppendExecutionProvider_CoreML"
                ])
            ]
        )
    ]
)
