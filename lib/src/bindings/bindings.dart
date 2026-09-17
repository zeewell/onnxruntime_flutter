import 'dart:ffi';
import 'dart:io';
import 'package:onnxruntime/src/bindings/onnxruntime_bindings_generated.dart';

final DynamicLibrary _dylib = () {
  if (Platform.isAndroid) {
    return DynamicLibrary.open('libonnxruntime.so');
  }

  if (Platform.isIOS || Platform.isMacOS) {
    // Apple platforms statically link ONNX Runtime through SwiftPM or CocoaPods.
    return DynamicLibrary.process();
  }

  if (Platform.isWindows) {
    return DynamicLibrary.open('onnxruntime.dll');
  }

  if (Platform.isLinux) {
    return DynamicLibrary.open('libonnxruntime.so.1.30.0');
  }

  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();

/// OnnxRuntime Bindings
final onnxRuntimeBinding = OnnxRuntimeBindings(_dylib);
