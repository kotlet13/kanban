// Encode actual widget captures as opaque RGB PNGs for App Store Connect.
// Geometry and every visible RGB pixel are preserved; no scaling or compositing.
import 'dart:io';
import 'dart:convert';
import 'package:image/image.dart' as img;

void main(List<String> args) {
  final input = Directory(args.single);
  final output = Directory('${input.parent.path}/upload');
  final evidence = <Map<String, Object>>[];
  for (final device in ['iphone', 'ipad']) {
    final files =
        Directory('${input.path}/$device')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.png'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    if (files.length != 7)
      throw StateError('Expected seven captures for $device');
    Directory('${output.path}/$device').createSync(recursive: true);
    for (final file in files) {
      final source = img.decodePng(file.readAsBytesSync())!;
      final rgb = source.convert(numChannels: 3);
      for (final pixel in source) {
        if (pixel.a != 255)
          throw StateError('Capture contains actual transparency');
        final other = rgb.getPixel(pixel.x, pixel.y);
        if (pixel.r != other.r || pixel.g != other.g || pixel.b != other.b)
          throw StateError('RGB mismatch');
      }
      final bytes = img.encodePng(rgb);
      if (bytes[25] != 2)
        throw StateError('PNG must be RGB without an alpha channel');
      final name = file.uri.pathSegments.last;
      File('${output.path}/$device/$name').writeAsBytesSync(bytes);
      evidence.add({
        'device': device,
        'file': name,
        'width': source.width,
        'height': source.height,
        'rgbIdentical': true,
        'pngColorType': 2,
      });
    }
  }
  File(
    '${input.parent.path}/screenshots-evidence.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(evidence));
  print('14 RGB PNGs encoded; dimensions and all visible pixels preserved.');
}
