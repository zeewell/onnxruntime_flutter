<p align="center"><img width="50%" src="https://github.com/microsoft/onnxruntime/raw/main/docs/images/ONNX_Runtime_logo_dark.png" /></p>

# OnnxRuntime Plugin
[![pub package](https://img.shields.io/pub/v/onnxruntime.svg)](https://pub.dev/packages/onnxruntime)

This fork includes [inference lifecycle fixes](LIFECYCLE_PATCH.md). In particular,
await `OrtSession.release()` before releasing the environment.

## Overview

Flutter plugin for OnnxRuntime via `dart:ffi` provides an easy, flexible, and fast Dart API to integrate Onnx models in flutter apps across mobile and desktop platforms.

| **Platform**      | Android       | iOS | Linux | macOS | Windows |
|-------------------|---------------|-----|-------|-------|---------|
| **Compatibility** | API level 24+ | iOS 15.1+ | glibc 2.28+ | macOS 14+ | Windows 10+ |
| **Architecture**  | arm32/arm64   | arm64; arm64/x64 simulator | x64 | arm64/x64 | x64 |

Requires Flutter **3.47+** and Dart **3.13+**. The bundled native runtime is
ONNX Runtime **1.30.0**. The host must also meet
[Flutter's platform requirements](https://docs.flutter.dev/reference/supported-platforms).
See [native dependency details](NATIVE_DEPENDENCIES.md) for binary sources,
checksums, Apple linking, and Android build requirements.

### Apple host setup

iOS and macOS support both Swift Package Manager and CocoaPods. Both integrations
use ONNX Runtime **1.30.0** and retain the same deployment targets and Dart API.
Flutter uses the Swift package when SwiftPM is enabled, and the shared Darwin
podspec when SwiftPM is disabled. The example app uses SwiftPM by default.

CocoaPods applications can continue using their existing integration. Applications
moving to SwiftPM should follow [Flutter's migration guidance](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers).
Remove the application's CocoaPods integration only after all of its dependencies
support SwiftPM.

## Key Features

* Multi-platform Support for Android, iOS, Linux, macOS, Windows, and Web(Coming soon).
* Flexibility to use any Onnx Model.
* Acceleration using multi-threading.
* Similar structure as OnnxRuntime Java and C# API.
* Inference speed is not slower than native Android/iOS Apps built using the Java/Objective-C API.
* Run inference in different isolates to prevent jank in UI thread.

## Getting Started

In your flutter project add the dependency:

```yml
dependencies:
  ...
  onnxruntime: x.y.z
```

## Usage example

### Import

```dart
import 'package:onnxruntime/onnxruntime.dart';
```

### Initializing environment

```dart
OrtEnv.instance.init();
```

### Creating the Session

```dart
final sessionOptions = OrtSessionOptions();
const assetFileName = 'assets/models/test.onnx';
final rawAssetFile = await rootBundle.load(assetFileName);
final bytes = rawAssetFile.buffer.asUint8List();
final session = OrtSession.fromBuffer(bytes, sessionOptions!);
```

### Performing inference

```dart
final shape = [1, 2, 3];
final inputOrt = OrtValueTensor.createTensorWithDataList(data, shape);
final inputs = {'input': inputOrt};
final runOptions = OrtRunOptions();
final outputs = await _session?.runAsync(runOptions, inputs);
inputOrt.release();
runOptions.release();
outputs?.forEach((element) {
  element?.release();
});
```

### Large numeric tensors

Pass a flat `Float32List`, `Int64List`, or another supported numeric typed list
with an explicit shape to avoid flattening nested Dart lists. Input data is
copied into native memory owned by the tensor.

For large outputs, use `toTypedList()` to obtain a flat typed copy, without
constructing nested Dart lists:

```dart
final tensor = outputs.first as OrtValueTensor;
final pixels = tensor.toTypedList() as Float32List;
tensor.release();
// pixels owns its data and remains valid after tensor.release().
```

`toTypedList()` supports signed/unsigned 8-, 16-, 32-, and 64-bit integers,
Float32 and Float64. It throws `UnsupportedError` for other types, including
boolean and string tensors. The existing `.value` getter still returns scalar
or nested-list values. Both getters return data independent of the tensor;
read them before releasing it. Repeated reads produce new copies.

### Bounding asynchronous submissions

Each session's worker processes asynchronous runs sequentially. Set a limit
when creating the session to bound outstanding requests:

```dart
final session = OrtSession.fromBuffer(bytes, sessionOptions, maxPendingRuns: 1);
```

The limit includes worker startup, queued runs, and the active run. An excess
request fails with `StateError` before its pointers are sent to the worker;
accepted requests are never dropped. Omit the option to retain unlimited
submission. For camera/audio streams, also avoid producing an unbounded queue
before calling this API. Keep accepted inputs and run options alive until their
futures settle, and await `session.release()` before releasing the environment.

### Sharing CPU thread pools across sessions

Configure the environment before creating any sessions, then opt each session
into its shared pools:

```dart
final threading = OrtThreadingOptions()
  ..setGlobalIntraOpNumThreads(2)
  ..setGlobalInterOpNumThreads(1);
OrtEnv.instance.init(options: threading);
threading.release();
final sessionOptions = OrtSessionOptions()..disablePerSessionThreads();
```

Repeated environment initialization is a no-op until release. Session-local
thread pools remain the default; tune counts using the actual models and
devices. Release all sessions before releasing the environment.

### Releasing environment

```dart
OrtEnv.instance.release();
```
