## Unreleased

* **Breaking:** iOS and macOS integration now requires Flutter's Swift Package
  Manager support; CocoaPods-only Apple hosts are no longer supported.
* Links the official ONNX Runtime 1.30.0 C XCFramework statically through a
  shared Darwin Swift package. The supported Apple deployment targets,
  architectures, and Dart API remain unchanged.

## 1.4.1

* Fixes a memory leak when creating tensor.

## 1.4.0

* Fixes a memory leak when creating tensor.

## 1.3.0

* Attempts to support macOS, Windows and Linux.

## 1.2.0

* Compatible with Gradle8.

## 1.1.0

* Exposes some methods of input and output name.
* Adds some documentation comments.

## 1.0.0

* Initial release.
