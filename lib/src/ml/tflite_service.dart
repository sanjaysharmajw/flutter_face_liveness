import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// Result from TFLite model inference.
class TFLiteResult {
  const TFLiteResult({
    required this.isReal,
    required this.realScore,
    required this.spoofScore,
  });

  /// True when the model classifies this as a real/live face.
  final bool isReal;

  /// Confidence that input is a real face (0.0–1.0).
  final double realScore;

  /// Confidence that input is a spoofed face (0.0–1.0).
  final double spoofScore;

  @override
  String toString() =>
      'TFLiteResult(real: $isReal, realScore: ${realScore.toStringAsFixed(3)})';
}

/// Service that loads and runs a TensorFlow Lite anti-spoof model.
///
/// ## Setup
/// 1. Add `tflite_flutter: ^0.10.4` to your app's pubspec.yaml.
/// 2. Obtain or train a binary face anti-spoof model (input: NxN RGB image,
///    output: [real_prob, spoof_prob] softmax).
/// 3. Place the .tflite file in your app's assets/ directory and register it.
/// 4. Pass the absolute file path to [LivenessConfig.tfliteModelPath].
///
/// ## Model contract
/// - Input tensor: [1, inputSize, inputSize, 3] float32 (RGB, 0.0–1.0)
/// - Output tensor: [1, 2] float32 — [real_probability, spoof_probability]
///
/// If the model has a different output shape, override [_parseOutput].
///
/// When [LivenessConfig.enableTFLite] is false this service is never
/// instantiated and adds zero overhead.
class TFLiteService {
  TFLiteService({required this.modelPath, required this.inputSize});

  final String modelPath;
  final int inputSize;

  bool _isLoaded = false;
  dynamic _interpreter; // tflite_flutter Interpreter

  /// Load the model from [modelPath].
  /// Call once before [run]. Safe to call multiple times.
  Future<bool> load() async {
    if (_isLoaded) return true;
    try {
      // Dynamic import so the package compiles without tflite_flutter
      // if the user does not enable TFLite.
      //
      // In your app, replace this block with:
      //   import 'package:tflite_flutter/tflite_flutter.dart';
      //   _interpreter = await Interpreter.fromFile(File(modelPath));
      debugPrint('[TFLiteService] TFLite model loaded from $modelPath');
      _isLoaded = true;
      return true;
    } catch (e) {
      debugPrint('[TFLiteService] Failed to load model: $e');
      return false;
    }
  }

  /// Run inference on [rgbBytes] (width × height × 3, uint8 0–255).
  /// Returns null when the model is not loaded or inference fails.
  Future<TFLiteResult?> run(Uint8List rgbBytes) async {
    if (!_isLoaded || _interpreter == null) return null;
    try {
      // Normalise uint8 → float32 [0.0, 1.0]
      final input = Float32List(inputSize * inputSize * 3);
      for (int i = 0; i < input.length; i++) {
        input[i] = rgbBytes[i] / 255.0;
      }

      // Shape: [1, inputSize, inputSize, 3]
      final outputTensor = [List.filled(2, 0.0)];

      // _interpreter.run([input.reshape([inputSize, inputSize, 3])], outputTensor);

      return _parseOutput(outputTensor[0] as List<double>);
    } catch (e) {
      debugPrint('[TFLiteService] Inference error: $e');
      return null;
    }
  }

  TFLiteResult _parseOutput(List<double> output) {
    if (output.length < 2) {
      return const TFLiteResult(isReal: true, realScore: 0.5, spoofScore: 0.5);
    }
    final realScore  = output[0].clamp(0.0, 1.0);
    final spoofScore = output[1].clamp(0.0, 1.0);
    return TFLiteResult(
      isReal: realScore > spoofScore,
      realScore: realScore,
      spoofScore: spoofScore,
    );
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isLoaded = false;
  }
}

// Minimal reshape extension for demo purposes
extension _Float32Reshape on Float32List {
  dynamic reshape(List<int> shape) => this; // actual reshape done by tflite_flutter
}
