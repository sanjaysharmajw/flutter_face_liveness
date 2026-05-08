import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Wraps the bundled MobileFaceNet TFLite model.
///
/// Input :  [1, 112, 112, 3] Float32, pixel values in [-1, 1]
/// Output:  [1, 128]         Float32, L2-normalised face embedding
class FaceEmbeddingModel {
  static const String _asset =
      'packages/flutter_face_liveness/assets/models/mobile_face_net.tflite';
  static const int embeddingSize = 128;

  Interpreter? _interpreter;

  bool get isLoaded => _interpreter != null;

  Future<void> load() async {
    try {
      final data  = await rootBundle.load(_asset);
      final bytes = data.buffer.asUint8List();
      final opts  = InterpreterOptions()..threads = 2;
      _interpreter = Interpreter.fromBuffer(bytes, options: opts);
      _interpreter!.allocateTensors();
      debugPrint('[FaceEmbeddingModel] MobileFaceNet loaded (${bytes.length ~/ 1024} KB)');
    } catch (e) {
      _interpreter = null;
      throw Exception(
        '[FaceEmbeddingModel] Could not load model from $_asset.\n'
        'Run  scripts/download_face_model.sh  to fetch the MobileFaceNet weights.\n'
        'Original error: $e',
      );
    }
  }

  /// Returns an L2-normalised 128-dimensional embedding, or `null` on error.
  List<double>? infer(Float32List input112x112x3) {
    if (_interpreter == null) return null;
    try {
      final inputTensor  = input112x112x3.reshape([1, 112, 112, 3]);
      final outputBuffer = [List<double>.filled(embeddingSize, 0.0)];
      _interpreter!.run(inputTensor, outputBuffer);
      return _l2Normalize(outputBuffer[0]);
    } catch (e) {
      debugPrint('[FaceEmbeddingModel] Inference error: $e');
      return null;
    }
  }

  // L2-normalise so cosine similarity == dot product
  static List<double> _l2Normalize(List<double> v) {
    double norm = 0.0;
    for (final x in v) norm += x * x;
    norm = math.sqrt(norm);
    if (norm < 1e-10) return v;
    return v.map((x) => x / norm).toList();
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}
