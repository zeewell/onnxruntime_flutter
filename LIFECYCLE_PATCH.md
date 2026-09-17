# Inference lifecycle patch

This fork carries the Dart lifecycle fixes originally maintained in AuraID's
`vendor/onnxruntime_aura`, introduced by AuraID commit `d1f00e97`.
They are ported onto upstream main `8cde2fbe36b55c3b01e5745234f6f65a5c512caf`,
preserving its model metadata API and QNN provider support. Native libraries,
platform integration and inference mathematics are unchanged.

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
- UI cancellation, queue bounds and watchdogs remain application responsibilities.
  A cancelled caller does not prove native completion. A permanently stalled
  native Run can retain its session indefinitely; do not replace it or free its
  resources while it still owns them.

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
DYLD_LIBRARY_PATH="$PWD/macos" ONNX_NATIVE_TEST=1 \
  "$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" \
  "$FLUTTER_ROOT/bin/cache/flutter_tools.snapshot" \
  test --no-pub test/onnx_native_lifecycle_test.dart
```

Set `FLUTTER_ROOT` to your Flutter SDK directory and run `flutter pub get` first.
Invoking the Dart executable directly avoids macOS stripping `DYLD_LIBRARY_PATH`
while passing through the Flutter shell launcher.

These checks do not establish device/CoreML cancellation latency, recovery from
a native process crash, or allocation-failure behavior on every native API path.
