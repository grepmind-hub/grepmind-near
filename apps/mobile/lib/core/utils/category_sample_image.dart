import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const categorySampleLabels = <String>[
  'Fresh produce',
  'Tools & hardware',
  'Pharmacy',
  'Restaurant',
  'Salon',
  'Plumbing',
  'Electrical',
  'Carpentry',
  'Tailoring',
  'Grocery store',
  'Hotel',
  'Fashion',
  'Books & stationery',
  'Cleaning',
  'Home & kitchen',
  'Wellness',
  'Electronics',
  'Fitness',
  'Automotive',
  'Handloom',
];

/// Maps API category metadata to representative, bundled merchant photography.
int categorySampleIndex(String slug, String name) {
  final value = '$slug $name'.toLowerCase();
  if (value.contains('grocery') || value.contains('grocer')) {
    return 0;
  }
  if (value.contains('hardware') || value.contains('tool')) {
    return 1;
  }
  if (value.contains('medical') || value.contains('pharmacy')) {
    return 2;
  }
  if (value.contains('restaurant') ||
      value.contains('food') ||
       value.contains('cafe')) {
    return 3;
  }
  if (value.contains('salon') || value.contains('beauty')) {
    return 4;
  }
  if (value.contains('plumb')) {
    return 5;
  }
  if (value.contains('electric')) {
    return 6;
  }
  if (value.contains('carpent') || value.contains('furniture')) {
    return 7;
  }
  if (value.contains('tailor') || value.contains('stitch')) {
    return 8;
  }
  if (value.contains('general') || value.contains('convenience')) {
    return 9;
  }
  if (value.contains('hotel') || value.contains('stay')) {
    return 10;
  }
  if (value.contains('fashion') ||
      value.contains('cloth') ||
       value.contains('boutique')) {
    return 11;
  }
  if (value.contains('book') || value.contains('station')) {
    return 12;
  }
  if (value.contains('clean')) {
    return 13;
  }
  if (value.contains('kitchen') || value.contains('home')) {
    return 14;
  }
  if (value.contains('wellness') || value.contains('yoga')) {
    return 15;
  }
  if (value.contains('electronic') || value.contains('mobile')) {
    return 16;
  }
  if (value.contains('fitness') || value.contains('sport')) {
    return 17;
  }
  if (value.contains('auto') ||
      value.contains('vehicle') ||
       value.contains('mechanic')) {
    return 18;
  }
  if (value.contains('handloom') ||
      value.contains('artisan') ||
       value.contains('weav')) {
    return 19;
  }
  return 0;
}

class CategorySampleImage extends StatelessWidget {
  const CategorySampleImage({
    super.key,
    required this.index,
    this.fit = BoxFit.cover,
  });

  final int index;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => FutureBuilder<ui.Image>(
    future: _atlas,
    builder: (context, snapshot) {
      final image = snapshot.data;
      if (image == null) {
        return const ColoredBox(color: Color(0xFFE8EEF8));
      }
      return CustomPaint(
        painter: _SamplePainter(image, index.clamp(0, 19), fit),
        child: const SizedBox.expand(),
      );
    },
  );
}

class _SamplePainter extends CustomPainter {
  const _SamplePainter(this.image, this.index, this.fit);
  final ui.Image image;
  final int index;
  final BoxFit fit;

  @override
  void paint(Canvas canvas, Size size) {
    final sourceWidth = image.width / 4;
    final sourceHeight = image.height / 5;
    final source = Rect.fromLTWH(
      (index % 4) * sourceWidth,
      (index ~/ 4) * sourceHeight,
      sourceWidth,
      sourceHeight,
    );
    final destination = applyBoxFit(fit, source.size, size);
    final sourceRect = Alignment.center.inscribe(destination.source, source);
    final destinationRect = Alignment.center.inscribe(
      destination.destination,
      Offset.zero & size,
    );
    canvas.drawImageRect(
      image,
      sourceRect,
      destinationRect,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_SamplePainter oldDelegate) =>
      image != oldDelegate.image ||
      index != oldDelegate.index ||
      fit != oldDelegate.fit;
}

Future<ui.Image> _atlas = _loadAtlas();

Future<ui.Image> _loadAtlas() async {
  final data = await rootBundle.load('assets/images/category_sample_atlas.png');
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

Future<Uint8List> cropCategorySample(int index) async {
  final image = await _atlas;
  final width = image.width ~/ 4;
  final height = image.height ~/ 5;
  final x = (index.clamp(0, 19) % 4) * width;
  final y = (index.clamp(0, 19) ~/ 4) * height;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(
      x.toDouble(),
      y.toDouble(),
      width.toDouble(),
      height.toDouble(),
    ),
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..filterQuality = FilterQuality.high,
  );
  final crop = await recorder.endRecording().toImage(width, height);
  final bytes = await crop.toByteData(format: ui.ImageByteFormat.png);
  crop.dispose();
  if (bytes == null) {
    throw StateError('Could not prepare the selected sample image.');
  }
  return bytes.buffer.asUint8List();
}
