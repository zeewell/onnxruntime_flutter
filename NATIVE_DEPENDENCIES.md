# Native dependencies

## ONNX Runtime 1.30.0

All platforms use the [official 1.30.0 release](https://github.com/microsoft/onnxruntime/releases/tag/v1.30.0).
The existing Dart bindings continue to request C API 14, which this runtime
supports. Updating the runtime does not expose every new C API through Dart.

| Platform | Source | Packaging |
| --- | --- | --- |
| Android | [Maven Central AAR](https://repo.maven.apache.org/maven2/com/microsoft/onnxruntime/onnxruntime-android/1.30.0/onnxruntime-android-1.30.0.aar) | Only `jni/arm64-v8a/libonnxruntime.so` and `jni/armeabi-v7a/libonnxruntime.so`; API 24+, 16 KB ELF alignment |
| iOS | `onnxruntime-objc` CocoaPod 1.30.0 | Official static XCFramework via `onnxruntime-c`; iOS 15.1+ |
| macOS | `onnxruntime-c` CocoaPod 1.30.0 | Official static XCFramework with ARM64 and x64 slices; macOS 14+ |
| Linux | `onnxruntime-linux-x64-1.30.0.tgz` release asset | `lib/libonnxruntime.so.1.30.0`; x64, glibc 2.28+ and compatible libstdc++ |
| Windows | `onnxruntime-win-x64-1.30.0.zip` release asset | `lib/onnxruntime.dll`; x64, Windows 10+ and Visual C++ runtime |

Android continues to package only the C runtime, without the AAR's Java/JNI
wrapper or manifest components. Desktop packages use the CPU distributions;
provider availability is determined by each official binary.

Apple loads symbols from `DynamicLibrary.process()`. The podspec linker flags
retain the C entry points used by Dart FFI, including in release builds. macOS no
longer bundles the old 1.15.1 dylib. After upgrading, application consumers must
raise their deployment targets and update their ONNX Runtime pods.

The standalone macOS ARM64 archive is used only for host regression testing;
applications use the universal CocoaPod. Upstream license and third-party notices
for redistributed binaries are included under `native_licenses/`.

### Archive SHA-256

GitHub release asset digests were verified before extracting the desktop binaries.
The Android download was additionally checked against Maven Central's SHA-1
sidecar. The SHA-256 values below identify the exact downloaded archives.

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
