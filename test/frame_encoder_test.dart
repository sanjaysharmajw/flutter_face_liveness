// Closures assigned to variables are deliberate: they reproduce how the real
// controller method captures `this` into its closure context.
// ignore_for_file: prefer_function_declarations_over_variables

import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_face_liveness/src/ml/face_detector_service.dart' show RawFrameData;
import 'package:flutter_face_liveness/src/ml/frame_encoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Mid-grey NV21 frame (Y plane + interleaved VU plane).
RawFrameData _nv21Frame({int width = 64, int height = 48, int sensorOrientation = 0}) {
  final bytes = Uint8List(width * height * 3 ~/ 2)..fillRange(0, width * height * 3 ~/ 2, 128);
  return RawFrameData(
    imageBytes: bytes,
    imageWidth: width,
    imageHeight: height,
    sensorOrientation: sensorOrientation,
  );
}

/// Mirrors the shape of LivenessController._onEngineComplete: an instance
/// method that holds an unsendable resource and contains another closure
/// referencing `this`, so `this` lands in the method's closure context.
class _FakeController {
  final ReceivePort unsendable = ReceivePort();
  RawFrameData? bestFrame = _nv21Frame();

  /// The pre-fix pattern: Isolate.run with an inline closure.
  Future<Uint8List?> encodeInline() async {
    final fallback = () => bestFrame; // captures `this`, like the real method
    final frame = fallback()!;
    const quality = 85;
    return Isolate.run(() => encodeFrameToJpeg(frame, quality: quality));
  }

  /// The fixed pattern: top-level helper.
  Future<Uint8List?> encodeViaHelper() async {
    final fallback = () => bestFrame;
    return encodeFrameToJpegInBackground(fallback()!, quality: 85);
  }

  void dispose() => unsendable.close();
}

void main() {
  group('encodeFrameToJpegInBackground', () {
    test('returns a decodable JPEG with the frame dimensions', () async {
      final jpeg = await encodeFrameToJpegInBackground(_nv21Frame());

      expect(jpeg, isNotNull);
      final decoded = img.decodeJpg(jpeg!);
      expect(decoded, isNotNull);
      expect(decoded!.width, 64);
      expect(decoded.height, 48);
    });

    test('rotates sensor-space frames upright (90° swaps dimensions)', () async {
      final jpeg = await encodeFrameToJpegInBackground(_nv21Frame(sensorOrientation: 90));

      final decoded = img.decodeJpg(jpeg!)!;
      expect(decoded.width, 48);
      expect(decoded.height, 64);
    });
  });

  group('regression: onSuccess never fired with enableBestFrontalCapture', () {
    late _FakeController controller;
    setUp(() => controller = _FakeController());
    tearDown(() => controller.dispose());

    test('inline Isolate.run closure inside an instance method throws', () async {
      await expectLater(
        controller.encodeInline(),
        throwsA(predicate((e) => e.toString().contains('ReceivePort'))),
      );
    });

    test('top-level helper succeeds from the same instance method', () async {
      final jpeg = await controller.encodeViaHelper();
      expect(jpeg, isNotNull);
    });
  });
}
