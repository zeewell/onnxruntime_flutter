import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:onnxruntime/src/bindings/bindings.dart';
import 'package:onnxruntime/src/bindings/onnxruntime_bindings_generated.dart'
    as bg;
import 'package:onnxruntime/src/ort_env.dart';
import 'package:onnxruntime/src/ort_isolate_session.dart';
import 'package:onnxruntime/src/ort_status.dart';
import 'package:onnxruntime/src/ort_value.dart';
import 'package:onnxruntime/src/ort_provider.dart';
import 'package:onnxruntime/src/providers/ort_flags.dart';

class OrtSession {
  ffi.Pointer<bg.OrtSession> _ptr = ffi.nullptr;
  late int _inputCount;
  late List<String> _inputNames;
  late int _outputCount;
  late List<String> _outputNames;
  OrtIsolateSession? _isolateSession;
  Future<void>? _releasing;

  /// Maximum unfinished asynchronous runs, including worker startup and the
  /// active run. Null preserves unlimited submission. Excess runs are rejected
  /// before their pointers are sent to the worker; accepted runs are drained.
  final int? maxPendingRuns;

  int get address {
    _ensureOpen();
    return _ptr.address;
  }
  int get inputCount => _inputCount;
  List<String> get inputNames => _inputNames;
  int get outputCount => _outputCount;
  List<String> get outputNames => _outputNames;

  /// Creates a session from a file.
  OrtSession.fromFile(File modelFile, OrtSessionOptions options,
      {this.maxPendingRuns}) {
    _validatePendingLimit();
    using((arena) {
      final pp = arena<ffi.Pointer<bg.OrtSession>>();
      final path = Platform.isWindows
          ? modelFile.path.toNativeUtf16(allocator: arena).cast<ffi.Char>()
          : modelFile.path.toNativeUtf8(allocator: arena).cast<ffi.Char>();
      var initialized = false;
      try {
        final status = OrtEnv.instance.ortApiPtr.ref.CreateSession.asFunction<
            bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtEnv>,
                ffi.Pointer<ffi.Char>, ffi.Pointer<bg.OrtSessionOptions>,
                ffi.Pointer<ffi.Pointer<bg.OrtSession>>)>()(
            OrtEnv.instance.ptr, path, options._ptr, pp);
        OrtStatus.checkOrtStatus(status);
        _ptr = pp.value;
        _init();
        initialized = true;
      } finally {
        if (!initialized && pp.value != ffi.nullptr) {
          OrtEnv.instance.ortApiPtr.ref.ReleaseSession
              .asFunction<void Function(ffi.Pointer<bg.OrtSession>)>()(pp.value);
          _ptr = ffi.nullptr;
        }
      }
    });
  }

  /// Creates a session from buffer.
  OrtSession.fromBuffer(Uint8List modelBuffer, OrtSessionOptions options,
      {this.maxPendingRuns}) {
    _validatePendingLimit();
    using((arena) {
      final pp = arena<ffi.Pointer<bg.OrtSession>>();
      final size = modelBuffer.length;
      final bufferPtr = arena<ffi.Uint8>(size);
      bufferPtr.asTypedList(size).setRange(0, size, modelBuffer);
      var initialized = false;
      try {
        final status = OrtEnv.instance.ortApiPtr.ref.CreateSessionFromArray
            .asFunction<bg.OrtStatusPtr Function(
                ffi.Pointer<bg.OrtEnv>, ffi.Pointer<ffi.Void>, int,
                ffi.Pointer<bg.OrtSessionOptions>,
                ffi.Pointer<ffi.Pointer<bg.OrtSession>>)>()(
            OrtEnv.instance.ptr, bufferPtr.cast(), size, options._ptr, pp);
        OrtStatus.checkOrtStatus(status);
        _ptr = pp.value;
        _init();
        initialized = true;
      } finally {
        if (!initialized && pp.value != ffi.nullptr) {
          OrtEnv.instance.ortApiPtr.ref.ReleaseSession
              .asFunction<void Function(ffi.Pointer<bg.OrtSession>)>()(pp.value);
          _ptr = ffi.nullptr;
        }
      }
    });
  }

  /// Creates a session from a pointer's address.
  OrtSession.fromAddress(int address) : maxPendingRuns = null {
    _ptr = ffi.Pointer.fromAddress(address);
    _ensureOpen();
    _init();
  }

  void _validatePendingLimit() {
    if (maxPendingRuns != null && maxPendingRuns! < 1) {
      throw ArgumentError.value(maxPendingRuns, 'maxPendingRuns',
          'Must be positive or null');
    }
  }

  void _ensureOpen() {
    if (_releasing != null || _ptr == ffi.nullptr) {
      throw StateError('ONNX session released');
    }
  }

  void _init() {
    _inputCount = _getCount(input: true);
    _inputNames = _getNames(_inputCount, input: true);
    _outputCount = _getCount(input: false);
    _outputNames = _getNames(_outputCount, input: false);
  }

  int _getCount({required bool input}) {
    return using((arena) {
      final count = arena<ffi.Size>();
      final getCount = input
          ? OrtEnv.instance.ortApiPtr.ref.SessionGetInputCount
          : OrtEnv.instance.ortApiPtr.ref.SessionGetOutputCount;
      final status = getCount.asFunction<bg.OrtStatusPtr Function(
          ffi.Pointer<bg.OrtSession>, ffi.Pointer<ffi.Size>)>()(_ptr, count);
      OrtStatus.checkOrtStatus(status);
      return count.value;
    });
  }

  List<String> _getNames(int count, {required bool input}) {
    final getName = input
        ? OrtEnv.instance.ortApiPtr.ref.SessionGetInputName
        : OrtEnv.instance.ortApiPtr.ref.SessionGetOutputName;
    return List<String>.generate(count, (index) {
      return using((arena) {
        final name = arena<ffi.Pointer<ffi.Char>>();
        try {
          final status = getName.asFunction<bg.OrtStatusPtr Function(
              ffi.Pointer<bg.OrtSession>, int, ffi.Pointer<bg.OrtAllocator>,
              ffi.Pointer<ffi.Pointer<ffi.Char>>)>()(
              _ptr, index, OrtAllocator.instance.ptr, name);
          OrtStatus.checkOrtStatus(status);
          return name.value.cast<Utf8>().toDartString();
        } finally {
          OrtAllocator.instance.free(name.value.cast());
        }
      });
    });
  }

  /// Performs inference synchronously.
  List<OrtValue?> run(OrtRunOptions runOptions, Map<String, OrtValue> inputs,
      [List<String>? outputNames]) {
    _ensureOpen();
    return using((arena) {
      final inputLength = inputs.length;
      final names = outputNames ?? _outputNames;
      final inputNamePtrs = arena<ffi.Pointer<ffi.Char>>(inputLength);
      final inputPtrs = arena<ffi.Pointer<bg.OrtValue>>(inputLength);
      final outputNamePtrs = arena<ffi.Pointer<ffi.Char>>(names.length);
      final outputPtrs = arena<ffi.Pointer<bg.OrtValue>>(names.length);
      var index = 0;
      for (final entry in inputs.entries) {
        inputNamePtrs[index] = entry.key.toNativeUtf8(allocator: arena).cast();
        inputPtrs[index++] = entry.value.ptr;
      }
      for (var i = 0; i < names.length; i++) {
        outputNamePtrs[i] = names[i].toNativeUtf8(allocator: arena).cast();
      }
      var transferred = false;
      try {
        final status = OrtEnv.instance.ortApiPtr.ref.Run.asFunction<
            bg.OrtStatusPtr Function(
                ffi.Pointer<bg.OrtSession>,
                ffi.Pointer<bg.OrtRunOptions>,
                ffi.Pointer<ffi.Pointer<ffi.Char>>,
                ffi.Pointer<ffi.Pointer<bg.OrtValue>>,
                int,
                ffi.Pointer<ffi.Pointer<ffi.Char>>,
                int,
                ffi.Pointer<ffi.Pointer<bg.OrtValue>>)>()(
            _ptr, runOptions._ptr, inputNamePtrs, inputPtrs, inputLength,
            outputNamePtrs, names.length, outputPtrs);
        OrtStatus.checkOrtStatus(status);
        final outputs = <OrtValue?>[];
        final typePtr = arena<ffi.Int32>();
        for (var i = 0; i < names.length; i++) {
          final ptr = outputPtrs[i];
          if (ptr == ffi.nullptr) {
            outputs.add(null);
            continue;
          }
          final status = OrtEnv.instance.ortApiPtr.ref.GetValueType.asFunction<
              bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtValue>,
                  ffi.Pointer<ffi.Int32>)>()(ptr, typePtr);
          OrtStatus.checkOrtStatus(status);
          final value = OrtValue.fromAddress(
              ptr.address, ONNXType.valueOf(typePtr.value));
          if (value == null) {
            OrtValue.releaseAddress(ptr.address);
            outputPtrs[i] = ffi.nullptr;
          }
          outputs.add(value);
        }
        transferred = true;
        return outputs;
      } finally {
        if (!transferred) {
          // Run may fail after allocating a subset of the outputs.
          for (var i = 0; i < names.length; i++) {
            if (outputPtrs[i] != ffi.nullptr) {
              OrtValue.releaseAddress(outputPtrs[i].address);
            }
          }
        }
      }
    });
  }

  /// Performs inference asynchronously.
  Future<List<OrtValue?>>? runAsync(
      OrtRunOptions runOptions, Map<String, OrtValue> inputs,
      [List<String>? outputNames]) {
    _ensureOpen();
    _isolateSession ??= OrtIsolateSession(this, maxPendingRuns: maxPendingRuns);
    return _isolateSession?.run(runOptions, inputs, outputNames);
  }

  /// Reads a custom model metadata value. A missing key throws ArgumentError.
  String getMetadatas(String key) {
    _ensureOpen();
    return using((arena) {
      final meta = arena<ffi.Pointer<bg.OrtModelMetadata>>();
      final value = arena<ffi.Pointer<ffi.Char>>();
      try {
        var status = OrtEnv.instance.ortApiPtr.ref.SessionGetModelMetadata
            .asFunction<bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtSession>,
                ffi.Pointer<ffi.Pointer<bg.OrtModelMetadata>>)>()(_ptr, meta);
        OrtStatus.checkOrtStatus(status);
        status = OrtEnv.instance.ortApiPtr.ref.ModelMetadataLookupCustomMetadataMap
            .asFunction<bg.OrtStatusPtr Function(
                ffi.Pointer<bg.OrtModelMetadata>, ffi.Pointer<bg.OrtAllocator>,
                ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Pointer<ffi.Char>>)>()(
            meta.value, OrtAllocator.instance.ptr,
            key.toNativeUtf8(allocator: arena).cast(), value);
        OrtStatus.checkOrtStatus(status);
        if (value.value == ffi.nullptr) {
          throw ArgumentError.value(key, 'key', 'Model metadata key not found');
        }
        return value.value.cast<Utf8>().toDartString();
      } finally {
        try {
          if (value.value != ffi.nullptr) {
            OrtAllocator.instance.free(value.value.cast());
          }
        } finally {
          if (meta.value != ffi.nullptr) {
            OrtEnv.instance.ortApiPtr.ref.ReleaseModelMetadata.asFunction<
                void Function(ffi.Pointer<bg.OrtModelMetadata>)>()(meta.value);
          }
        }
      }
    });
  }

  /// Waits for pending inference before releasing the native session.
  Future<void> release() => _releasing ??= _release();

  Future<void> _release() async {
    await _isolateSession?.release();
    _isolateSession = null;
    OrtEnv.instance.ortApiPtr.ref.ReleaseSession
        .asFunction<void Function(ffi.Pointer<bg.OrtSession>)>()(_ptr);
    _ptr = ffi.nullptr;
  }
}

class OrtSessionOptions {
  late ffi.Pointer<bg.OrtSessionOptions> _ptr;
  int _intraOpNumThreads = 0;

  OrtSessionOptions() {
    _create();
  }

  void _create() {
    using((arena) {
      final pp = arena<ffi.Pointer<bg.OrtSessionOptions>>();
      try {
        final status = OrtEnv.instance.ortApiPtr.ref.CreateSessionOptions
            .asFunction<bg.OrtStatusPtr Function(
                ffi.Pointer<ffi.Pointer<bg.OrtSessionOptions>>)>()(pp);
        OrtStatus.checkOrtStatus(status);
        _ptr = pp.value;
      } catch (_) {
        if (pp.value != ffi.nullptr) {
          OrtEnv.instance.ortApiPtr.ref.ReleaseSessionOptions
              .asFunction<void Function(ffi.Pointer<bg.OrtSessionOptions>)>()(pp.value);
        }
        rethrow;
      }
    });
  }

  void release() {
    OrtEnv.instance.ortApiPtr.ref.ReleaseSessionOptions
        .asFunction<void Function(ffi.Pointer<bg.OrtSessionOptions>)>()(_ptr);
  }

  /// Sets the number of intra op threads.
  void setIntraOpNumThreads(int numThreads) {
    _intraOpNumThreads = numThreads;
    final statusPtr = OrtEnv.instance.ortApiPtr.ref.SetIntraOpNumThreads
        .asFunction<
            bg.OrtStatusPtr Function(
                ffi.Pointer<bg.OrtSessionOptions>, int)>()(_ptr, numThreads);
    OrtStatus.checkOrtStatus(statusPtr);
  }

  /// Sets the number of inter op threads.
  void setInterOpNumThreads(int numThreads) {
    final statusPtr = OrtEnv.instance.ortApiPtr.ref.SetInterOpNumThreads
        .asFunction<
            bg.OrtStatusPtr Function(
                ffi.Pointer<bg.OrtSessionOptions>, int)>()(_ptr, numThreads);
    OrtStatus.checkOrtStatus(statusPtr);
  }

  /// Uses the environment's shared thread pools for sessions created with
  /// these options. First initialize OrtEnv with OrtThreadingOptions.
  /// This does not change the default per-session threading policy.
  void disablePerSessionThreads() {
    final status = OrtEnv.instance.ortApiPtr.ref.DisablePerSessionThreads
        .asFunction<bg.OrtStatusPtr Function(
            ffi.Pointer<bg.OrtSessionOptions>)>()(_ptr);
    OrtStatus.checkOrtStatus(status);
  }

  /// Sets the level of session graph optimization.
  void setSessionGraphOptimizationLevel(GraphOptimizationLevel level) {
    final statusPtr = OrtEnv
        .instance.ortApiPtr.ref.SetSessionGraphOptimizationLevel
        .asFunction<
            bg.OrtStatusPtr Function(
                ffi.Pointer<bg.OrtSessionOptions>, int)>()(_ptr, level.value);
    OrtStatus.checkOrtStatus(statusPtr);
  }

  bool _appendExecutionProvider(OrtProvider provider, OrtFlags flags) {
    var result = false;
    bg.OrtStatusPtr? statusPtr;
    switch (provider) {
      case OrtProvider.cpu:
        statusPtr =
            onnxRuntimeBinding.OrtSessionOptionsAppendExecutionProvider_CPU(
                _ptr, flags.value);
        result = true;
        break;
      case OrtProvider.coreml:
        statusPtr =
            onnxRuntimeBinding.OrtSessionOptionsAppendExecutionProvider_CoreML(
                _ptr, flags.value);
        result = true;
        break;
      case OrtProvider.nnapi:
        statusPtr =
            onnxRuntimeBinding.OrtSessionOptionsAppendExecutionProvider_Nnapi(
                _ptr, flags.value);
        result = true;
        break;
      default:
        break;
    }
    OrtStatus.checkOrtStatus(statusPtr);
    return result;
  }

  bool _appendExecutionProvider2(
      OrtProvider provider, Map<String, String> providerOptions) {
    var providerName = '';
    switch (provider) {
      case OrtProvider.xnnpack:
        providerName = 'XNNPACK';
        break;
      default:
        return false;
    }
    return using((arena) {
      final providerNamePtr =
          providerName.toNativeUtf8(allocator: arena).cast<ffi.Char>();
      final size = providerOptions.length;
      final keys = arena<ffi.Pointer<ffi.Char>>(size);
      final values = arena<ffi.Pointer<ffi.Char>>(size);
      var i = 0;
      for (final entry in providerOptions.entries) {
        keys[i] = entry.key.toNativeUtf8(allocator: arena).cast();
        values[i] = entry.value.toNativeUtf8(allocator: arena).cast();
        ++i;
      }
      final status = OrtEnv.instance.ortApiPtr.ref.SessionOptionsAppendExecutionProvider
          .asFunction<bg.OrtStatusPtr Function(
              ffi.Pointer<bg.OrtSessionOptions>, ffi.Pointer<ffi.Char>,
              ffi.Pointer<ffi.Pointer<ffi.Char>>,
              ffi.Pointer<ffi.Pointer<ffi.Char>>, int)>()(
          _ptr, providerNamePtr, keys, values, size);
      OrtStatus.checkOrtStatus(status);
      return true;
    });
  }

  /// Appends cpu provider.
  bool appendCPUProvider(CPUFlags flags) {
    return _appendExecutionProvider(OrtProvider.cpu, flags);
  }

  /// Appends CoreML provider.
  bool appendCoreMLProvider(CoreMLFlags flags) {
    return _appendExecutionProvider(OrtProvider.coreml, flags);
  }

  /// Appends Nnapi provider.
  bool appendNnapiProvider(NnapiFlags flags) {
    return _appendExecutionProvider(OrtProvider.nnapi, flags);
  }

  /// Appends QNN provider.
  bool appendQnnProvider() {
    return _appendExecutionProvider2(OrtProvider.qnn, {});
  }

  /// Appends Xnnpack provider.
  bool appendXnnpackProvider() {
    return _appendExecutionProvider2(OrtProvider.xnnpack,
        {'intra_op_num_threads': _intraOpNumThreads.toString()});
  }
}

class OrtRunOptions {
  late ffi.Pointer<bg.OrtRunOptions> _ptr;

  int get address => _ptr.address;

  OrtRunOptions() {
    _create();
  }

  OrtRunOptions.fromAddress(int address) {
    _ptr = ffi.Pointer.fromAddress(address);
  }

  void _create() {
    using((arena) {
      final pp = arena<ffi.Pointer<bg.OrtRunOptions>>();
      try {
        final status = OrtEnv.instance.ortApiPtr.ref.CreateRunOptions
            .asFunction<bg.OrtStatusPtr Function(
                ffi.Pointer<ffi.Pointer<bg.OrtRunOptions>>)>()(pp);
        OrtStatus.checkOrtStatus(status);
        _ptr = pp.value;
      } catch (_) {
        if (pp.value != ffi.nullptr) {
          OrtEnv.instance.ortApiPtr.ref.ReleaseRunOptions
              .asFunction<void Function(ffi.Pointer<bg.OrtRunOptions>)>()(pp.value);
        }
        rethrow;
      }
    });
  }

  void release() {
    OrtEnv.instance.ortApiPtr.ref.ReleaseRunOptions
        .asFunction<void Function(ffi.Pointer<bg.OrtRunOptions> input)>()(_ptr);
  }

  void setRunLogVerbosityLevel(int level) {
    final statusPtr = OrtEnv
        .instance.ortApiPtr.ref.RunOptionsSetRunLogVerbosityLevel
        .asFunction<
            bg.OrtStatusPtr Function(
                ffi.Pointer<bg.OrtRunOptions>, int)>()(_ptr, level);
    OrtStatus.checkOrtStatus(statusPtr);
  }

  int getRunLogVerbosityLevel() {
    return using((arena) {
      final level = arena<ffi.Int>();
      final status = OrtEnv.instance.ortApiPtr.ref.RunOptionsGetRunLogVerbosityLevel
          .asFunction<bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtRunOptions>,
              ffi.Pointer<ffi.Int>)>()(_ptr, level);
      OrtStatus.checkOrtStatus(status);
      return level.value;
    });
  }

  void setRunLogSeverityLevel(int level) {
    final statusPtr = OrtEnv
        .instance.ortApiPtr.ref.RunOptionsSetRunLogSeverityLevel
        .asFunction<
            bg.OrtStatusPtr Function(
                ffi.Pointer<bg.OrtRunOptions>, int)>()(_ptr, level);
    OrtStatus.checkOrtStatus(statusPtr);
  }

  int getRunLogSeverityLevel() {
    return using((arena) {
      final level = arena<ffi.Int>();
      final status = OrtEnv.instance.ortApiPtr.ref.RunOptionsGetRunLogSeverityLevel
          .asFunction<bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtRunOptions>,
              ffi.Pointer<ffi.Int>)>()(_ptr, level);
      OrtStatus.checkOrtStatus(status);
      return level.value;
    });
  }

  void setRunTag(String tag) {
    using((arena) {
      final status = OrtEnv.instance.ortApiPtr.ref.RunOptionsSetRunTag
          .asFunction<bg.OrtStatusPtr Function(
              ffi.Pointer<bg.OrtRunOptions>, ffi.Pointer<ffi.Char>)>()(
          _ptr, tag.toNativeUtf8(allocator: arena).cast());
      OrtStatus.checkOrtStatus(status);
    });
  }

  String getRunTag() {
    return using((arena) {
      final tag = arena<ffi.Pointer<ffi.Char>>();
      final status = OrtEnv.instance.ortApiPtr.ref.RunOptionsGetRunTag
          .asFunction<bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtRunOptions>,
              ffi.Pointer<ffi.Pointer<ffi.Char>>)>()(_ptr, tag);
      OrtStatus.checkOrtStatus(status);
      // The native string is borrowed from RunOptions.
      return tag.value.cast<Utf8>().toDartString();
    });
  }

  void setTerminate() {
    final statusPtr = OrtEnv.instance.ortApiPtr.ref.RunOptionsSetTerminate
        .asFunction<
            bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtRunOptions>)>()(_ptr);
    OrtStatus.checkOrtStatus(statusPtr);
  }

  void unsetTerminate() {
    final statusPtr = OrtEnv.instance.ortApiPtr.ref.RunOptionsUnsetTerminate
        .asFunction<
            bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtRunOptions>)>()(_ptr);
    OrtStatus.checkOrtStatus(statusPtr);
  }
}

enum GraphOptimizationLevel {
  ortDisableAll(bg.GraphOptimizationLevel.ORT_DISABLE_ALL),
  ortEnableBasic(bg.GraphOptimizationLevel.ORT_ENABLE_BASIC),
  ortEnableExtended(bg.GraphOptimizationLevel.ORT_ENABLE_EXTENDED),
  ortEnableAll(bg.GraphOptimizationLevel.ORT_ENABLE_ALL);

  final int value;

  const GraphOptimizationLevel(this.value);
}
