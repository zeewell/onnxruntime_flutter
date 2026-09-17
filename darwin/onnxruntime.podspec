Pod::Spec.new do |s|
  s.name             = 'onnxruntime'
  s.version          = '1.4.1'
  s.summary          = 'ONNX Runtime C API integration for Flutter.'
  s.description      = 'Links the official ONNX Runtime library for the Flutter Dart FFI API.'
  s.homepage         = 'https://github.com/gtbluesky/onnxruntime_flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'gtbluesky'
  s.source           = { :path => '.' }

  s.ios.deployment_target = '15.1'
  s.osx.deployment_target = '14.0'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.dependency 'onnxruntime-c', '1.30.0'
  s.static_framework = true

  # The dependency supplies the native code. Match the Swift package's symbol
  # retention so Dart FFI can resolve these entry points in release builds.
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) -Wl,-u,_OrtGetApiBase -Wl,-u,_OrtSessionOptionsAppendExecutionProvider_CPU -Wl,-u,_OrtSessionOptionsAppendExecutionProvider_CoreML'
  }
end
