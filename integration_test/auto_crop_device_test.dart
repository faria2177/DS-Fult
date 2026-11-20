// Runs the real gallery auto-crop (native OpenCV, ML Kit, U²-Net model,
// Dart fallbacks) on an Android emulator against synthetic photos that copy
// the situations users reported. Each result is compared with the true
// document corners.
//
//   python3 tool/make_autocrop_fixtures.py
//   flutter test integration_test/auto_crop_device_test.dart -d <device>
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:docscanner/src/screens/gallery_import_review_screen.dart';
import 'package:docscanner/src/services/document_edges.dart';
import 'package:docscanner/src/services/image_processor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'autocrop_fixture_data.dart';

/// Overlap of two convex quads (normalized), rasterised on a 240×240 grid.
double quadIou(List<Offset> a, List<Offset> b) {
  bool inside(List<Offset> q, Offset p) {
    var sign = 0;
    for (var i = 0; i < 4; i++) {
      final s = q[i];
      final e = q[(i + 1) % 4];
      final c = (e.dx - s.dx) * (p.dy - s.dy) - (e.dy - s.dy) * (p.dx - s.dx);
      final d = c > 0 ? 1 : c < 0 ? -1 : 0;
      if (d != 0) {
        if (sign == 0) {
          sign = d;
        } else if (d != sign) {
          return false;
        }
      }
    }
    return true;
  }

  const n = 240;
  var both = 0;
  var either = 0;
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final p = Offset((x + .5) / n, (y + .5) / n);
      final ia = inside(a, p);
      final ib = inside(b, p);
      if (ia && ib) both++;
      if (ia || ib) either++;
    }
  }
  return either == 0 ? 0 : both / either;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('gallery auto crop finds the whole document', (tester) async {
    final dir = await getTemporaryDirectory();
    // Finished pages (crop + Enhance, exactly as Import Images does) are
    // kept where `adb pull` can reach them for a visual check.
    final shots = Directory(
        '${(await getExternalStorageDirectory())!.path}/autocrop');
    await shots.create(recursive: true);
    final failures = <String>[];
    for (final entry in autoCropScenes.entries) {
      final (data, flat) = entry.value;
      final file = File('${dir.path}/${entry.key}.jpg');
      await file.writeAsBytes(base64Decode(data), flush: true);
      final truth = [
        for (var i = 0; i < 8; i += 2) Offset(flat[i], flat[i + 1]),
      ];
      final watch = Stopwatch()..start();
      final detection = await DocumentEdges.detectSafeStillOutline(file.path);
      final quad = detection?.quad;
      final iou = quad == null ? 0.0 : quadIou(quad.points, truth);
      final batch = await DocumentEdges.autoCropFiles([file.path]);
      final imported = await processGalleryImport(sourcePaths: [file.path],
          autoCrop: true, filter: ScanFilter.enhance);
      await File(imported.paths.single)
          .copy('${shots.path}/${entry.key}_imported.jpg');
      // Small copy in the log as well, for reviewers without artifacts.
      final page = img.decodeImage(await File(imported.paths.single).readAsBytes());
      if (page != null) {
        final small = base64Encode(img.encodeJpg(
            img.copyResize(page, width: 360), quality: 70));
        for (var i = 0; i < small.length; i += 700) {
          // ignore: avoid_print
          print('SHOT ${entry.key} ${i ~/ 700} '
              '${small.substring(i, i + 700 > small.length ? small.length : i + 700)}');
        }
      }
      // ignore: avoid_print
      print('AUTOCROP ${entry.key} iou=${iou.toStringAsFixed(3)} '
          'ms=${watch.elapsedMilliseconds} cropped=${batch.croppedCount} '
          'quad=${quad?.points.map((p) => '${p.dx.toStringAsFixed(3)},'
              '${p.dy.toStringAsFixed(3)}').join(' ')}');
      if (iou < .90 || batch.croppedCount != 1) {
        failures.add('${entry.key}: iou ${iou.toStringAsFixed(3)}, '
            'cropped ${batch.croppedCount}');
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}
