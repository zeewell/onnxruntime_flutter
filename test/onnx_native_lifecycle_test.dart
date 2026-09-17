import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:onnxruntime/onnxruntime.dart';

// Opt-in: host must have the unchanged ONNX Runtime 1.15.1 native library on
// its loader path. The normal isolate/lane tests do not require native binaries.
void main() {
  test('native termination reports an error and repeated next requests succeed', () async {
    OrtEnv.instance.init();
    final sessionOptions = OrtSessionOptions();
    late final OrtSession session;
    try {
      sessionOptions.setIntraOpNumThreads(1);
      sessionOptions.setInterOpNumThreads(1);
      session = OrtSession.fromBuffer(
        File('example/assets/models/test_types_FLOAT.pb').readAsBytesSync(),
        sessionOptions,
      );
    } finally {
      sessionOptions.release();
    }
    try {
      for (var iteration = 0; iteration < 20; iteration++) {
        final tensor = OrtValueTensor.createTensorWithDataList(
          Float32List.fromList([1, 2, -3, -99, 99999]), [1, 5],
        );
        final cancelledOptions = OrtRunOptions()..setTerminate();
        try {
          expect(() => session.run(cancelledOptions, {'input': tensor}),
            throwsA(isA<Exception>()));
          await expectLater(
            session.runAsync(cancelledOptions, {'input': tensor})!,
            throwsStateError,
          );
        } finally {
          cancelledOptions.release();
        }
        final options = OrtRunOptions();
        List<OrtValue?> outputs = [];
        try {
          expect(() => session.run(options, {'invalid_input': tensor}),
            throwsA(isA<Exception>()));
          outputs = await session.runAsync(options, {'input': tensor})!;
          expect(outputs.first!.value, [[1.0, 2.0, -3.0, -99.0, 99999.0]]);
        } finally {
          for (final output in outputs) { output?.release(); }
          options.release();
          tensor.release();
        }
      }
    } finally {
      await session.release();
      OrtEnv.instance.release();
    }
  }, skip: Platform.environment['ONNX_NATIVE_TEST'] != '1',
    timeout: const Timeout(Duration(seconds: 15)));
}
