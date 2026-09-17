# Native dependencies

## ONNX Runtime 1.30.0

All platforms use the [official 1.30.0 release](https://github.com/microsoft/onnxruntime/releases/tag/v1.30.0).
The existing Dart bindings continue to request C API 14, which this runtime
supports. Updating the runtime does not expose every new C API through Dart.

| Platform | Source | Packaging |
| --- | --- | --- |
| Android | [Maven Central AAR](https://repo.maven.apache.org/maven2/com/microsoft/onnxruntime/onnxruntime-android/1.30.0/onnxruntime-android-1.30.0.aar) | Only `jni/arm64-v8a/libonnxruntime.so` and `jni/armeabi-v7a/libonnxruntime.so`; API 24+, 16 KB ELF alignment |
| iOS | Local Swift package with the official `onnxruntime-c` binary target | Static XCFramework; iOS 15.1+, device arm64 and simulator arm64/x64 |
| macOS | Local Swift package with the official `onnxruntime-c` binary target | Static XCFramework; macOS 14+, ARM64 and x64 |
| Linux | `onnxruntime-linux-x64-1.30.0.tgz` release asset | `lib/libonnxruntime.so.1.30.0`; x64, glibc 2.28+ and compatible libstdc++ |
| Windows | `onnxruntime-win-x64-1.30.0.zip` release asset | `lib/onnxruntime.dll`; x64, Windows 10+ and Visual C++ runtime |

Android continues to package only the C runtime, without the AAR's Java/JNI
wrapper or manifest components. Desktop packages use the CPU distributions;
provider availability is determined by each official binary.

Apple uses the shared local package at `darwin/onnxruntime/Package.swift`. Its
binary target downloads the official
`https://download.onnxruntime.ai/pod-archive-onnxruntime-c-1.30.0.zip` archive and
links the C runtime statically. The package linker settings preserve the weak
CoreML link and the `OrtGetApiBase`,
`OrtSessionOptionsAppendExecutionProvider_CPU`, and
`OrtSessionOptionsAppendExecutionProvider_CoreML` entry points used by Dart FFI,
including in release builds. Dart continues to resolve them through
`DynamicLibrary.process()`. iOS no longer depends on `onnxruntime-objc`, and
macOS no longer bundles the old 1.15.1 dylib.

The linker flags use SwiftPM's `unsafeFlags` setting, supported by Flutter's
generated local path dependencies. The package also depends on the
Flutter-managed `FlutterFramework` package in the generated packages directory.

The standalone macOS ARM64 archive is used only for host regression testing;
applications use the universal XCFramework from the Swift package. Upstream
license and third-party notices for redistributed binaries are included under
`native_licenses/`.

### Apple host migration

The plugin declares both Apple platforms as FFI plugins with shared Darwin
sources, so Swift Package Manager support is required. CocoaPods-only iOS and
macOS hosts are no longer supported. Existing applications should
[enable Swift Package Manager and follow Flutter's migration guidance](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers),
then rebuild so Flutter can migrate the generated Apple project integration and
attach `FlutterGeneratedPluginSwiftPackage`.

Do not unconditionally remove CocoaPods from an application. The old plugin
podspecs and ONNX Runtime pods are no longer used, but the application may still
need its Podfile, Pods configuration, or workspace for other dependencies.

The example Xcode projects navigate directly to the shared `Package.swift`.
`FlutterGeneratedPluginSwiftPackage` owns the dependency; adding a second local
package override can conflict with Flutter's generated package identity when
the checkout directory name differs from the Dart package name.

### Archive SHA-256

GitHub release asset digests were verified before extracting the desktop binaries.
The Android download was additionally checked against Maven Central's SHA-1
sidecar. The Apple binary-target archive was downloaded in full and verified
against its Swift package checksum. The SHA-256 values below identify the exact
downloaded archives.

| Archive | SHA-256 |
| --- | --- |
| `onnxruntime-android-1.30.0.aar` | `e7fb945e402205f6db858d65bb78d2bdb0812317b383976c9e3bceb4862c73f1` |
| `onnxruntime-linux-x64-1.30.0.tgz` | `a5ed5a3cac51fbb2e90da632ae43d19212faaa20e76484e62bcb7c23ddb3b3fd` |
| `onnxruntime-win-x64-1.30.0.zip` | `c6ba983baf5681af108599675d2a89c2d145512d02de28aed0bff177cd0ba949` |
| `onnxruntime-osx-arm64-1.30.0.tgz` | `6ebb5062a934537c352937821f9fe9718e7de1a2db1122a93dd363ffd53a7012` |
| `pod-archive-onnxruntime-c-1.30.0.zip` | `e6f1670c14406fd9f082bb400ab197a9b0a9646058ca6366e440642e2b54a2ea` |

## Android build tools

This upgrade requires Flutter 3.47+ and Dart 3.13+.
The plugin and example use Android Gradle Plugin 9.4.0; the example wrapper uses
Gradle 9.7.1. The plugin compiles against Android API 36 and requires API 24+ at
runtime. The example uses AGP's built-in Kotlin support with Kotlin 2.4.0
declared in plugin management, and Java 17 source compatibility. Use a
Gradle-compatible JDK 17 or newer (verified with JDK 21).
Flutter 3.47 requires `android.newDsl=false` for this AGP integration.
See Flutter's [built-in Kotlin migration guide](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers).
