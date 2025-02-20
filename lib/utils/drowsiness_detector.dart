import 'dart:math';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class DrowsinessDetector {
  final FaceDetector _faceDetector;

  // Parameters for drowsiness detection
  int _consecutiveFramesWithClosedEyes = 0;
  final int _drowsinessThreshold = 10;
  bool _isDrowsy = false;

  // Parameters for yawn detection
  int _consecutiveFramesWithYawn = 0;
  final int _yawnThreshold = 5; // Reduced from 8
  bool _isYawning = false;

  // Yawn detection parameters - more sensitive
  final double _yawnAspectRatioThreshold = 0.4; // Lowered from 0.6
  final int _stableFramesRequired = 2; // Reduced from 3

  // Track maximum mouth opening
  double _maxMouthOpening = 0.0;
  bool _calibrationComplete = false;
  int _calibrationFrames = 0;
  final int _requiredCalibrationFrames = 20;

  // Historical values for stability checking
  List<double> _recentAspectRatios = [];
  double _baselineAspectRatio = 0.0;
  bool _baselineEstablished = false;
  int _stableFrames = 0;

  DrowsinessDetector() : _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  Future<Map<String, bool>> processCameraImage(InputImage inputImage) async {
    final faces = await _faceDetector.processImage(inputImage);

    if (faces.isEmpty) {
      return {'drowsy': false, 'yawning': false};
    }

    final face = faces.first;
    _detectDrowsiness(face);
    _detectYawn(face);

    return {
      'drowsy': _isDrowsy,
      'yawning': _isYawning
    };
  }

  void _resetCounters() {
    _consecutiveFramesWithClosedEyes = 0;
    _consecutiveFramesWithYawn = 0;
    _isDrowsy = false;
    _isYawning = false;
    _recentAspectRatios.clear();
    _baselineEstablished = false;
    _stableFrames = 0;
  }

  void _detectDrowsiness(Face face) {
    if (face.leftEyeOpenProbability != null &&
        face.rightEyeOpenProbability != null) {
      bool eyesClosed = face.leftEyeOpenProbability! < 0.2 &&
          face.rightEyeOpenProbability! < 0.2;

      if (eyesClosed) {
        _consecutiveFramesWithClosedEyes++;
      } else {
        _consecutiveFramesWithClosedEyes = 0;
      }

      _isDrowsy = _consecutiveFramesWithClosedEyes >= _drowsinessThreshold;
    }
  }

  void _detectYawn(Face face) {
    // Get mouth landmarks
    final bottomMouth = face.landmarks[FaceLandmarkType.bottomMouth]?.position;
    final leftMouth = face.landmarks[FaceLandmarkType.leftMouth]?.position;
    final rightMouth = face.landmarks[FaceLandmarkType.rightMouth]?.position;

    // If we don't have all landmarks, skip this frame
    if (bottomMouth == null || leftMouth == null || rightMouth == null) {
      return;
    }

    // Calculate mouth aspect ratio (height/width)
    double mouthWidth = (rightMouth.x - leftMouth.x).toDouble().abs();
    double mouthHeight = (bottomMouth.y - ((leftMouth.y + rightMouth.y) / 2)).toDouble().abs();

    // Avoid division by zero
    if (mouthWidth < 1.0) mouthWidth = 1.0;

    double aspectRatio = mouthHeight / mouthWidth;

    // Add to recent ratios for stability
    _recentAspectRatios.add(aspectRatio);
    if (_recentAspectRatios.length > 10) {
      _recentAspectRatios.removeAt(0);
    }

    // Calibration phase - measure normal mouth state
    if (!_calibrationComplete) {
      _calibrationFrames++;

      // Update baseline as moving average during calibration
      if (_baselineEstablished) {
        _baselineAspectRatio = (_baselineAspectRatio * 0.9) + (aspectRatio * 0.1);
      } else if (_recentAspectRatios.length >= 3) {
        // Initialize baseline when we have at least 3 frames
        _baselineAspectRatio = _recentAspectRatios.reduce((a, b) => a + b) / _recentAspectRatios.length;
        _baselineEstablished = true;
      }

      // Track maximum mouth opening during calibration
      _maxMouthOpening = max(_maxMouthOpening, aspectRatio);

      // Finish calibration after sufficient frames
      if (_calibrationFrames >= _requiredCalibrationFrames) {
        _calibrationComplete = true;
      }

      return; // Skip detection during calibration
    }

    // Adaptive threshold based on observed maximum
    double yawnThreshold = max(_yawnAspectRatioThreshold, _baselineAspectRatio * 1.3);

    // Check both absolute and relative criteria for yawn detection
    bool isLikelyYawning = aspectRatio > yawnThreshold ||
        (aspectRatio > _baselineAspectRatio * 1.5);

    if (isLikelyYawning) {
      _stableFrames++;
      if (_stableFrames >= _stableFramesRequired) {
        _consecutiveFramesWithYawn++;
      }
    } else {
      // Gradual reset to avoid flickering
      _stableFrames = max(0, _stableFrames - 1);
      _consecutiveFramesWithYawn = max(0, _consecutiveFramesWithYawn - 1);
    }

    _isYawning = _consecutiveFramesWithYawn >= _yawnThreshold;
  }

  void dispose() {
    _faceDetector.close();
  }
}
