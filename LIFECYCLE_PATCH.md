# Inference lifecycle patch

This fork carries the Dart lifecycle fixes originally maintained in AuraID's
`vendor/onnxruntime_aura`, introduced by AuraID commit `d1f00e97`.
They are ported onto upstream main `8cde2fbe36b55c3b01e5745234f6f65a5c512caf`,
preserving its model metadata API and QNN provider support. Native libraries,
platform integration and inference mathematics are unchanged by the lifecycle
patch itself.

## Behavior and ownership

- Requests have IDs and success/error replies. Fatal isolate errors and actual
  exits settle pending requests; the next request can recreate an exited worker.
- Release drains pending requests before cooperative worker shutdown. It does
  not kill a worker or impose a timeout on native inference.
- Run allocations, partial outputs, tensor metadata and failed buffer-based
  session/options creation are cleaned up on the patched failure paths.
- `OrtSession.release()` now returns `Future<void>`. Await it before releasing
  the environment or other resources that pending inference may still use.
  Keep input tensors and run options alive until their inference future settles.
- Optional `maxPendingRuns` on file/buffer sessions rejects excess asynchronous
  requests before dispatch, counting startup, queued and active requests. The
  default remains unlimited. UI cancellation, upstream frame queues and
  watchdogs remain application responsibilities.
  A cancelled caller does not prove native completion. A permanently stalled
  native Run can retain its session indefinitely; do not replace it or free its
  resources while it still owns them.
- Synchronous runs, metadata queries and address access reject a closing or
  released session. The worker retains its borrowed session wrapper while
  draining accepted requests; only the original owner releases native state.
- Tensor metadata is read lazily. Numeric typed inputs avoid an intermediate
  Dart list; `toTypedList()` returns an owned flat copy that survives tensor
  release. `.value` retains scalar/nested-list output semantics. Releasing the
  same value wrapper twice is harmless; reading it after release throws.
- Tensor construction validates shape before native allocation and cleans up
  failed creation. UTF-8 strings, model metadata, provider options and other
  temporary native allocations are released on success and failure. Missing
  custom metadata keys throw `ArgumentError`.
- Shared global thread pools require both `OrtEnv.init(options: threading)`
  and `OrtSessionOptions.disablePerSessionThreads()`. Repeated environment
  initialization does not acquire another native environment reference.

## Verification

The migrated channel tests cover request correlation, failures, duplicate replies,
worker exit/recreation, startup failure and draining release:

```sh
flutter test test/onnx_isolate_channel_test.dart
```

The opt-in native regression runs 20 CPU rounds of synchronous/asynchronous
termination errors, invalid input and successful Identity inference using the
existing MIT-licensed `example/assets/models/test_types_FLOAT.pb` fixture:

```sh
DYLD_INSERT_LIBRARIES="$ORT_DYLIB" ONNX_NATIVE_TEST=1 \
  "$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" \
  "$FLUTTER_ROOT/bin/cache/flutter_tools.snapshot" \
  test --no-pub test/onnx_native_lifecycle_test.dart
```

Set `FLUTTER_ROOT` to your Flutter SDK directory and run `flutter pub get` first.
Set `ORT_DYLIB` to the absolute path of `libonnxruntime.1.30.0.dylib` from the
official macOS ARM64 release archive (see [native dependencies](NATIVE_DEPENDENCIES.md)).
The Flutter test runner does not link the application's native Swift package
dependencies, so the library must be injected into its process for this opt-in
test. This standalone test command requires an Apple Silicon Mac; the
universal macOS XCFramework used by applications also includes Intel. Invoking
Dart directly avoids macOS stripping `DYLD_INSERT_LIBRARIES`
while passing through the Flutter shell launcher.

These checks do not establish device/CoreML cancellation latency, recovery from
a native process crash, or allocation-failure behavior on every native API path.
