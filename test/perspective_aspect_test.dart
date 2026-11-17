import 'dart:math' as math;
import 'dart:ui';

import 'package:docscanner/src/services/perspective_aspect.dart';
import 'package:flutter_test/flutter_test.dart';

const _image = Size(3000, 4000);

/// Photographs a [width] x [height] rectangle with a phone-like pinhole
/// camera (focal 0.75 x long side), tilted by [rx]/[ry]/[rz] radians.
List<Offset> _photo(double width, double height,
    {double rx = 0, double ry = 0, double rz = 0, double distance = 650,
    double focalScale = .75}) {
  final f = focalScale * 4000;
  List<double> rotate(List<double> p) {
    var x = p[0], y = p[1], z = p[2];
    // X axis.
    var y1 = y * math.cos(rx) - z * math.sin(rx);
    var z1 = y * math.sin(rx) + z * math.cos(rx);
    y = y1; z = z1;
    // Y axis.
    final x2 = x * math.cos(ry) + z * math.sin(ry);
    final z2 = -x * math.sin(ry) + z * math.cos(ry);
    x = x2; z = z2;
    // Z axis.
    final x3 = x * math.cos(rz) - y * math.sin(rz);
    final y3 = x * math.sin(rz) + y * math.cos(rz);
    return [x3, y3, z];
  }

  return [
    for (final c in [[-1, -1], [1, -1], [1, 1], [-1, 1]])
      () {
        final p = rotate([c[0] * width / 2, c[1] * height / 2, 0]);
        final z = p[2] + distance;
        return Offset(f * p[0] / z + _image.width / 2,
            f * p[1] / z + _image.height / 2);
      }(),
  ];
}

double _naiveRatio(List<Offset> c) =>
    (((c[0] - c[1]).distance + (c[3] - c[2]).distance) / 2) /
    (((c[0] - c[3]).distance + (c[1] - c[2]).distance) / 2);

Size _output(List<Offset> c) => PerspectiveAspect.outputSize(c, _image,
    ((c[0] - c[1]).distance + (c[3] - c[2]).distance) / 2,
    ((c[0] - c[3]).distance + (c[1] - c[2]).distance) / 2);

void main() {
  test('a steeply tilted A4 page comes out exactly A4', () {
    final corners = _photo(210, 297, rx: .55, ry: .2, rz: .1);
    // The old method squeezes the far end noticeably.
    expect((_naiveRatio(corners) / (210 / 297) - 1).abs(), greaterThan(.05));
    final size = _output(corners);
    expect(size.width / size.height, closeTo(1 / 1.41421, .002));
  });

  test('a tilted bank card keeps the ID-1 shape', () {
    final size = _output(_photo(85.6, 54, rx: -.45, ry: .3, distance: 280));
    expect(size.width / size.height, closeTo(1.58577, .003));
  });

  test('a non-standard shape is recovered without snapping', () {
    final corners = _photo(180, 100, rx: .5, ry: -.25, distance: 500);
    final size = _output(corners);
    expect(size.width / size.height, closeTo(1.8, .03));
  });

  test('a camera with a different lens is still much better than before',
      () {
    final corners = _photo(210, 297, rx: .5, ry: .3, focalScale: .65);
    final before = (_naiveRatio(corners) / (210 / 297) - 1).abs();
    final size = _output(corners);
    final after = (size.width / size.height / (210 / 297) - 1).abs();
    expect(after, lessThan(before / 2));
  });

  test('resolution is kept: the output area matches the old size', () {
    final corners = _photo(210, 297, rx: .4, ry: .2);
    final w = ((corners[0] - corners[1]).distance +
            (corners[3] - corners[2]).distance) / 2;
    final h = ((corners[0] - corners[3]).distance +
            (corners[1] - corners[2]).distance) / 2;
    final size = _output(corners);
    expect(size.width * size.height, closeTo(w * h, w * h * 1e-9));
  });

  test('a front-on rectangle is left as it is', () {
    const corners = [Offset(500, 600), Offset(2300, 600), Offset(2300, 3000),
      Offset(500, 3000)];
    final size = _output(corners);
    expect(size.width / size.height, closeTo(1800 / 2400, 1e-6));
  });

  test('degenerate corners fall back to the old size', () {
    const corners = [Offset(0, 0), Offset(100, 100), Offset(200, 200),
      Offset(300, 300)];
    expect(PerspectiveAspect.widthToHeight(corners, _image), isNull);
    expect(PerspectiveAspect.outputSize(corners, _image, 120, 80),
        const Size(120, 80));
  });
}
