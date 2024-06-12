import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:harlem_text_extract/painter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late String recognizedText = 'No Detected';
  final ImagePicker picker = ImagePicker();
  late CameraController _cameraController;
  late StreamController<String> _streamController;
  late List<Rect> objectRectangles = [];
  late int objectCount = 0;
  late int textRecognitionDelay = 500; 
  late DateTime _lastTextRecognitionTime;

    @override
  void initState() {
    super.initState();
    _streamController = StreamController<String>();
    _initializeCamera();
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _streamController.close();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: SafeArea(
        child: Scaffold(
          backgroundColor: Colors.white60,
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildButton(
                        onTap: () async {
                          final FilePickerResult? result = await FilePicker.platform.pickFiles();
                          if (result != null) {
                            final PlatformFile file = result.files.first;
                            final String path = file.path!;
                            if (path.endsWith('.jpg') || path.endsWith('.jpeg') || path.endsWith('.png')) {
                              final String recognized = await _getImageToText(path);

                              final int count = countObjects(recognized);
                              setState(() {
                                recognizedText = recognized;
                                objectCount = count;
                              });
                            } else {
                              // Handle other file types here
                            }
                          }
                        },
                        icon: Icons.attach_file,
                        label: 'Select File',
                      ),
                      _buildButton(
                        onTap: () async {
                          final XFile? image =
                              await picker.pickImage(source: ImageSource.camera);
                          if (image != null) {
                            final String recognized = await _getImageToText(image.path);

                            final int count = countObjects(recognized);
                            setState(() {
                              recognizedText = recognized;

                              objectCount = count;
                            });
                          }
                        },
                        icon: Icons.camera_alt,
                        label: 'Capture Image',
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 20.0),
                _buildDivider(),
                SizedBox(height: 20.0),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Text(
                    recognizedText,
                    style: TextStyle(color: Colors.black, fontSize: 20),
                  ),
                ),
                SizedBox(height: 20.0),
                _buildDivider(),
                SizedBox(height: 20.0),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Text(
                    'Object Count: $objectCount',
                    style: TextStyle(color: Colors.black, fontSize: 20),
                  ),
                ),
                SizedBox(height: 20.0),
                _cameraPreviewWidget(),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () {
              if (_cameraController != null && _cameraController.value.isStreamingImages) {
                _stopObjectDetection();
              } else {
                _startObjectDetection();
              }
            },
            child: Icon(_cameraController != null && _cameraController.value.isStreamingImages
                ? Icons.stop
                : Icons.play_arrow),
          ),
        ),
      ),
    );
  }

  Widget _buildButton({required VoidCallback onTap, required IconData icon, required String label}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            height: 60,
            width: 60,
            decoration: BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 35),
          ),
          SizedBox(height: 10),
          Text(label, style: TextStyle(color: Colors.black)),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Divider(
        thickness: 2,
        color: Colors.black,
      ),
    );
  }

  Widget _cameraPreviewWidget() {
    if (_cameraController != null && _cameraController.value.isInitialized) {
      return Stack(
        children: [
          AspectRatio(
            aspectRatio: _cameraController.value.aspectRatio,
            child: CameraPreview(_cameraController),
          ),
          CustomPaint(
            painter: ObjectDetectorPainter(objectRectangles),
          ),
        ],
      );
    } else {
      return Container();
    }
  }

  Future<void> _initializeCamera() async {
    _cameraController = CameraController(cameras[0], ResolutionPreset.max);
    await _cameraController.initialize();
    if (!mounted) return;
    setState(() {});
  }

  Future<String> _getImageToText(final imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final textDetector = GoogleMlKit.vision.textRecognizer();
      final RecognizedText recognizedText = await textDetector.processImage(inputImage);
      List<TextBlock> blocks = recognizedText.blocks;
      setState(() {
        objectRectangles = blocks.map((block) => block.boundingBox).toList();
      });
      String text = recognizedText.text;
      _streamController.add(text);
      setState(() {
        this.recognizedText = text;
      });
      textDetector.close();
      return text; 
    } catch (e) {
      print("Error in text recognition: $e");
      return ''; 
    }
  }

  Future<void> _stopObjectDetection() async {
    if (_cameraController != null && _cameraController.value.isStreamingImages) {
      await _cameraController.stopImageStream();
      setState(() {
        objectRectangles = [];
        objectCount = 0;
      });
    }
  }

  Future<void> _startObjectDetection() async {
    try {
      _lastTextRecognitionTime = DateTime.now();
      await _cameraController.startImageStream((CameraImage image) async {
        if (DateTime.now().difference(_lastTextRecognitionTime).inMilliseconds >=
            textRecognitionDelay) {
          final inputImage = InputImage.fromBytes(
            metadata: InputImageMetadata(
              size: Size(image.width.toDouble(), image.height.toDouble()),
              rotation: InputImageRotation.rotation0deg,
              format: InputImageFormat.nv21,
              bytesPerRow: image.width * 4,
            ),
            bytes: concatenatePlanes(image.planes),
          );
          final textDetector = GoogleMlKit.vision.textRecognizer();
          final RecognizedText recognizedText =
              await textDetector.processImage(inputImage);
          List<TextBlock> blocks = recognizedText.blocks;

          objectRectangles.clear();

          int count = 0;
          for (TextBlock block in blocks) {
            String blockText = block.text;
            count += countObjects(blockText);
            Rect boundingBox = block.boundingBox!;
            objectRectangles.add(boundingBox);
          }
          setState(() {
            objectCount = count;
          });
          textDetector.close();
          _lastTextRecognitionTime = DateTime.now();
        }
      });
    } catch (e) {
      print("Error in object detection: $e");
    }
  }

  int countObjects(String recognizedText) {
    List<String> keywords = ["284", "1.02", "125"];
    int totalCount = 0;
    for (String keyword in keywords) {
      RegExp regExp = RegExp(keyword, caseSensitive: true);
      Iterable<Match> matches = regExp.allMatches(recognizedText);
      totalCount += matches.length;
    }
    return totalCount;
  }

  Uint8List concatenatePlanes(List<Plane> planes) {
  int totalSize = planes.map((plane) => plane.bytes.length).reduce((value, element) => value + element);
  Uint8List bytes = Uint8List(totalSize);
  int planeIndex = 0;
  int offset = 0;
  planes.forEach((plane) {
    bytes.setRange(offset, offset + plane.bytes.length, plane.bytes);
    offset += plane.bytes.length;
  });
  return bytes;
  }
}
