import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:onnxruntime/src/bindings/onnxruntime_bindings_generated.dart'
    as bg;
import 'package:onnxruntime/src/ort_env.dart';
import 'package:onnxruntime/src/ort_status.dart';
import 'package:onnxruntime/src/util/list_shape_extension.dart';

abstract class OrtValue {
  static OrtValue? fromAddress(int address, ONNXType type) {
    final ptr = ffi.Pointer<bg.OrtValue>.fromAddress(address);
    switch (type) {
      case ONNXType.tensor: return OrtValueTensor(ptr);
      case ONNXType.sequence: return OrtValueSequence(ptr);
      case ONNXType.map: return OrtValueMap(ptr);
      case ONNXType.sparseTensor: return OrtValueSparseTensor(ptr);
      default: return null;
    }
  }

  static void releaseAddress(int address) {
    OrtEnv.instance.ortApiPtr.ref.ReleaseValue.asFunction<
        void Function(ffi.Pointer<bg.OrtValue>)>()(
        ffi.Pointer<bg.OrtValue>.fromAddress(address));
  }

  late ffi.Pointer<bg.OrtValue> _ptr;

  ffi.Pointer<bg.OrtValue> get ptr {
    if (_ptr == ffi.nullptr) throw StateError('OrtValue has been released.');
    return _ptr;
  }

  int get address => ptr.address;

  Object? get value;

  Map<OrtTensorTypeAndShapeInfo, OrtTensorTypeAndShapeInfo> _createMapInfo(
      ffi.Pointer<bg.OrtValue> ortValuePtr) {
    OrtTensorTypeAndShapeInfo read(int index) {
      return using((arena) {
        final output = arena<ffi.Pointer<bg.OrtValue>>();
        try {
          final value = _getOrtValue(ortValuePtr, index, output);
          return OrtTensorTypeAndShapeInfo(value);
        } finally {
          if (output.value != ffi.nullptr) _releaseOrtValue(output.value);
        }
      });
    }
    return {read(0): read(1)};
  }

  ffi.Pointer<bg.OrtValue> _getOrtValue(ffi.Pointer<bg.OrtValue> ortValuePtr,
      int index, ffi.Pointer<ffi.Pointer<bg.OrtValue>> indexOrtValuePtrPtr) {
    final statusPtr = OrtEnv.instance.ortApiPtr.ref.GetValue.asFunction<
            bg.OrtStatusPtr Function(
                ffi.Pointer<bg.OrtValue>,
                int,
                ffi.Pointer<bg.OrtAllocator>,
                ffi.Pointer<ffi.Pointer<bg.OrtValue>>)>()(
        ortValuePtr, index, OrtAllocator.instance.ptr, indexOrtValuePtrPtr);
    OrtStatus.checkOrtStatus(statusPtr);
    return indexOrtValuePtrPtr.value;
  }

  ffi.Pointer<T> _getTensorMutableData<T extends ffi.NativeType>(
      ffi.Pointer<bg.OrtValue> ortValuePtr,
      ffi.Pointer<ffi.Pointer<T>> dataPtrPtr) {
    final statusPtr = OrtEnv.instance.ortApiPtr.ref.GetTensorMutableData
            .asFunction<
                bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtValue>,
                    ffi.Pointer<ffi.Pointer<ffi.Void>>)>()(
        ortValuePtr, dataPtrPtr.cast());
    OrtStatus.checkOrtStatus(statusPtr);
    return dataPtrPtr.value;
  }

  List<String> _getStringList(ffi.Pointer<bg.OrtValue> ortValuePtr,
      [OrtTensorTypeAndShapeInfo? info]) {
    final count = (info ?? OrtTensorTypeAndShapeInfo(ortValuePtr))
        ._tensorShapeElementCount;
    return using((arena) {
      final lengthPtr = arena<ffi.Size>();
      OrtStatus.checkOrtStatus(OrtEnv.instance.ortApiPtr.ref
          .GetStringTensorDataLength.asFunction<bg.OrtStatusPtr Function(
              ffi.Pointer<bg.OrtValue>, ffi.Pointer<ffi.Size>)>()(
          ortValuePtr, lengthPtr));
      final length = lengthPtr.value;
      final data = arena<ffi.Uint8>(length + 1);
      final offsets = arena<ffi.Size>(count + 1);
      OrtStatus.checkOrtStatus(OrtEnv.instance.ortApiPtr.ref
          .GetStringTensorContent.asFunction<bg.OrtStatusPtr Function(
              ffi.Pointer<bg.OrtValue>, ffi.Pointer<ffi.Void>, int,
              ffi.Pointer<ffi.Size>, int)>()(
          ortValuePtr, data.cast(), length, offsets, count));
      offsets[count] = length;
      return List<String>.generate(count, (i) =>
          (data + offsets[i]).cast<Utf8>().toDartString(
              length: offsets[i + 1] - offsets[i]));
    });
  }

  // Native views stay inside synchronous reads; public flat reads copy them.
  List<num> _getNumList(ffi.Pointer<bg.OrtValue> ortValuePtr,
      [OrtTensorTypeAndShapeInfo? info]) {
    final metadata = info ?? OrtTensorTypeAndShapeInfo(ortValuePtr);
    final count = metadata._tensorShapeElementCount;
    return using((arena) {
      final pp = arena<ffi.Pointer<ffi.Void>>();
      final data = _getTensorMutableData(ortValuePtr, pp);
      switch (metadata._tensorElementType) {
        case ONNXTensorElementDataType.uint8:
          return data.cast<ffi.Uint8>().asTypedList(count);
        case ONNXTensorElementDataType.int8:
          return data.cast<ffi.Int8>().asTypedList(count);
        case ONNXTensorElementDataType.uint16:
          return data.cast<ffi.Uint16>().asTypedList(count);
        case ONNXTensorElementDataType.int16:
          return data.cast<ffi.Int16>().asTypedList(count);
        case ONNXTensorElementDataType.uint32:
          return data.cast<ffi.Uint32>().asTypedList(count);
        case ONNXTensorElementDataType.int32:
          return data.cast<ffi.Int32>().asTypedList(count);
        case ONNXTensorElementDataType.uint64:
          return data.cast<ffi.Uint64>().asTypedList(count);
        case ONNXTensorElementDataType.int64:
          return data.cast<ffi.Int64>().asTypedList(count);
        case ONNXTensorElementDataType.float:
          return data.cast<ffi.Float>().asTypedList(count);
        case ONNXTensorElementDataType.double:
          return data.cast<ffi.Double>().asTypedList(count);
        default:
          throw UnsupportedError('Tensor type is not numeric.');
      }
    });
  }

  List<bool> _getBoolList(ffi.Pointer<bg.OrtValue> ortValuePtr,
      [OrtTensorTypeAndShapeInfo? info]) {
    final count = (info ?? OrtTensorTypeAndShapeInfo(ortValuePtr))
        ._tensorShapeElementCount;
    return using((arena) {
      final pp = arena<ffi.Pointer<ffi.Bool>>();
      final data = _getTensorMutableData(ortValuePtr, pp);
      return List<bool>.generate(count, (i) => data[i]);
    });
  }

  void _releaseOrtValue(ffi.Pointer<bg.OrtValue> ortValuePtr) {
    OrtEnv.instance.ortApiPtr.ref.ReleaseValue
        .asFunction<void Function(ffi.Pointer<bg.OrtValue>)>()(ortValuePtr);
  }

  void release() {
    if (_ptr == ffi.nullptr) return;
    _releaseOrtValue(_ptr);
    _ptr = ffi.nullptr;
  }
}

class OrtValueTensor extends OrtValue {
  OrtTensorTypeAndShapeInfo? _cachedInfo;

  OrtTensorTypeAndShapeInfo get _info {
    final valuePtr = ptr;
    return _cachedInfo ??= OrtTensorTypeAndShapeInfo(valuePtr);
  }
  ffi.Pointer<ffi.Void> _dataPtr = ffi.nullptr;

  OrtValueTensor(ffi.Pointer<bg.OrtValue> ptr,
      [ffi.Pointer<ffi.Void>? dataPtr]) {
    _ptr = ptr;
    if (dataPtr != null) {
      _dataPtr = dataPtr;
    }
  }

  factory OrtValueTensor.fromAddress(int address) {
    return OrtValueTensor(ffi.Pointer.fromAddress(address));
  }

  static OrtValueTensor _createTensorWithString(String data) {
    return _createTensorWithStringList(<String>[data], []);
  }

  static OrtValueTensor _createTensorWithStringList(List<String> data,
      [List<int>? shape]) {
    shape ??= data.shape;
    _validateShape(shape, data.length);
    return using((arena) {
      final output = arena<ffi.Pointer<bg.OrtValue>>();
      final dimensions = arena<ffi.Int64>(shape!.isEmpty ? 1 : shape.length);
      dimensions.asTypedList(shape.length).setAll(0, shape);
      var transferred = false;
      try {
        OrtStatus.checkOrtStatus(OrtEnv.instance.ortApiPtr.ref
            .CreateTensorAsOrtValue.asFunction<bg.OrtStatusPtr Function(
                ffi.Pointer<bg.OrtAllocator>, ffi.Pointer<ffi.Int64>, int,
                int, ffi.Pointer<ffi.Pointer<bg.OrtValue>>)>()(
            OrtAllocator.instance.ptr, dimensions, shape.length,
            ONNXTensorElementDataType.string.value, output));
        for (var i = 0; i < data.length; i++) {
          final string = data[i].toNativeUtf8();
          try {
            OrtStatus.checkOrtStatus(OrtEnv.instance.ortApiPtr.ref
                .FillStringTensorElement.asFunction<bg.OrtStatusPtr Function(
                    ffi.Pointer<bg.OrtValue>, ffi.Pointer<ffi.Char>, int)>()(
                output.value, string.cast(), i));
          } finally {
            malloc.free(string);
          }
        }
        final tensor = OrtValueTensor(output.value);
        transferred = true;
        return tensor;
      } finally {
        if (!transferred && output.value != ffi.nullptr) {
          OrtValue.releaseAddress(output.value.address);
        }
      }
    });
  }

  static void _validateShape(List<int> shape, int count) {
    var size = BigInt.one;
    for (final dimension in shape) {
      if (dimension < 0) {
        throw ArgumentError.value(shape, 'shape',
            'Dimensions must be non-negative.');
      }
      size *= BigInt.from(dimension);
    }
    if (size != BigInt.from(count)) {
      throw ArgumentError('Shape $shape does not match $count elements.');
    }
  }

  static OrtValueTensor createTensorWithData(dynamic data) {
    if (data is int) {
      return createTensorWithDataList(<int>[data], []);
    }
    if (data is double) {
      return createTensorWithDataList(<double>[data], []);
    }
    if (data is bool) {
      return createTensorWithDataList(<bool>[data], []);
    }
    if (data is String) {
      return _createTensorWithString(data);
    }
    throw Exception('Invalid element type');
  }

  static OrtValueTensor createTensorWithDataList(List data,
      [List<int>? shape]) {
    shape ??= data.shape;
    final element = data.element();
    final List flat = data.isByteBuffer() ? data : data.flatten<dynamic>();
    _validateShape(shape, flat.length);
    if (element is String) {
      return _createTensorWithStringList(flat.cast<String>(), shape);
    }
    var dataType = ONNXTensorElementDataType.undefined;
    var byteWidth = 0;
    if (element is Uint8List) {
      dataType = ONNXTensorElementDataType.uint8;
      byteWidth = 1;
    } else if (element is Int8List) {
      dataType = ONNXTensorElementDataType.int8;
      byteWidth = 1;
    } else if (element is Uint16List) {
      dataType = ONNXTensorElementDataType.uint16;
      byteWidth = 2;
    } else if (element is Int16List) {
      dataType = ONNXTensorElementDataType.int16;
      byteWidth = 2;
    } else if (element is Uint32List) {
      dataType = ONNXTensorElementDataType.uint32;
      byteWidth = 4;
    } else if (element is Int32List) {
      dataType = ONNXTensorElementDataType.int32;
      byteWidth = 4;
    } else if (element is Uint64List) {
      dataType = ONNXTensorElementDataType.uint64;
      byteWidth = 8;
    } else if (element is Int64List || element is int) {
      dataType = ONNXTensorElementDataType.int64;
      byteWidth = 8;
    } else if (element is Float32List) {
      dataType = ONNXTensorElementDataType.float;
      byteWidth = 4;
    } else if (element is Float64List || element is double) {
      dataType = ONNXTensorElementDataType.double;
      byteWidth = 8;
    } else if (element is bool) {
      dataType = ONNXTensorElementDataType.bool;
      byteWidth = 1;
    } else {
      throw ArgumentError('Invalid inputTensor element type.');
    }
    final byteCount = flat.length * byteWidth;
    final dataPtr = calloc<ffi.Uint8>(byteCount == 0 ? 1 : byteCount).cast<ffi.Void>();
    var transferred = false;
    try {
      switch (dataType) {
        case ONNXTensorElementDataType.uint8:
          dataPtr.cast<ffi.Uint8>().asTypedList(flat.length)
              .setAll(0, flat is List<int> ? flat : flat.cast<int>());
          break;
        case ONNXTensorElementDataType.int8:
          dataPtr.cast<ffi.Int8>().asTypedList(flat.length)
              .setAll(0, flat is List<int> ? flat : flat.cast<int>());
          break;
        case ONNXTensorElementDataType.uint16:
          dataPtr.cast<ffi.Uint16>().asTypedList(flat.length)
              .setAll(0, flat is List<int> ? flat : flat.cast<int>());
          break;
        case ONNXTensorElementDataType.int16:
          dataPtr.cast<ffi.Int16>().asTypedList(flat.length)
              .setAll(0, flat is List<int> ? flat : flat.cast<int>());
          break;
        case ONNXTensorElementDataType.uint32:
          dataPtr.cast<ffi.Uint32>().asTypedList(flat.length)
              .setAll(0, flat is List<int> ? flat : flat.cast<int>());
          break;
        case ONNXTensorElementDataType.int32:
          dataPtr.cast<ffi.Int32>().asTypedList(flat.length)
              .setAll(0, flat is List<int> ? flat : flat.cast<int>());
          break;
        case ONNXTensorElementDataType.uint64:
          dataPtr.cast<ffi.Uint64>().asTypedList(flat.length)
              .setAll(0, flat is List<int> ? flat : flat.cast<int>());
          break;
        case ONNXTensorElementDataType.int64:
          dataPtr.cast<ffi.Int64>().asTypedList(flat.length)
              .setAll(0, flat is List<int> ? flat : flat.cast<int>());
          break;
        case ONNXTensorElementDataType.float:
          dataPtr.cast<ffi.Float>().asTypedList(flat.length)
              .setAll(0, flat is List<double> ? flat : flat.cast<double>());
          break;
        case ONNXTensorElementDataType.double:
          dataPtr.cast<ffi.Double>().asTypedList(flat.length)
              .setAll(0, flat is List<double> ? flat : flat.cast<double>());
          break;
        case ONNXTensorElementDataType.bool:
          final boolData = dataPtr.cast<ffi.Bool>();
          for (var i = 0; i < flat.length; i++) {
            boolData[i] = flat[i] as bool;
          }
          break;
        default:
          throw UnsupportedError('Unsupported tensor element type.');
      }
      return using((arena) {
        final dimensions = arena<ffi.Int64>(shape!.isEmpty ? 1 : shape.length);
        dimensions.asTypedList(shape.length).setAll(0, shape);
        final memory = arena<ffi.Pointer<bg.OrtMemoryInfo>>();
        final output = arena<ffi.Pointer<bg.OrtValue>>();
        try {
          OrtStatus.checkOrtStatus(OrtEnv.instance.ortApiPtr.ref
              .AllocatorGetInfo.asFunction<bg.OrtStatusPtr Function(
                  ffi.Pointer<bg.OrtAllocator>,
                  ffi.Pointer<ffi.Pointer<bg.OrtMemoryInfo>>)>()(
              OrtAllocator.instance.ptr, memory));
          OrtStatus.checkOrtStatus(OrtEnv.instance.ortApiPtr.ref
              .CreateTensorWithDataAsOrtValue.asFunction<bg.OrtStatusPtr Function(
                  ffi.Pointer<bg.OrtMemoryInfo>, ffi.Pointer<ffi.Void>, int,
                  ffi.Pointer<ffi.Int64>, int, int,
                  ffi.Pointer<ffi.Pointer<bg.OrtValue>>)>()(
              memory.value, dataPtr, byteCount, dimensions, shape.length,
              dataType.value, output));
          final tensor = OrtValueTensor(output.value, dataPtr);
          transferred = true;
          return tensor;
        } finally {
          if (!transferred && output.value != ffi.nullptr) {
            OrtValue.releaseAddress(output.value.address);
          }
        }
      });
    } finally {
      if (!transferred) calloc.free(dataPtr);
    }
  }

  /// Returns a flat, owned copy of the numeric tensor data.
  ///
  /// The returned typed list remains valid after [release]. Shape is not
  /// applied here; [value] retains its scalar or nested-list representation.
  /// Boolean, string, and other unsupported tensor types throw [UnsupportedError].
  TypedData toTypedList() {
    final info = _info;
    switch (info._tensorElementType) {
      case ONNXTensorElementDataType.uint8:
        return Uint8List.fromList(_getNumList(ptr, info) as List<int>);
      case ONNXTensorElementDataType.int8:
        return Int8List.fromList(_getNumList(ptr, info) as List<int>);
      case ONNXTensorElementDataType.uint16:
        return Uint16List.fromList(_getNumList(ptr, info) as List<int>);
      case ONNXTensorElementDataType.int16:
        return Int16List.fromList(_getNumList(ptr, info) as List<int>);
      case ONNXTensorElementDataType.uint32:
        return Uint32List.fromList(_getNumList(ptr, info) as List<int>);
      case ONNXTensorElementDataType.int32:
        return Int32List.fromList(_getNumList(ptr, info) as List<int>);
      case ONNXTensorElementDataType.uint64:
        return Uint64List.fromList(_getNumList(ptr, info) as List<int>);
      case ONNXTensorElementDataType.int64:
        return Int64List.fromList(_getNumList(ptr, info) as List<int>);
      case ONNXTensorElementDataType.float:
        return Float32List.fromList(_getNumList(ptr, info) as List<double>);
      case ONNXTensorElementDataType.double:
        return Float64List.fromList(_getNumList(ptr, info) as List<double>);
      default:
        throw UnsupportedError('Tensor type ${info._tensorElementType} '
            'does not support toTypedList().');
    }
  }

  @override
  dynamic get value {
    if (_info._dimensionsCount == 0) {
      // scalar tensor
      switch (_info._tensorElementType) {
        case ONNXTensorElementDataType.uint8:
        case ONNXTensorElementDataType.int8:
        case ONNXTensorElementDataType.uint16:
        case ONNXTensorElementDataType.int16:
        case ONNXTensorElementDataType.uint32:
        case ONNXTensorElementDataType.int32:
        case ONNXTensorElementDataType.uint64:
        case ONNXTensorElementDataType.int64:
        case ONNXTensorElementDataType.float:
        case ONNXTensorElementDataType.double:
          return _getNumList(ptr, _info)[0];
        case ONNXTensorElementDataType.bool:
          return _getBoolList(ptr, _info)[0];
        case ONNXTensorElementDataType.string:
          return _getStringList(ptr, _info)[0];
        default:
          throw Exception('Extracting the value of an invalid Tensor.');
      }
    } else {
      // vector tensor
      switch (_info._tensorElementType) {
        case ONNXTensorElementDataType.uint8:
        case ONNXTensorElementDataType.int8:
        case ONNXTensorElementDataType.uint16:
        case ONNXTensorElementDataType.int16:
        case ONNXTensorElementDataType.uint32:
        case ONNXTensorElementDataType.int32:
        case ONNXTensorElementDataType.uint64:
        case ONNXTensorElementDataType.int64:
          return _getNumList(ptr, _info).reshape<int>(_info._tensorShape);
        case ONNXTensorElementDataType.float:
        case ONNXTensorElementDataType.double:
          return _getNumList(ptr, _info).reshape<double>(_info._tensorShape);
        case ONNXTensorElementDataType.bool:
          return _getBoolList(ptr, _info).reshape<bool>(_info._tensorShape);
        case ONNXTensorElementDataType.string:
          return _getStringList(ptr, _info).reshape<String>(_info._tensorShape);
        default:
          throw Exception('Extracting the value of an invalid Tensor.');
      }
    }
  }

  @override
  void release() {
    super.release();
    if (_dataPtr == ffi.nullptr) {
      return;
    }
    calloc.free(_dataPtr);
    _dataPtr = ffi.nullptr;
  }
}

class OrtValueSequence extends OrtValue {
  OrtValueSequence(ffi.Pointer<bg.OrtValue> ptr) {
    _ptr = ptr;
  }

  OrtValueSequence.fromAddress(int address)
      : this(ffi.Pointer.fromAddress(address));

  @override
  List<OrtValue> get value {
    final valuePtr = ptr;
    final values = <OrtValue>[];
    try {
      return using((arena) {
        final count = arena<ffi.Size>();
        OrtStatus.checkOrtStatus(OrtEnv.instance.ortApiPtr.ref.GetValueCount
            .asFunction<bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtValue>,
                ffi.Pointer<ffi.Size>)>()(valuePtr, count));
        final output = arena<ffi.Pointer<bg.OrtValue>>();
        final type = arena<ffi.Int32>();
        for (var i = 0; i < count.value; i++) {
          output.value = ffi.nullptr;
          var transferred = false;
          try {
            final item = _getOrtValue(valuePtr, i, output);
            OrtStatus.checkOrtStatus(OrtEnv.instance.ortApiPtr.ref.GetValueType
                .asFunction<bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtValue>,
                    ffi.Pointer<ffi.Int32>)>()(item, type));
            final wrapped = OrtValue.fromAddress(item.address,
                ONNXType.valueOf(type.value));
            if (wrapped == null) {
              throw UnsupportedError('Unsupported sequence element type.');
            }
            values.add(wrapped);
            transferred = true;
          } finally {
            if (!transferred && output.value != ffi.nullptr) {
              _releaseOrtValue(output.value);
            }
          }
        }
        // Preserve the concrete list types returned for homogeneous sequences.
        if (values.isNotEmpty && values.every((value) => value is OrtValueTensor)) {
          return values.cast<OrtValueTensor>();
        }
        if (values.isNotEmpty && values.every((value) => value is OrtValueMap)) {
          return values.cast<OrtValueMap>();
        }
        return values;
      });
    } catch (_) {
      for (final value in values) {
        value.release();
      }
      rethrow;
    }
  }
}

class OrtValueMap extends OrtValue {
  Map<OrtTensorTypeAndShapeInfo, OrtTensorTypeAndShapeInfo>? _mapInfo;

  Map<OrtTensorTypeAndShapeInfo, OrtTensorTypeAndShapeInfo> get _info {
    final valuePtr = ptr;
    return _mapInfo ??= _createMapInfo(valuePtr);
  }

  OrtTensorTypeAndShapeInfo get _keyInfo => _info.keys.first;
  OrtTensorTypeAndShapeInfo get _valueInfo => _info.values.first;

  OrtValueMap(ffi.Pointer<bg.OrtValue> ptr) {
    _ptr = ptr;
  }

  OrtValueMap.fromAddress(int address) {
    _ptr = ffi.Pointer.fromAddress(address);
  }

  @override
  Map get value {
    final keys = _getMapKeys();
    final values = _getMapValues();
    final map = {};
    for (int i = 0; i < keys.length; ++i) {
      map[keys[i]] = values[i];
    }
    return map;
  }

  List<dynamic> _getMapKeys() {
    switch (_keyInfo._tensorElementType) {
      case ONNXTensorElementDataType.string:
        return _getStringListWithIndex(0);
      case ONNXTensorElementDataType.int64:
        return _getNumListWithIndex(0);
      default:
        throw Exception(
            'Invalid or unknown valueType: ${_keyInfo._tensorElementType}');
    }
  }

  List<String> _getStringListWithIndex(int index) {
    return _readMapList(index, (value) => _getStringList(value));
  }

  List<num> _getNumListWithIndex(int index) {
    return _readMapList(index, (value) => List<num>.of(_getNumList(value)));
  }

  List<T> _readMapList<T>(int index,
      List<T> Function(ffi.Pointer<bg.OrtValue>) read) {
    final valuePtr = ptr;
    return using((arena) {
      final output = arena<ffi.Pointer<bg.OrtValue>>();
      try {
        return read(_getOrtValue(valuePtr, index, output));
      } finally {
        if (output.value != ffi.nullptr) _releaseOrtValue(output.value);
      }
    });
  }

  List<Object> _getMapValues() {
    switch (_valueInfo._tensorElementType) {
      case ONNXTensorElementDataType.string:
        return _getStringListWithIndex(1);
      case ONNXTensorElementDataType.int64:
      case ONNXTensorElementDataType.float:
      case ONNXTensorElementDataType.double:
        return _getNumListWithIndex(1);
      default:
        throw Exception(
            'Invalid or unknown valueType: ${_keyInfo._tensorElementType}');
    }
  }

  int get size => _keyInfo._tensorShapeElementCount;
}

class OrtValueSparseTensor extends OrtValue {
  OrtSparseFormat? _format;

  OrtValueSparseTensor(ffi.Pointer<bg.OrtValue> ptr) {
    _ptr = ptr;
  }

  OrtValueSparseTensor.fromAddress(int address)
      : this(ffi.Pointer.fromAddress(address));

  @override
  Object? get value {
    final valuePtr = ptr;
    _format ??= using((arena) {
      final format = arena<ffi.Int32>();
      OrtStatus.checkOrtStatus(OrtEnv.instance.ortApiPtr.ref.GetSparseTensorFormat
          .asFunction<bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtValue>,
              ffi.Pointer<ffi.Int32>)>()(valuePtr, format));
      return OrtSparseFormat.valueOf(format.value);
    });
    if (_format == OrtSparseFormat.undefined) {
      throw Exception('Undefined sparsity type in this sparse tensor.');
    }
    // Sparse tensor extraction is not implemented.
    return null;
  }
}

class OrtTensorTypeAndShapeInfo {
  int _dimensionsCount = 0;
  int _tensorShapeElementCount = 0;
  ONNXTensorElementDataType _tensorElementType =
      ONNXTensorElementDataType.undefined;
  List<int> _tensorShape = [];

  OrtTensorTypeAndShapeInfo(ffi.Pointer<bg.OrtValue> ortValuePtr) {
    using((arena) {
      final pp = arena<ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>>();
      try {
        final status = OrtEnv.instance.ortApiPtr.ref.GetTensorTypeAndShape
            .asFunction<bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtValue>,
                ffi.Pointer<ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>>)>()(
            ortValuePtr, pp);
        OrtStatus.checkOrtStatus(status);
        _tensorElementType = _getTensorElementType(pp.value);
        _dimensionsCount = _getDimensionsCount(pp.value);
        _tensorShape = _getDimensions(pp.value, _dimensionsCount);
        _tensorShapeElementCount = _getTensorShapeElementCount(pp.value);
      } finally {
        if (pp.value != ffi.nullptr) _releaseTensorTypeAndShapeInfo(pp.value);
      }
    });
  }

  static ONNXTensorElementDataType _getTensorElementType(
      ffi.Pointer<bg.OrtTensorTypeAndShapeInfo> infoPtr) {
    return using((arena) {
      final onnxTensorElementDataTypePtr = arena<ffi.Int32>();
      final statusPtr = OrtEnv.instance.ortApiPtr.ref.GetTensorElementType
              .asFunction<
                  bg.OrtStatusPtr Function(
                      ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>,
                      ffi.Pointer<ffi.Int32>)>()(
          infoPtr, onnxTensorElementDataTypePtr);
      OrtStatus.checkOrtStatus(statusPtr);
      final onnxTensorElementDataType = onnxTensorElementDataTypePtr.value;
      return ONNXTensorElementDataType.valueOf(onnxTensorElementDataType);
    });
  }

  static void _releaseTensorTypeAndShapeInfo(
      ffi.Pointer<bg.OrtTensorTypeAndShapeInfo> infoPtr) {
    OrtEnv.instance.ortApiPtr.ref.ReleaseTensorTypeAndShapeInfo.asFunction<
        void Function(ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>)>()(infoPtr);
  }

  static int _getDimensionsCount(
      ffi.Pointer<bg.OrtTensorTypeAndShapeInfo> infoPtr) {
    return using((arena) {
      final countPtr = arena<ffi.Size>();
      final statusPtr = OrtEnv.instance.ortApiPtr.ref.GetDimensionsCount
          .asFunction<
              bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>,
                  ffi.Pointer<ffi.Size>)>()(infoPtr, countPtr);
      OrtStatus.checkOrtStatus(statusPtr);
      final count = countPtr.value;
      return count;
    });
  }

  static List<int> _getDimensions(
      ffi.Pointer<bg.OrtTensorTypeAndShapeInfo> infoPtr, int length) {
    return using((arena) {
      final dimensionsPtr = arena<ffi.Int64>(length);
      final statusPtr = OrtEnv.instance.ortApiPtr.ref.GetDimensions.asFunction<
          bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>,
              ffi.Pointer<ffi.Int64>, int)>()(infoPtr, dimensionsPtr, length);
      OrtStatus.checkOrtStatus(statusPtr);
      final dimensions =
          List<int>.generate(length, (index) => dimensionsPtr[index]);
      return dimensions;
    });
  }

  static int _getTensorShapeElementCount(
      ffi.Pointer<bg.OrtTensorTypeAndShapeInfo> infoPtr) {
    return using((arena) {
      final countPtr = arena<ffi.Size>();
      final statusPtr = OrtEnv.instance.ortApiPtr.ref.GetTensorShapeElementCount
          .asFunction<
              bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>,
                  ffi.Pointer<ffi.Size>)>()(infoPtr, countPtr);
      OrtStatus.checkOrtStatus(statusPtr);
      final count = countPtr.value;
      return count;
    });
  }
}

enum ONNXTensorElementDataType {
  undefined(
      bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_UNDEFINED),
  float(bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT),
  uint8(bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT8),
  int8(bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_INT8),
  uint16(bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT16),
  int16(bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_INT16),
  int32(bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32),
  int64(bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64),
  string(bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_STRING),
  bool(bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL),
  float16(bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT16),
  double(bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_DOUBLE),
  uint32(bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT32),
  uint64(bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT64),
  complex64(
      bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_COMPLEX64),
  complex128(
      bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_COMPLEX128),
  bFloat16(bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_BFLOAT16);

  final int value;

  const ONNXTensorElementDataType(this.value);

  static ONNXTensorElementDataType valueOf(int type) {
    switch (type) {
      case bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT:
        return ONNXTensorElementDataType.float;
      case bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT8:
        return ONNXTensorElementDataType.uint8;
      case bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_INT8:
        return ONNXTensorElementDataType.int8;
      case bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT16:
        return ONNXTensorElementDataType.uint16;
      case bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_INT16:
        return ONNXTensorElementDataType.int16;
      case bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32:
        return ONNXTensorElementDataType.int32;
      case bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64:
        return ONNXTensorElementDataType.int64;
      case bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_STRING:
        return ONNXTensorElementDataType.string;
      case bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL:
        return ONNXTensorElementDataType.bool;
      case bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT16:
        return ONNXTensorElementDataType.float16;
      case bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_DOUBLE:
        return ONNXTensorElementDataType.double;
      case bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT32:
        return ONNXTensorElementDataType.uint32;
      case bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT64:
        return ONNXTensorElementDataType.uint64;
      case bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_COMPLEX64:
        return ONNXTensorElementDataType.complex64;
      case bg
            .ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_COMPLEX128:
        return ONNXTensorElementDataType.complex128;
      case bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_BFLOAT16:
        return ONNXTensorElementDataType.bFloat16;
      default:
        return ONNXTensorElementDataType.undefined;
    }
  }
}

enum ONNXType {
  unknown(bg.ONNXType.ONNX_TYPE_UNKNOWN),
  tensor(bg.ONNXType.ONNX_TYPE_TENSOR),
  sequence(bg.ONNXType.ONNX_TYPE_SEQUENCE),
  map(bg.ONNXType.ONNX_TYPE_MAP),
  opaque(bg.ONNXType.ONNX_TYPE_OPAQUE),
  sparseTensor(bg.ONNXType.ONNX_TYPE_SPARSETENSOR),
  optional(bg.ONNXType.ONNX_TYPE_OPTIONAL);

  final int value;

  const ONNXType(this.value);

  static ONNXType valueOf(int type) {
    switch (type) {
      case bg.ONNXType.ONNX_TYPE_TENSOR:
        return ONNXType.tensor;
      case bg.ONNXType.ONNX_TYPE_SEQUENCE:
        return ONNXType.sequence;
      case bg.ONNXType.ONNX_TYPE_MAP:
        return ONNXType.map;
      case bg.ONNXType.ONNX_TYPE_OPAQUE:
        return ONNXType.opaque;
      case bg.ONNXType.ONNX_TYPE_SPARSETENSOR:
        return ONNXType.sparseTensor;
      case bg.ONNXType.ONNX_TYPE_OPTIONAL:
        return ONNXType.optional;
      default:
        return ONNXType.unknown;
    }
  }
}

enum OrtSparseFormat {
  undefined(bg.OrtSparseFormat.ORT_SPARSE_UNDEFINED),
  coo(bg.OrtSparseFormat.ORT_SPARSE_COO),
  csrc(bg.OrtSparseFormat.ORT_SPARSE_CSRC),
  blockSparse(bg.OrtSparseFormat.ORT_SPARSE_BLOCK_SPARSE);

  final int value;

  const OrtSparseFormat(this.value);

  static OrtSparseFormat valueOf(int type) {
    switch (type) {
      case bg.OrtSparseFormat.ORT_SPARSE_COO:
        return OrtSparseFormat.coo;
      case bg.OrtSparseFormat.ORT_SPARSE_CSRC:
        return OrtSparseFormat.csrc;
      case bg.OrtSparseFormat.ORT_SPARSE_BLOCK_SPARSE:
        return OrtSparseFormat.blockSparse;
      default:
        return OrtSparseFormat.undefined;
    }
  }
}
