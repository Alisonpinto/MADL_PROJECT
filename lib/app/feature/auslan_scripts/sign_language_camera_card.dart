import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, debugPrint;
import 'package:flutter/material.dart';

import '../../services/auslan_network_service.dart';
import '../auslan_scripts/auslan_predict.dart';

class SignLanguageCameraCard extends StatefulWidget {
  const SignLanguageCameraCard({
    super.key,
    required this.label,
    required this.accent,
    this.onPrediction,
    this.onFinalized,
  });

  final String label;
  final Color accent;
  final Function(String rawLabel, double confidence, String allLetters)?
      onPrediction;
  final Function(String capturedLetters, String? guessedText, String trigger)?
      onFinalized;

  @override
  State<SignLanguageCameraCard> createState() => _SignLanguageCameraCardState();
}

class _SignLanguageCameraCardState extends State<SignLanguageCameraCard> {
  final AuslanNetworkService _networkService = AuslanNetworkService();
  CameraController? _controller;
  List<CameraDescription> _availableCameras = [];
  int _selectedCameraIndex = 0;

  bool _isDisposed = false;
  bool _isInitializingCamera = false;
  bool _isInitialized = false;
  String? _cameraError;

  bool _isPredicting = false;
  String _prediction = '';
  double _confidence = 0;
  String _statusMessage = 'Connecting to recognition server...';
  String? _serverError;
  bool _isServerHealthy = false;
  String? _connectedUrl;

  Timer? _timer;
  CameraImage? _latestFrame;
  String _allLetters = '';
  DateTime? _lastHandDetectedAt;
  bool _isFinalizing = false;

  AuslanPredictor? _predictor;

  @override
  void initState() {
    super.initState();
    unawaited(_initPredictor());
    unawaited(_initCamera());
    unawaited(_checkServerHealth());
  }

  Future<void> _checkServerHealth() async {
    final health = await _networkService.checkServerHealth();
    if (!mounted || _isDisposed) return;
    setState(() {
      _isServerHealthy = health.isReachable;
      _connectedUrl = health.url;
      if (health.isReachable) {
        _serverError = null;
        _statusMessage = 'Server connected: ${health.url}';
      } else {
        _serverError = health.errorMessage;
        _statusMessage = health.errorMessage ?? 'Recognition server unavailable';
      }
    });
  }

  Future<void> _initPredictor() async {
    _predictor = AuslanPredictor();
    try {
      await _predictor!.loadModel();
      if (mounted) {
        debugPrint('Local Auslan predictor model loaded successfully.');
      }
    } catch (error) {
      debugPrint('Predictor bootstrap failed: $error');
    }
  }

  void _showStatus(String message) {
    if (!mounted || _statusMessage == message) return;
    setState(() => _statusMessage = message);
  }

  Future<void> _initCamera([int? preferredIndex]) async {
    if (_isInitializingCamera) return;
    setState(() {
      _isInitializingCamera = true;
      _isInitialized = false;
      _cameraError = null;
    });

    try {
      _availableCameras = await availableCameras();
      if (_availableCameras.isEmpty) {
        if (mounted) {
          setState(() {
            _cameraError = 'No camera found on this device or emulator.';
            _isInitializingCamera = false;
          });
        }
        return;
      }

      int targetIndex = preferredIndex ?? _selectedCameraIndex;
      if (preferredIndex == null) {
        // Default to FRONT camera for sign language (facing the user)
        final frontIndex = _availableCameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
        );
        targetIndex = frontIndex >= 0 ? frontIndex : 0;
      }

      _selectedCameraIndex = targetIndex.clamp(0, _availableCameras.length - 1);
      final camera = _availableCameras[_selectedCameraIndex];

      // Dispose existing controller if any
      final oldController = _controller;
      _controller = null;
      if (oldController != null) {
        if (oldController.value.isStreamingImages) {
          await oldController.stopImageStream().catchError((_) {});
        }
        await oldController.dispose().catchError((_) {});
      }

      // Using ResolutionPreset.low or medium to prevent frame pipeline lag
      final controller = CameraController(
        camera,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );

      await controller.initialize();
      if (!mounted || _isDisposed) {
        await controller.dispose();
        return;
      }

      await controller.startImageStream((frame) {
        if (!mounted || _isDisposed) return;
        _latestFrame = frame;
      });

      _controller = controller;
      setState(() {
        _isInitialized = true;
        _isInitializingCamera = false;
        _cameraError = null;
      });

      _timer?.cancel();
      _timer = Timer.periodic(
        const Duration(milliseconds: 350),
        (_) => _sendFrame(),
      );
    } on CameraException catch (e) {
      debugPrint('CameraException during init: ${e.code} - ${e.description}');
      if (mounted) {
        setState(() {
          _cameraError = 'Camera error: ${e.description ?? e.code}';
          _isInitialized = false;
          _isInitializingCamera = false;
        });
      }
    } catch (e) {
      debugPrint('General camera error: $e');
      if (mounted) {
        setState(() {
          _cameraError = 'Failed to initialize camera: $e';
          _isInitialized = false;
          _isInitializingCamera = false;
        });
      }
    }
  }

  Future<void> _switchCamera() async {
    if (_availableCameras.length < 2) return;
    final nextIndex = (_selectedCameraIndex + 1) % _availableCameras.length;
    await _initCamera(nextIndex);
  }

  Future<void> _sendFrame() async {
    final controller = _controller;
    if (_isDisposed ||
        _isPredicting ||
        controller == null ||
        !controller.value.isInitialized ||
        _predictor == null ||
        _latestFrame == null) {
      return;
    }

    _isPredicting = true;

    try {
      final frameBytes = await _encodeFrameToPng(_latestFrame!);
      if (frameBytes == null) {
        _showStatus('Camera frame format not supported');
        return;
      }

      final result = await _networkService.sendFrame(frameBytes);

      if (!mounted) return;

      if (!result.isSuccess) {
        setState(() {
          _isServerHealthy = false;
          _serverError = result.errorMessage;
          _statusMessage = result.errorMessage ?? 'Recognition server unavailable';
        });
        return;
      }

      setState(() {
        _isServerHealthy = true;
        _serverError = null;
        _connectedUrl = result.connectedUrl ?? _connectedUrl;
      });

      final now = DateTime.now();
      if (!result.hasHand) {
        _showStatus('Show one hand clearly to the camera');
        if (_lastHandDetectedAt != null &&
            now.difference(_lastHandDetectedAt!) >= const Duration(seconds: 5)) {
          await _finalizeCapture(trigger: 'no-hand-5s');
          _lastHandDetectedAt = null;
        }
        return;
      }

      _lastHandDetectedAt = now;

      final predictor = _predictor!;
      final prediction = predictor.processRawPrediction(
        rawLabel: result.label,
        confidencePercent: result.confidence,
      );

      setState(() {
        _statusMessage = '';
        _prediction = prediction.rawLabel;
        _confidence = prediction.confidence;
        _allLetters = prediction.allLetters;
      });

      if (prediction.acceptedLetter.isNotEmpty) {
        widget.onPrediction?.call(
          prediction.rawLabel,
          prediction.confidence,
          prediction.allLetters,
        );
      }
    } catch (e) {
      debugPrint('Prediction Error: $e');
    } finally {
      _isPredicting = false;
    }
  }

  Future<void> _finalizeCapture({required String trigger}) async {
    if (_isFinalizing || _predictor == null) return;

    final predictor = _predictor!;
    if (!predictor.hasCapturedLetters) return;

    _isFinalizing = true;
    final capturedLetters = predictor.allLetters;
    String? guessedText;
    try {
      guessedText = await predictor.guessWordPhrase();
      widget.onFinalized?.call(capturedLetters, guessedText, trigger);
    } catch (e) {
      debugPrint('Finalize Error: $e');
      widget.onFinalized?.call(capturedLetters, null, trigger);
    } finally {
      predictor.resetCaptureState();
      if (mounted) {
        setState(() {
          _allLetters = '';
        });
      }
      _isFinalizing = false;
    }
  }

  Future<Uint8List?> _encodeFrameToPng(CameraImage frame) async {
    if (frame.planes.isEmpty) return null;

    if (frame.format.group == ImageFormatGroup.jpeg) {
      return frame.planes.first.bytes;
    }

    final Uint8List rgbaBytes;
    if (frame.format.group == ImageFormatGroup.bgra8888) {
      final source = frame.planes.first.bytes;
      rgbaBytes = Uint8List(source.length);
      for (var i = 0; i + 3 < source.length; i += 4) {
        rgbaBytes[i] = source[i + 2];
        rgbaBytes[i + 1] = source[i + 1];
        rgbaBytes[i + 2] = source[i];
        rgbaBytes[i + 3] = source[i + 3];
      }
    } else if (frame.format.group == ImageFormatGroup.yuv420 &&
        frame.planes.length >= 3) {
      rgbaBytes = _yuv420ToRgba(frame);
    } else {
      return null;
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgbaBytes,
      frame.width,
      frame.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final image = await completer.future;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return byteData?.buffer.asUint8List();
  }

  Uint8List _yuv420ToRgba(CameraImage frame) {
    final width = frame.width;
    final height = frame.height;
    final yPlane = frame.planes[0];
    final uPlane = frame.planes[1];
    final vPlane = frame.planes[2];
    final rgba = Uint8List(width * height * 4);

    for (var y = 0; y < height; y++) {
      final yRow = y * yPlane.bytesPerRow;
      final uvRow = (y ~/ 2) * uPlane.bytesPerRow;
      for (var x = 0; x < width; x++) {
        final yValue = yPlane.bytes[yRow + x];
        final uvColumn = (x ~/ 2) * (uPlane.bytesPerPixel ?? 1);
        final uValue = uPlane.bytes[uvRow + uvColumn];
        final vValue = vPlane.bytes[(y ~/ 2) * vPlane.bytesPerRow +
            (x ~/ 2) * (vPlane.bytesPerPixel ?? 1)];

        final yAdjusted = yValue - 16;
        final uAdjusted = uValue - 128;
        final vAdjusted = vValue - 128;
        final red = (1.164 * yAdjusted + 1.596 * vAdjusted)
            .round()
            .clamp(0, 255);
        final green = (1.164 * yAdjusted -
                0.392 * uAdjusted -
                0.813 * vAdjusted)
            .round()
            .clamp(0, 255);
        final blue = (1.164 * yAdjusted + 2.017 * uAdjusted)
            .round()
            .clamp(0, 255);
        final offset = (y * width + x) * 4;

        rgba[offset] = red;
        rgba[offset + 1] = green;
        rgba[offset + 2] = blue;
        rgba[offset + 3] = 255;
      }
    }

    return rgba;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _timer?.cancel();
    final controller = _controller;
    _controller = null;
    if (controller?.value.isStreamingImages ?? false) {
      unawaited(controller!.stopImageStream().catchError((_) {}));
    }
    if (controller != null) {
      unawaited(controller.dispose().catchError((_) {}));
    }
    _networkService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: () => _finalizeCapture(trigger: 'double-tap'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          color: const Color(0xFF111827),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Camera Preview or Error / Loading states
              if (_isInitialized &&
                  _controller != null &&
                  _controller!.value.isInitialized)
                ClipRect(
                  child: SizedBox.expand(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: _controller!.value.previewSize != null
                            ? (defaultTargetPlatform == TargetPlatform.android ||
                                    defaultTargetPlatform == TargetPlatform.iOS
                                ? _controller!.value.previewSize!.height
                                : _controller!.value.previewSize!.width)
                            : 1,
                        height: _controller!.value.previewSize != null
                            ? (defaultTargetPlatform == TargetPlatform.android ||
                                    defaultTargetPlatform == TargetPlatform.iOS
                                ? _controller!.value.previewSize!.width
                                : _controller!.value.previewSize!.height)
                            : 1,
                        child: CameraPreview(_controller!),
                      ),
                    ),
                  ),
                )
              else if (_cameraError != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.videocam_off_rounded,
                          size: 56,
                          color: Colors.redAccent,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _cameraError!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => _initCamera(),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry Camera'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.accent,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white54),
                      const SizedBox(height: 16),
                      Text(
                        _isInitializingCamera
                            ? 'Starting camera...'
                            : widget.label,
                        style: const TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

              // Top accent line
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(height: 3, color: widget.accent),
              ),

              // 2. Camera Switch Button (Top Right)
              if (_availableCameras.length > 1 && _isInitialized)
                Positioned(
                  top: 14,
                  right: 14,
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: const Icon(
                        Icons.flip_camera_ios_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      tooltip: 'Switch Camera',
                      onPressed: _switchCamera,
                    ),
                  ),
                ),

              // 3. Recognized Gesture & Confidence Badge (Top Left)
              if (_prediction.isNotEmpty)
                Positioned(
                  top: 14,
                  left: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _confidence >= 80
                            ? Colors.greenAccent
                            : Colors.orangeAccent,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _prediction,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_confidence.toStringAsFixed(1)}%',
                          style: TextStyle(
                            color: _confidence >= 80
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // 4. Status and Error Message Overlay
              if (_serverError != null ||
                  (_statusMessage.isNotEmpty && _prediction.isEmpty))
                Positioned(
                  top: 68,
                  left: 16,
                  right: 16,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _serverError != null
                            ? const Color(0xDD7F1D1D)
                            : Colors.black.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _serverError != null
                              ? Colors.redAccent.withValues(alpha: 0.6)
                              : Colors.white24,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _serverError != null
                                    ? Icons.wifi_off_rounded
                                    : Icons.info_outline_rounded,
                                color: _serverError != null
                                    ? Colors.redAccent
                                    : Colors.amberAccent,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _serverError ?? _statusMessage,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_serverError != null) ...[
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () => unawaited(_checkServerHealth()),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white24,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.refresh,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'Retry Connection',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),

              // 5. Server Connection Indicator (Bottom Left)
              Positioned(
                bottom: 14,
                left: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isServerHealthy
                              ? Colors.greenAccent
                              : Colors.redAccent,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isServerHealthy
                            ? 'Server Online'
                            : 'Server Offline',
                        style: TextStyle(
                          color: _isServerHealthy
                              ? Colors.greenAccent
                              : Colors.redAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 6. Captured Letters Display & Finalize button
              if (_allLetters.isNotEmpty)
                Positioned(
                  bottom: 14,
                  left: 120,
                  right: 14,
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Text(
                            _allLetters,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2.0,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _isFinalizing
                            ? null
                            : () => _finalizeCapture(trigger: 'button'),
                        icon: const Icon(Icons.translate, size: 18),
                        label: const Text('Translate'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
