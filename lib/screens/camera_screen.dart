import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'dart:typed_data';
import '../utils/drowsiness_detector.dart';

class CameraScreen extends StatefulWidget {
  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  DrowsinessDetector? _drowsinessDetector;
  bool _isProcessing = false;
  bool _isDrowsy = false;
  bool _isYawning = false;
  bool _isCameraInitialized = false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _initializeCamera();
    _drowsinessDetector = DrowsinessDetector();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) {
        final frontCamera = _cameras.firstWhere(
              (camera) => camera.lensDirection == CameraLensDirection.front,
          orElse: () => _cameras.first,
        );

        _cameraController = CameraController(
          frontCamera,
          ResolutionPreset.medium,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.yuv420,
        );

        await _cameraController!.initialize();

        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
          _startImageStream();
        }
      }
    } catch (e) {
      print('Error initializing camera: $e');
    }
  }

  void _startImageStream() {
    if (_cameraController != null) {
      _cameraController!.startImageStream((CameraImage cameraImage) async {
        if (!_isProcessing) {
          _isProcessing = true;
          try {
            final inputImage = _convertCameraImageToInputImage(
              cameraImage,
              _cameraController!.description,
            );

            if (inputImage != null) {
              final result = await _drowsinessDetector!.processCameraImage(inputImage);

              if (mounted) {
                setState(() {
                  _isDrowsy = result['drowsy'] ?? false;
                  _isYawning = result['yawning'] ?? false;
                });

                if (_isDrowsy || _isYawning) {
                  _playAlertSound();
                }
              }
            }
          } catch (e) {
            print('Error processing image: $e');
          }
          _isProcessing = false;
        }
      });
    }
  }

  InputImage? _convertCameraImageToInputImage(
      CameraImage cameraImage, CameraDescription cameraDescription) {
    final BytesBuilder allBytes = BytesBuilder();
    for (final Plane plane in cameraImage.planes) {
      allBytes.add(plane.bytes);
    }
    final bytes = allBytes.toBytes();

    final imageRotation = InputImageRotationValue.fromRawValue(
      cameraDescription.sensorOrientation,
    );

    if (imageRotation == null) return null;

    final inputImageFormat = InputImageFormatValue.fromRawValue(cameraImage.format.raw);
    if (inputImageFormat == null) return null;

    final metadata = InputImageMetadata(
      size: Size(cameraImage.width.toDouble(), cameraImage.height.toDouble()),
      rotation: imageRotation,
      format: inputImageFormat,
      bytesPerRow: cameraImage.planes[0].bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  void _playAlertSound() {
    print('ALERT: Drowsiness or Yawning detected!');
    // Implement actual sound alert here
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _cameraController?.dispose();
    _drowsinessDetector?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('DROWY APP for Driver')),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              child: CameraPreview(_cameraController!),
            ),
          ),
          Container(
            color: (_isDrowsy || _isYawning) ? Colors.red : Colors.green,
            padding: EdgeInsets.all(16),
            width: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  (_isDrowsy || _isYawning)
                      ? 'AWAS! ${_isDrowsy ? "MENGANTUK!" : "MENGUAP!"}'
                      : 'Status: Active',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  (_isDrowsy || _isYawning)
                      ? 'Sila berhenti memandu/berehat'
                      : 'Detector system activate',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
