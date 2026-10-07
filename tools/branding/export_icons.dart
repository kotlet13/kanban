// Mechanical exports of the generated artwork. Does not regenerate the design.
// Uses the image package already pinned by flutter_launcher_icons.
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

void main() {
  final root = Directory('assets/branding/jivie');
  final source = img.decodePng(
    File('${root.path}/source-mark.png').readAsBytesSync(),
  );
  if (source == null || source.width != source.height || !source.hasAlpha) {
    throw StateError('Expected a square RGBA source-mark.png');
  }
  final foreground = img.copyResize(
    source,
    width: 1024,
    height: 1024,
    interpolation: img.Interpolation.average,
  );
  final master = img.Image(width: 1024, height: 1024, numChannels: 3);
  img.fill(master, color: img.ColorRgb8(244, 246, 250));
  img.compositeImage(master, foreground);
  final monochrome = img.Image(width: 1024, height: 1024, numChannels: 4);
  var minX = 1024, minY = 1024, maxX = -1, maxY = -1;
  var maxRadius = 0.0;
  for (final pixel in foreground) {
    monochrome.setPixelRgba(pixel.x, pixel.y, 255, 255, 255, pixel.a);
    if (pixel.a > 127) {
      if (pixel.x < minX) minX = pixel.x;
      if (pixel.y < minY) minY = pixel.y;
      if (pixel.x > maxX) maxX = pixel.x;
      if (pixel.y > maxY) maxY = pixel.y;
      maxRadius = math.max(
        maxRadius,
        math.sqrt(math.pow(pixel.x - 511.5, 2) + math.pow(pixel.y - 511.5, 2)),
      );
    }
  }
  void write(String name, img.Image image) =>
      File('${root.path}/$name').writeAsBytesSync(img.encodePng(image));
  write('icon-master.png', master);
  write('icon-foreground.png', foreground);
  write('icon-monochrome.png', monochrome);
  write(
    'google-play-512.png',
    img.copyResize(
      master,
      width: 512,
      height: 512,
      interpolation: img.Interpolation.average,
    ),
  );
  // Combined with the source's transparent margin, the configured 12% inset
  // keeps the substantial mark inside Android's 66/108 dp safe-area circle.
  // Operating systems provide the outer icon mask, never baked-in corners.
  if (maxRadius * 0.76 > 1024 * 33 / 108) {
    throw StateError('Artwork exceeds the adaptive safe area with 12% inset');
  }
  stdout.writeln(
    'Exported RGB master/store icon and RGBA foreground/monochrome.',
  );
  stdout.writeln(
    'Foreground alpha>127 bounds: $minX,$minY to $maxX,$maxY /1024.',
  );
  stdout.writeln(
    'Inset mark radius ${maxRadius * 0.76}; safe radius ${1024 * 33 / 108}.',
  );
}
