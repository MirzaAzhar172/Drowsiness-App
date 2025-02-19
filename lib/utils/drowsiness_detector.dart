import 'dart:math';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class DrowsinessDetector {
  final FaceDetector _faceDetector;

  // Parameters for drowsiness detection
  int _consecutiveFramesWithClosedEyes = 0;
  final int _drowsinessThreshold = 10; // Number of frames with closed eyes to trigger alert
  bool _isDrowsy = false;

  DrowsinessDetector() : _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,  // For eye open probability
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  Future<bool> processCameraImage(InputImage inputImage) async {
    final faces = await _faceDetector.processImage(inputImage);

    if (faces.isEmpty) {
      // Reset if no face found
      _consecutiveFramesWithClosedEyes = 0;
      _isDrowsy = false;
      return false;
    }

    // Take the first detected face
    final face = faces.first;

    // Check if eyes are closed (using left eye as reference)
    if (face.leftEyeOpenProbability != null &&
        face.rightEyeOpenProbability != null) {
      bool eyesClosed = face.leftEyeOpenProbability! < 0.3 &&
          face.rightEyeOpenProbability! < 0.3;

      if (eyesClosed) {
        _consecutiveFramesWithClosedEyes++;
      } else {
        _consecutiveFramesWithClosedEyes = 0;
      }

      _isDrowsy = _consecutiveFramesWithClosedEyes >= _drowsinessThreshold;
    }

    return _isDrowsy;
  }

  void dispose() {
    _faceDetector.close();
  }
}
