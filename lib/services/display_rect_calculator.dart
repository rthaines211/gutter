import 'package:flutter/painting.dart';

Rect calculateDisplayRect({
  required int imageWidth,
  required int imageHeight,
  required double viewportWidth,
  required double viewportHeight,
  required BoxFit fit,
}) {
  final imageAspect = imageWidth / imageHeight;
  final viewportAspect = viewportWidth / viewportHeight;

  double renderWidth;
  double renderHeight;

  switch (fit) {
    case BoxFit.contain:
      if (imageAspect > viewportAspect) {
        renderWidth = viewportWidth;
        renderHeight = viewportWidth / imageAspect;
      } else {
        renderHeight = viewportHeight;
        renderWidth = viewportHeight * imageAspect;
      }
    case BoxFit.fitWidth:
      renderWidth = viewportWidth;
      renderHeight = viewportWidth / imageAspect;
    case BoxFit.fitHeight:
      renderHeight = viewportHeight;
      renderWidth = viewportHeight * imageAspect;
    default:
      if (imageAspect > viewportAspect) {
        renderWidth = viewportWidth;
        renderHeight = viewportWidth / imageAspect;
      } else {
        renderHeight = viewportHeight;
        renderWidth = viewportHeight * imageAspect;
      }
  }

  final left = (viewportWidth - renderWidth) / 2;
  final top = (viewportHeight - renderHeight) / 2;

  return Rect.fromLTWH(left, top, renderWidth, renderHeight);
}
