import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(CameraApp());

class CameraApp extends StatefulWidget {
  const CameraApp({super.key});

  @override
  _CameraAppState createState() => _CameraAppState();
}

class _CameraAppState extends State<CameraApp> {
  List<CameraDescription> _cameras = [];
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isCapturing = false;
  Timer? _timer;
  String _responseText = 'Initializing...';
  int _selectedCameraIndex = 0;

  final String instruction = "What do you see?";
  final String baseUrl = "http://192.168.100.224:8080";
  final int captureIntervalMs = 1000;

  @override
  void initState() {
    super.initState();
    _initCameraList();
  }

  Future<void> _initCameraList() async {
    await Permission.camera.request();
    _cameras = await availableCameras();

    if (_cameras.isNotEmpty) {
      // Set default to front camera if available
      final frontIndex = _cameras.indexWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
      );
      if (frontIndex != -1) {
        _selectedCameraIndex = frontIndex;
      }

      await _initializeCamera(_cameras[_selectedCameraIndex]);
    } else {
      setState(() {
        _responseText = 'No camera found.';
      });
    }
  }

  Future<void> _initializeCamera(CameraDescription cameraDescription) async {
    _timer?.cancel();
    await _cameraController?.dispose();

    _cameraController = CameraController(
      cameraDescription,
      ResolutionPreset.medium,
    );

    try {
      await _cameraController!.initialize();
    } catch (e) {
      setState(() {
        _responseText = 'Camera initialization error: $e';
      });
      return;
    }

    if (!mounted) return;

    setState(() {
      _isCameraInitialized = true;
    });

    _timer = Timer.periodic(
      Duration(milliseconds: captureIntervalMs),
      (_) => _captureAndSendImage(),
    );
  }

  void _switchCamera() async {
    if (_cameras.length < 2) return;

    setState(() {
      _isCameraInitialized = false;
      _responseText = "Switching camera...";
    });

    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    await _initializeCamera(_cameras[_selectedCameraIndex]);
  }

  Future<void> _captureAndSendImage() async {
    if (_isCapturing ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized)
      return;

    setState(() => _isCapturing = true);

    try {
      final XFile file = await _cameraController!.takePicture();
      final bytes = await file.readAsBytes();
      final base64Image = base64Encode(bytes);
      final response = await _sendToServer(instruction, base64Image);

      setState(() => _responseText = response);
    } catch (e) {
      setState(() => _responseText = 'Capture error: $e');
    } finally {
      _isCapturing = false;
    }
  }

  Future<String> _sendToServer(String instruction, String base64Image) async {
    final url = Uri.parse('$baseUrl/v1/chat/completions');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "max_tokens": 100,
          "messages": [
            {
              "role": "user",
              "content": [
                {"type": "text", "text": instruction},
                {
                  "type": "image_url",
                  "image_url": {"url": "data:image/jpeg;base64,$base64Image"},
                },
              ],
            },
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'] ??
            'No response content.';
      } else {
        return 'Server error: ${response.statusCode} ${response.body}';
      }
    } catch (e) {
      return 'Network error: $e';
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: Text('Camera Interaction App'),
          actions: [
            IconButton(
              icon: Icon(Icons.cameraswitch),
              onPressed: _cameras.length > 1 ? _switchCamera : null,
              tooltip: 'Switch Camera',
            ),
          ],
        ),
        body:
            _isCameraInitialized && _cameraController != null
                ? Column(
                  children: [
                    // AspectRatio(
                    //   aspectRatio: _cameraController!.value.aspectRatio,
                    //   child: CameraPreview(_cameraController!),
                    // ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final size = _cameraController!.value.previewSize!;
                          final scale = constraints.maxWidth / size.height;

                          return FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: size.height,
                              height: size.width,
                              child: CameraPreview(_cameraController!),
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        'Prompt: $instruction',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0),
                        child: Text(
                          'Response: $_responseText',
                          style: TextStyle(fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                )
                : Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
