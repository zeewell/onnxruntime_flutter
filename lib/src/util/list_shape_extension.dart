import 'dart:typed_data';

extension ListShape on List {
  /// Reshape list to a another [shape]
  ///
  /// [T] is the type of elements in list
  ///
  /// Returns `List<dynamic>` if [shape.length] > 5
  /// else returns list with exact type
  ///
  /// Throws [ArgumentError] if number of elements for [shape]
  /// mismatch with current number of elements in list
  List reshape<T>(List<int> shape) {
    final dims = shape.length;
    final flat = _flatForReshape<T>();
    var count = BigInt.one;
    for (final dimension in shape) {
      if (dimension < 0) throw ArgumentError.value(shape, 'shape');
      count *= BigInt.from(dimension);
    }
    if (count != BigInt.from(flat.length)) {
      throw ArgumentError('Shape does not match the number of elements.');
    }
    switch (dims) {
      case 0:
      case 1:
        return List<T>.of(flat);
      case 2:
        return flat._reshape2<T>(shape);
      case 3:
        return flat._reshape3<T>(shape);
      case 4:
        return flat._reshape4<T>(shape);
      case 5:
        return flat._reshape5<T>(shape);
    }
    var offset = 0;
    List build(int dimension) {
      if (dimension == dims - 1) {
        return List<T>.generate(shape[dimension], (_) => flat[offset++]);
      }
      return List.generate(shape[dimension], (_) => build(dimension + 1));
    }
    return build(0);
  }

  List<T> _flatForReshape<T>() {
    if (this is List<T>) return this as List<T>;
    return flatten<T>();
  }

  List<List<T>> _reshape2<T>(List<int> shape) {
    var flatList = _flatForReshape<T>();
    List<List<T>> reshapedList = List.generate(
      shape[0],
      (i) => List.generate(
        shape[1],
        (j) => flatList[i * shape[1] + j],
      ),
    );

    return reshapedList;
  }

  List<List<List<T>>> _reshape3<T>(List<int> shape) {
    var flatList = _flatForReshape<T>();
    List<List<List<T>>> reshapedList = List.generate(
      shape[0],
      (i) => List.generate(
        shape[1],
        (j) => List.generate(
          shape[2],
          (k) => flatList[i * shape[1] * shape[2] + j * shape[2] + k],
        ),
      ),
    );

    return reshapedList;
  }

  List<List<List<List<T>>>> _reshape4<T>(List<int> shape) {
    var flatList = _flatForReshape<T>();

    List<List<List<List<T>>>> reshapedList = List.generate(
      shape[0],
      (i) => List.generate(
        shape[1],
        (j) => List.generate(
          shape[2],
          (k) => List.generate(
            shape[3],
            (l) => flatList[i * shape[1] * shape[2] * shape[3] +
                j * shape[2] * shape[3] +
                k * shape[3] +
                l],
          ),
        ),
      ),
    );

    return reshapedList;
  }

  List<List<List<List<List<T>>>>> _reshape5<T>(List<int> shape) {
    var flatList = _flatForReshape<T>();
    List<List<List<List<List<T>>>>> reshapedList = List.generate(
      shape[0],
      (i) => List.generate(
        shape[1],
        (j) => List.generate(
          shape[2],
          (k) => List.generate(
            shape[3],
            (l) => List.generate(
              shape[4],
              (m) => flatList[i * shape[1] * shape[2] * shape[3] * shape[4] +
                  j * shape[2] * shape[3] * shape[4] +
                  k * shape[3] * shape[4] +
                  l * shape[4] +
                  m],
            ),
          ),
        ),
      ),
    );

    return reshapedList;
  }

  /// Get shape of the list
  List<int> get shape {
    var list = this as dynamic;
    var shape = <int>[];
    while (list is List) {
      shape.add(list.length);
      if (list.isEmpty) break;
      list = list.elementAt(0);
    }
    return shape;
  }

  /// Flatten this list, [T] is element type
  /// if not specified `List<dynamic>` is returned
  List<T> flatten<T>() {
    final flat = <T>[];
    void append(List list) {
      for (final element in list) {
        if (element is List) {
          append(element);
        } else {
          flat.add(element as T);
        }
      }
    }
    append(this);
    return flat;
  }

  dynamic element() {
    var list = this as dynamic;
    while (list is List && !list.isByteBuffer()) {
      if (list.isEmpty) {
        if (list is List<int>) return 0;
        if (list is List<double>) return 0.0;
        if (list is List<bool>) return false;
        if (list is List<String>) return '';
        throw ArgumentError('Cannot infer the type of an empty list.');
      }
      list = list.elementAt(0);
    }
    return list;
  }

  bool isByteBuffer() {
    if (this is Uint8List) {
      return true;
    }
    if (this is Int8List) {
      return true;
    }
    if (this is Uint16List) {
      return true;
    }
    if (this is Int16List) {
      return true;
    }
    if (this is Uint32List) {
      return true;
    }
    if (this is Int32List) {
      return true;
    }
    if (this is Uint64List) {
      return true;
    }
    if (this is Int64List) {
      return true;
    }
    if (this is Float32List) {
      return true;
    }
    if (this is Float64List) {
      return true;
    }
    return false;
  }
}
