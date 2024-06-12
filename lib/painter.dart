import 'package:flutter/material.dart';

class ObjectDetectorPainter extends CustomPainter {
  final List<Rect> rectangles;

  ObjectDetectorPainter(this.rectangles);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (var rect in rectangles) {
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}