import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:onnxruntime/src/ort_isolate_channel.dart';

void _worker(SendPort replies) async {
  final commands = ReceivePort();
  replies.send(commands.sendPort);
  await for (final dynamic message in commands) {
    if (message == null) { commands.close(); break; }
    final id = message[1] as int;
    final value = message[2];
    if (value == 'exit') Isolate.exit();
    if (value == 'fatal') throw StateError('injected fatal error');
    if (value == 'error') {
      replies.send(['error', id, 'injected native failure', 'test stack']);
    } else {
      if (value == 'slow') await Future<void>.delayed(const Duration(milliseconds: 30));
      replies.send(['ok', id, value]);
      if (value == 'duplicate') replies.send(['ok', id, value]);
    }
  }
}

void _startupFailure(SendPort replies) { throw StateError('startup failure'); }

void main() {
  test('request IDs correlate concurrent callers; errors and duplicates settle once', () async {
    final channel = OrtIsolateChannel(_worker, debugName: 'test');
    addTearDown(channel.release);
    expect(await Future.wait([channel.request(1), channel.request(2)]), [1, 2]);
    await expectLater(channel.request('error'), throwsStateError);
    expect(await channel.request('duplicate'), 'duplicate');
    expect(await channel.request(3), 3);
  });

  for (final kind in ['exit', 'fatal']) {
    test('$kind completes all pending callers and next request rebuilds worker', () async {
      final channel = OrtIsolateChannel(_worker, debugName: 'test');
      addTearDown(channel.release);
      await channel.request('ready');
      final first = channel.request(kind);
      final second = channel.request('queued');
      await Future.wait([
        expectLater(first, throwsStateError),
        expectLater(second, throwsStateError),
      ]);
      expect(channel.isBusy, isFalse);
      expect(await channel.request('recovered'), 'recovered');
    });
  }

  test('startup failure completes request and permits another bounded attempt', () async {
    final channel = OrtIsolateChannel(_startupFailure, debugName: 'test');
    addTearDown(channel.release);
    await expectLater(channel.request(1), throwsStateError);
    await expectLater(channel.request(2), throwsStateError);
  });

  test('release during pending work drains reply before cooperative exit', () async {
    final channel = OrtIsolateChannel(_worker, debugName: 'test');
    await channel.request('ready');
    final result = channel.request('slow');
    await Future<void>.delayed(Duration.zero);
    var released = false;
    final release = channel.release().then((_) { released = true; });
    expect(released, isFalse);
    expect(await result, 'slow');
    await release;
    expect(released, isTrue);
    await channel.release();
    await expectLater(channel.request(1), throwsStateError);
  });
}
