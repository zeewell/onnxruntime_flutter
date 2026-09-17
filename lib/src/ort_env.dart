import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'package:onnxruntime/src/bindings/bindings.dart';
import 'package:onnxruntime/src/bindings/onnxruntime_bindings_generated.dart'
    as bg;
import 'package:onnxruntime/src/ort_provider.dart';
import 'package:onnxruntime/src/ort_status.dart';

/// A class about onnx runtime environment.
class OrtEnv {
  static final OrtEnv _instance = OrtEnv._();

  static OrtEnv get instance => _instance;

  ffi.Pointer<bg.OrtEnv>? _ptr;

  late ffi.Pointer<bg.OrtApi> _ortApiPtr;

  static OrtApiVersion _apiVersion = OrtApiVersion.api14;

  OrtEnv._() {
    _ortApiPtr = onnxRuntimeBinding.OrtGetApiBase()
        .ref
        .GetApi
        .asFunction<ffi.Pointer<bg.OrtApi> Function(int)>()(_apiVersion.value);
  }

  /// Set ort's api version.
  static void setApiVersion(OrtApiVersion apiVersion) {
    _apiVersion = apiVersion;
  }

  /// Initialize the onnx runtime environment. Repeated calls are no-ops until
  /// release; configure global thread pools before creating any sessions.
  void init(
      {OrtLoggingLevel level = OrtLoggingLevel.warning,
      String logId = 'DartOnnxRuntime',
      OrtThreadingOptions? options}) {
    if (_ptr != null) return;
    using((arena) {
      final pp = arena<ffi.Pointer<bg.OrtEnv>>();
      final logIdPtr = logId.toNativeUtf8(allocator: arena).cast<ffi.Char>();
      var initialized = false;
      try {
        bg.OrtStatusPtr statusPtr;
        if (options == null) {
          statusPtr = _ortApiPtr.ref.CreateEnv.asFunction<
              bg.OrtStatusPtr Function(int, ffi.Pointer<ffi.Char>,
                  ffi.Pointer<ffi.Pointer<bg.OrtEnv>>)>()(
              level.value, logIdPtr, pp);
        } else {
          statusPtr = _ortApiPtr.ref.CreateEnvWithGlobalThreadPools.asFunction<
              bg.OrtStatusPtr Function(int, ffi.Pointer<ffi.Char>,
                  ffi.Pointer<bg.OrtThreadingOptions>,
                  ffi.Pointer<ffi.Pointer<bg.OrtEnv>>)>()(
              level.value, logIdPtr, options._ptr, pp);
        }
        OrtStatus.checkOrtStatus(statusPtr);
        _ptr = pp.value;
        _setLanguageProjection();
        initialized = true;
      } finally {
        if (!initialized) {
          if (pp.value != ffi.nullptr) {
            _ortApiPtr.ref.ReleaseEnv
                .asFunction<void Function(ffi.Pointer<bg.OrtEnv>)>()(pp.value);
          }
          _ptr = null;
        }
      }
    });
  }

  /// Release the onnx runtime environment.
  void release() {
    if (_ptr == null) {
      return;
    }
    _ortApiPtr.ref.ReleaseEnv
        .asFunction<void Function(ffi.Pointer<bg.OrtEnv>)>()(_ptr!);
    _ptr = null;
  }

  /// Gets the version of onnx runtime.
  static String get version => onnxRuntimeBinding.OrtGetApiBase()
      .ref
      .GetVersionString
      .asFunction<ffi.Pointer<ffi.Char> Function()>()()
      .cast<Utf8>()
      .toDartString();

  ffi.Pointer<bg.OrtApi> get ortApiPtr => _ortApiPtr;

  ffi.Pointer<bg.OrtEnv> get ptr {
    if (_ptr == null) {
      init();
    }
    return _ptr!;
  }

  /// Gets all available providers.
  List<OrtProvider> availableProviders() {
    return using((arena) {
      final providers = arena<ffi.Pointer<ffi.Pointer<ffi.Char>>>();
      final length = arena<ffi.Int>();
      try {
        final status = ortApiPtr.ref.GetAvailableProviders.asFunction<
            bg.OrtStatusPtr Function(
                ffi.Pointer<ffi.Pointer<ffi.Pointer<ffi.Char>>>,
                ffi.Pointer<ffi.Int>)>()(providers, length);
        OrtStatus.checkOrtStatus(status);
        return List<OrtProvider>.generate(length.value, (index) {
          final provider = providers.value[index].cast<Utf8>().toDartString();
          return OrtProvider.valueOf(provider);
        });
      } finally {
        if (providers.value != ffi.nullptr) {
          final status = ortApiPtr.ref.ReleaseAvailableProviders.asFunction<
              bg.OrtStatusPtr Function(ffi.Pointer<ffi.Pointer<ffi.Char>>,
                  int)>()(providers.value, length.value);
          OrtStatus.checkOrtStatus(status);
        }
      }
    });
  }

  void _setLanguageProjection() {
    if (_ptr == null) {
      init();
    }
    final status = _ortApiPtr.ref.SetLanguageProjection.asFunction<
            bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtEnv>, int)>()(
        _ptr!, bg.OrtLanguageProjection.ORT_PROJECTION_C);
    OrtStatus.checkOrtStatus(status);
  }
}

/// An enumerated value of api's version.
enum OrtApiVersion {
  /// The initial release of the ORT API.
  api1(1),

  /// Post 1.0 builds of the ORT API.
  api2(2),

  /// Post 1.3 builds of the ORT API.
  api3(3),

  /// Post 1.6 builds of the ORT API.
  api7(7),

  /// Post 1.7 builds of the ORT API.
  api8(8),

  /// Post 1.10 builds of the ORT API.
  api11(11),

  /// Post 1.12 builds of the ORT API.
  api13(13),

  /// Post 1.13 builds of the ORT API.
  api14(14),

  /// The initial release of the ORT training API.
  trainingApi1(1);

  final int value;

  const OrtApiVersion(this.value);
}

/// An enumerated value of log's level.
enum OrtLoggingLevel {
  verbose(bg.OrtLoggingLevel.ORT_LOGGING_LEVEL_VERBOSE),
  info(bg.OrtLoggingLevel.ORT_LOGGING_LEVEL_INFO),
  warning(bg.OrtLoggingLevel.ORT_LOGGING_LEVEL_WARNING),
  error(bg.OrtLoggingLevel.ORT_LOGGING_LEVEL_ERROR),
  fatal(bg.OrtLoggingLevel.ORT_LOGGING_LEVEL_FATAL);

  final int value;

  const OrtLoggingLevel(this.value);
}

/// A class obout thread's options.
class OrtThreadingOptions {
  late ffi.Pointer<bg.OrtThreadingOptions> _ptr;

  OrtThreadingOptions() {
    _create();
  }

  void _create() {
    using((arena) {
      final pp = arena<ffi.Pointer<bg.OrtThreadingOptions>>();
      try {
        final status = OrtEnv.instance.ortApiPtr.ref.CreateThreadingOptions
            .asFunction<bg.OrtStatusPtr Function(
                ffi.Pointer<ffi.Pointer<bg.OrtThreadingOptions>>)>()(pp);
        OrtStatus.checkOrtStatus(status);
        _ptr = pp.value;
      } catch (_) {
        if (pp.value != ffi.nullptr) {
          OrtEnv.instance.ortApiPtr.ref.ReleaseThreadingOptions.asFunction<
              void Function(ffi.Pointer<bg.OrtThreadingOptions>)>()(pp.value);
        }
        rethrow;
      }
    });
  }

  void release() {
    OrtEnv.instance.ortApiPtr.ref.ReleaseThreadingOptions
        .asFunction<void Function(ffi.Pointer<bg.OrtThreadingOptions>)>()(_ptr);
  }

  /// Sets the number of global intra op threads.
  void setGlobalIntraOpNumThreads(int numThreads) {
    final statusPtr = OrtEnv.instance.ortApiPtr.ref.SetGlobalIntraOpNumThreads
        .asFunction<
            bg.OrtStatusPtr Function(
                ffi.Pointer<bg.OrtThreadingOptions>, int)>()(_ptr, numThreads);
    OrtStatus.checkOrtStatus(statusPtr);
  }

  /// Sets the number of global inter op threads.
  void setGlobalInterOpNumThreads(int numThreads) {
    final statusPtr = OrtEnv.instance.ortApiPtr.ref.SetGlobalInterOpNumThreads
        .asFunction<
            bg.OrtStatusPtr Function(
                ffi.Pointer<bg.OrtThreadingOptions>, int)>()(_ptr, numThreads);
    OrtStatus.checkOrtStatus(statusPtr);
  }

  /// Sets the global spin control.
  void setGlobalSpinControl(bool allowSpinning) {
    final statusPtr = OrtEnv.instance.ortApiPtr.ref.SetGlobalSpinControl
        .asFunction<
            bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtThreadingOptions>,
                int)>()(_ptr, allowSpinning ? 1 : 0);
    OrtStatus.checkOrtStatus(statusPtr);
  }

  void setGlobalDenormalAsZero() {
    final statusPtr = OrtEnv.instance.ortApiPtr.ref.SetGlobalDenormalAsZero
        .asFunction<
            bg.OrtStatusPtr Function(
                ffi.Pointer<bg.OrtThreadingOptions>)>()(_ptr);
    OrtStatus.checkOrtStatus(statusPtr);
  }

  /// Sets the global intra op thread affinity.
  void setGlobalIntraOpThreadAffinity(String affinity) {
    using((arena) {
      final status = OrtEnv.instance.ortApiPtr.ref.SetGlobalIntraOpThreadAffinity
          .asFunction<bg.OrtStatusPtr Function(
              ffi.Pointer<bg.OrtThreadingOptions>, ffi.Pointer<ffi.Char>)>()(
          _ptr, affinity.toNativeUtf8(allocator: arena).cast());
      OrtStatus.checkOrtStatus(status);
    });
  }
}

class OrtAllocator {
  late ffi.Pointer<bg.OrtAllocator> _ptr;

  static final OrtAllocator _instance = OrtAllocator._();

  static OrtAllocator get instance => _instance;

  ffi.Pointer<bg.OrtAllocator> get ptr => _ptr;

  /// Frees memory allocated by this ONNX Runtime allocator.
  void free(ffi.Pointer<ffi.Void> pointer) {
    if (pointer == ffi.nullptr) return;
    final status = OrtEnv.instance.ortApiPtr.ref.AllocatorFree.asFunction<
        bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtAllocator>,
            ffi.Pointer<ffi.Void>)>()(_ptr, pointer);
    OrtStatus.checkOrtStatus(status);
  }

  OrtAllocator._() {
    using((arena) {
      final pp = arena<ffi.Pointer<bg.OrtAllocator>>();
      final status = OrtEnv.instance.ortApiPtr.ref.GetAllocatorWithDefaultOptions
          .asFunction<bg.OrtStatusPtr Function(
              ffi.Pointer<ffi.Pointer<bg.OrtAllocator>>)>()(pp);
      OrtStatus.checkOrtStatus(status);
      _ptr = pp.value;
    });
  }
}
