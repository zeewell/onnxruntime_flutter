import 'dart:async';
import 'dart:isolate';

/// Request IDs and replies share one event port with fatal errors and exit.
/// No timeout kills the worker: a sent request owns native pointers until its
/// reply or actual isolate exit. The next request rebuilds an exited worker.
class OrtIsolateChannel {
  OrtIsolateChannel(this.entryPoint, {required this.debugName});

  final void Function(SendPort) entryPoint;
  final String debugName;
  final Map<int, Completer<Object?>> _pending = {};
  SendPort? _commands;
  Future<void>? _starting;
  Completer<void>? _ready;
  Completer<void>? _exited;
  ReceivePort? _events;
  Object? _fatalError;
  StackTrace? _fatalStack;
  int _nextId = 0;
  bool _closed = false;

  bool get isBusy => _pending.isNotEmpty;

  Future<void> _ensureStarted() {
    return _starting ??= _start();
  }

  Future<void> _start() async {
    final events = ReceivePort();
    _events = events;
    final ready = Completer<void>();
    _ready = ready;
    _exited = Completer<void>();
    events.listen(_onEvent);
    // Attach before spawning so even a startup error/exit is observable.
    final readiness = ready.future;
    unawaited(Isolate.spawn(entryPoint, events.sendPort,
          debugName: debugName,
          onError: events.sendPort,
          onExit: events.sendPort,
          errorsAreFatal: true).then<void>((_) {}, onError: (Object error, StackTrace stack) {
      _fatalError = error;
      _fatalStack = stack;
      _onEvent(null);
    }));
    await readiness;
  }

  void _onEvent(dynamic event) {
    if (event is SendPort) {
      _commands = event;
      if (!_ready!.isCompleted) _ready!.complete();
      return;
    }
    if (event == null) {
      final error = _fatalError ?? StateError('ONNX inference isolate exited');
      final stack = _fatalStack ?? StackTrace.current;
      if (_ready?.isCompleted == false) _ready!.completeError(error, stack);
      for (final request in _pending.values) {
        request.completeError(error, stack);
      }
      _pending.clear();
      _commands = null;
      _starting = null;
      _fatalError = null;
      _fatalStack = null;
      _events?.close();
      _events = null;
      _exited?.complete();
      return;
    }
    if (event is List && event.length == 2) {
      // A fatal error precedes exit. Wait for exit before returning ownership.
      _fatalError = StateError('ONNX isolate error: ${event[0]}');
      _fatalStack = StackTrace.fromString(event[1].toString());
      return;
    }
    final reply = event as List;
    final request = _pending.remove(reply[1] as int);
    if (request == null) return; // Duplicate terminal replies cannot settle twice.
    if (reply[0] == 'ok') {
      request.complete(reply[2]);
    } else {
      request.completeError(
        StateError('ONNX inference failed: ${reply[2]}'),
        StackTrace.fromString(reply[3] as String),
      );
    }
  }

  Future<Object?> request(Object? payload) async {
    if (_closed) throw StateError('ONNX isolate channel released');
    await _ensureStarted();
    if (_closed) throw StateError('ONNX isolate channel released');
    final id = ++_nextId;
    final result = Completer<Object?>();
    _pending[id] = result;
    try {
      _commands!.send(['request', id, payload]);
    } catch (error, stack) {
      _pending.remove(id);
      result.completeError(error, stack);
    }
    return result.future;
  }

  Future<void> release() async {
    if (_closed) return _exited?.future;
    _closed = true;
    try {
      await _starting;
    } catch (_) {
      return;
    }
    await Future.wait(_pending.values.map((request) async {
      try {
        await request.future;
      } catch (_) {}
    }).toList());
    _commands?.send(null);
    await _exited?.future;
  }
}
