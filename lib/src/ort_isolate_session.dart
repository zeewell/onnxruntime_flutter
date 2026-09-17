import 'dart:isolate';

import 'package:onnxruntime/src/ort_isolate_channel.dart';
import 'package:onnxruntime/src/ort_session.dart';
import 'package:onnxruntime/src/ort_value.dart';

class OrtIsolateSession {
  OrtIsolateSession(OrtSession session,
      {this.debugName = 'OnnxRuntimeSessionIsolate', int? maxPendingRuns})
      : address = session.address {
    _channel = OrtIsolateChannel(createNewIsolateContext,
        debugName: debugName, maxPendingRequests: maxPendingRuns);
  }

  final int address;
  final String debugName;
  late final OrtIsolateChannel _channel;
  IsolateSessionState get state => _channel.isBusy
      ? IsolateSessionState.loading
      : IsolateSessionState.idle;

  static void createNewIsolateContext(SendPort replies) async {
    final commands = ReceivePort();
    replies.send(commands.sendPort);
    OrtSession? session;
    await for (final command in commands) {
      if (command == null) {
        commands.close();
        break;
      }
      final envelope = command as List;
      final id = envelope[1] as int;
      final data = envelope[2] as _IsolateSessionData;
      List<OrtValue?> outputs = const [];
      var transferred = false;
      try {
        // Borrowed wrappers never own the caller's session/options/tensors.
        // This worker belongs to one native session. Cache its stable metadata;
        // only the caller releases the native session after this worker exits.
        session ??= OrtSession.fromAddress(data.session);
        final options = OrtRunOptions.fromAddress(data.runOptions);
        final inputs = data.inputs.map(
            (key, value) => MapEntry(key, OrtValueTensor.fromAddress(value)));
        outputs = session.run(options, inputs, data.outputNames);
        final values = outputs.map((output) {
          final type = output is OrtValueSequence
              ? ONNXType.sequence
              : output is OrtValueMap
                  ? ONNXType.map
                  : output is OrtValueSparseTensor
                      ? ONNXType.sparseTensor
                      : ONNXType.tensor;
          return [type.value, output?.address];
        }).toList();
        replies.send(['ok', id, values]);
        transferred = true;
      } catch (error, stack) {
        replies.send(['error', id, error.toString(), stack.toString()]);
      } finally {
        if (!transferred) {
          for (final output in outputs) {
            output?.release();
          }
        }
      }
    }
  }

  Future<List<OrtValue?>> run(
      OrtRunOptions options, Map<String, OrtValue> inputs,
      [List<String>? outputNames]) async {
    final values = await _channel.request(_IsolateSessionData(
        session: address,
        runOptions: options.address,
        inputs: inputs.map((key, value) => MapEntry(key, value.address)),
        outputNames: outputNames)) as List;
    final outputs = <OrtValue?>[];
    try {
      for (final value in values) {
        final address = value[1] as int?;
        outputs.add(address == null
            ? null
            : OrtValue.fromAddress(address, ONNXType.valueOf(value[0] as int)));
      }
      return outputs;
    } catch (_) {
      // Wrapping can fail too; all addresses have transferred to this isolate.
      for (final value in values) {
        final address = value[1] as int?;
        if (address != null) OrtValue.releaseAddress(address);
      }
      rethrow;
    }
  }

  Future<void> release() => _channel.release();
}

enum IsolateSessionState { idle, loading }

class _IsolateSessionData {
  _IsolateSessionData({required this.session, required this.runOptions,
    required this.inputs, this.outputNames});
  final int session;
  final int runOptions;
  final Map<String, int> inputs;
  final List<String>? outputNames;
}
