import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:doclens/doclens.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Last-resort, fully offline outline for an imported photo of a *small*
/// document (ID card, bank card, passport photo, visiting card) lying on a
/// table, cloth or bed sheet.
///
/// The other still-image detectors look for strong rectangles and then
/// refuse anything below roughly a fifth of the photo, because a small
/// rectangle is usually a printed box *inside* a page. That safety rule
/// also rejects a genuinely small card on a desk, so such imports stayed
/// uncropped.
///
/// This detector answers a different question: "is there one object that
/// clearly differs from the surface it is lying on?" The surface colours are
/// learnt from a thin band around the photo frame, every pixel is compared
/// with them, and the largest separate object becomes the outline. A printed
/// box inside a page is never found: when the page reaches the photo edge
/// its paper is part of the learnt surface, and when the whole page is
/// visible the page itself is the larger object.
///
/// The object may touch at most one photo edge (a card pushed against the
/// frame). Results are rejected unless the object is solid, four-sided, has
/// surface colour on every free side and is not surrounded by plain white
/// paper. A rejection keeps the original, uncropped photo.
class BackgroundContrastContour {
  static const int _workingSide = 384;
  static const int _clusters = 6;

  static Future<ImageDetection?> detectFile(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      return await compute(_detectWorker, bytes);
    } catch (error) {
      debugPrint('Background-contrast contour unavailable: $error');
      return null;
    }
  }

  /// Pure and synchronous so tests can call it directly.
  static ImageDetection? detectBytes(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final source = img.bakeOrientation(decoded);
    if (source.width < 64 || source.height < 64) return null;
    final scale = math.min(1.0,
        _workingSide / math.max(source.width, source.height));
    final width = math.max(1, (source.width * scale).round());
    final height = math.max(1, (source.height * scale).round());
    if (width < 48 || height < 48) return null;
    final working = scale < 1
        // Averaging (not point sampling) so cloth and paper texture is
        // smoothed rather than aliased into false edges.
        ? img.copyResize(source, width: width, height: height,
            interpolation: img.Interpolation.average)
        : source;
    final quad = _detectRgb(_Frame.fromImage(working));
    if (quad == null) return null;
    return ImageDetection(
      quad: quad,
      imageSize: Size(source.width.toDouble(), source.height.toDouble()),
    );
  }

  static Quad? _detectRgb(_Frame frame) {
    final w = frame.width;
    final h = frame.height;
    final smooth = frame.blurred();
    final band = math.max(4, (.035 * math.min(w, h)).round());

    _Candidate? full;
    final candidates = <_Candidate>[];
    // Pass "null" needs the object fully inside the photo. Passes 0..3
    // (top, right, bottom, left) learn the surface from the other three
    // frame sides, so an object touching that one side can still be found.
    for (final skip in <int?>[null, 0, 1, 2, 3]) {
      final candidate = _pass(smooth, w, h, band, skip);
      if (candidate == null) continue;
      candidates.add(candidate);
      if (skip == null) full = candidate;
    }
    if (candidates.isEmpty) {
      _log('no separate object on a learnt background');
      return null;
    }
    var best = candidates.reduce((a, b) => b.area > a.area ? b : a);
    if (full != null && !identical(best, full)) {
      // A larger edge-touching outline replaces the fully enclosed one only
      // if it really is the same object seen whole (the enclosed pass lost
      // the part pressed against the frame).
      final inner = _raster(full.points, w, h);
      final outer = _raster(best.points, w, h);
      var innerCount = 0;
      var shared = 0;
      for (var i = 0; i < inner.length; i++) {
        if (inner[i] == 0) continue;
        innerCount++;
        if (outer[i] != 0) shared++;
      }
      if (shared / math.max(innerCount, 1) < .70 ||
          best.area < full.area * 1.15) {
        best = full;
      }
    }
    final p = best.points;
    return Quad(
      topLeft: Offset(p[0].x / w, p[0].y / h),
      topRight: Offset(p[1].x / w, p[1].y / h),
      bottomRight: Offset(p[2].x / w, p[2].y / h),
      bottomLeft: Offset(p[3].x / w, p[3].y / h),
    );
  }

  /// Four corners from a neural foreground map (see `SalientDocumentDetector`).
  ///
  /// [probability] is a [width]x[height] map (0..255) of "this pixel belongs
  /// to the main object" and [rgb] the matching thumbnail. The same corner
  /// fitting and safety checks as the colour-contrast path are applied, plus
  /// a confidence test, so a vague or non-rectangular answer is discarded.
  static Quad? quadFromSalientMask({
    required Uint8List probability,
    required Uint8List rgb,
    required int width,
    required int height,
    required double imageWidth,
    required double imageHeight,
  }) {
    final w = width, h = height, n = w * h;
    if (n == 0 || probability.length != n || rgb.length != n * 3) return null;
    var mask = Uint8List(n);
    for (var i = 0; i < n; i++) {
      mask[i] = probability[i] > 127 ? 1 : 0;
    }
    mask = _dilate(_erode(mask, w, h), w, h);

    // Largest object touching no photo edge, or exactly one.
    Uint8List? component;
    var componentCount = 0;
    for (final skip in <int?>[null, 0, 1, 2, 3]) {
      final candidate = _largestComponent(mask, w, h, skip);
      if (candidate == null) continue;
      var count = 0;
      for (final v in candidate) {
        count += v;
      }
      if (count > componentCount) {
        componentCount = count;
        component = candidate;
      }
    }
    if (component == null) {
      _log('model: no separate object');
      return null;
    }
    final filled = _fillHoles(component, w, h);
    final points = _fitQuad(filled, w, h);
    if (points == null) return null;
    var filledCount = 0;
    for (final v in filled) {
      filledCount += v;
    }
    final quadArea = _polygonArea(points);
    final area = quadArea / n;
    final solidity = filledCount / math.max(quadArea, 1);
    if (area < .03 || area > .92) {
      _log('model: coverage ${area.toStringAsFixed(3)}');
      return null;
    }
    if (solidity < .93 || solidity > 1.08) {
      _log('model: solidity ${solidity.toStringAsFixed(2)}');
      return null;
    }
    // The network must be sure about the object's interior, and must not
    // see much else in the photo.
    var core = filled;
    var grown = filled;
    for (var i = 0; i < 3; i++) {
      core = _erode(core, w, h);
      grown = _dilate(grown, w, h);
    }
    var coreCount = 0, coreSum = 0, stray = 0;
    for (var i = 0; i < n; i++) {
      if (core[i] != 0) {
        coreCount++;
        coreSum += probability[i];
      } else if (grown[i] == 0 && probability[i] > 127) {
        stray++;
      }
    }
    final confidence = coreCount == 0 ? 0.0 : coreSum / (coreCount * 255);
    if (confidence < .90) {
      _log('model: unsure (${confidence.toStringAsFixed(2)})');
      return null;
    }
    if (stray / math.max(filledCount, 1) > .25) {
      _log('model: several objects');
      return null;
    }
    // Angles are judged in real image proportions, not the square map.
    final sx = imageWidth / w, sy = imageHeight / h;
    if (!_documentLike(
        [for (final p in points) math.Point(p.x * sx, p.y * sy)])) {
      _log('model: not a four-sided document shape');
      return null;
    }
    final r = Float32List(n), g = Float32List(n), b = Float32List(n);
    for (var i = 0; i < n; i++) {
      r[i] = rgb[i * 3].toDouble();
      g[i] = rgb[i * 3 + 1].toDouble();
      b[i] = rgb[i * 3 + 2].toDouble();
    }
    if (_paperAround(points, _Frame(w, h, r, g, b), w, h) > .55) {
      _log('model: object is enclosed by white paper (printed box)');
      return null;
    }
    return Quad(
      topLeft: Offset(points[0].x / w, points[0].y / h),
      topRight: Offset(points[1].x / w, points[1].y / h),
      bottomRight: Offset(points[2].x / w, points[2].y / h),
      bottomLeft: Offset(points[3].x / w, points[3].y / h),
    );
  }

  static _Candidate? _pass(_Frame rgb, int w, int h, int band, int? skip) {
    final n = w * h;
    bool inBand(int x, int y, int side) {
      switch (side) {
        case 0:
          return y < band;
        case 1:
          return x >= w - band;
        case 2:
          return y >= h - band;
        default:
          return x < band;
      }
    }

    final borderIndexes = <int>[];
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        for (var side = 0; side < 4; side++) {
          if (side != skip && inBand(x, y, side)) {
            borderIndexes.add(y * w + x);
            break;
          }
        }
      }
    }
    if (borderIndexes.length < _clusters * 4) return null;

    final centres = _kMeans(rgb, borderIndexes);
    final distance = _distanceMap(rgb, centres);
    final borderDistances = Float64List(borderIndexes.length);
    for (var i = 0; i < borderIndexes.length; i++) {
      borderDistances[i] = distance[borderIndexes[i]];
    }
    borderDistances.sort();
    final threshold = math.max(22.0,
        borderDistances[(.985 * (borderDistances.length - 1)).floor()] * 1.3);
    // The frame itself is too varied to describe as one surface.
    if (threshold > 70) {
      _log('pass ${skip ?? 'enclosed'}: surface too varied');
      return null;
    }

    var mask = Uint8List(n);
    for (var i = 0; i < n; i++) {
      mask[i] = distance[i] > threshold ? 1 : 0;
    }
    // Close small gaps (glare, text) then remove specks (cloth texture).
    mask = _dilate(_dilate(mask, w, h), w, h);
    mask = _erode(_erode(mask, w, h), w, h);
    mask = _dilate(_erode(mask, w, h), w, h);

    final component = _largestComponent(mask, w, h, skip);
    if (component == null) return null;
    final filled = _fillHoles(component, w, h);
    final points = _fitQuad(filled, w, h);
    if (points == null) return null;

    final quadArea = _polygonArea(points);
    var filledCount = 0;
    for (final v in filled) {
      filledCount += v;
    }
    final area = quadArea / (w * h);
    final solidity = filledCount / math.max(quadArea, 1);
    final label = 'pass ${skip ?? 'enclosed'}';
    if (area < .03 || area > .85) {
      _log('$label: coverage ${area.toStringAsFixed(3)}');
      return null;
    }
    if (solidity < .93 || solidity > 1.10) {
      _log('$label: solidity ${solidity.toStringAsFixed(2)}');
      return null;
    }
    if (!_documentLike(points)) {
      _log('$label: not a four-sided document shape');
      return null;
    }
    if (!_surfaceOnEverySide(points, filled, distance, threshold, w, h,
        skip)) {
      _log('$label: an edge is not surrounded by the surface');
      return null;
    }
    if (_paperAround(points, rgb, w, h) > .55) {
      _log('$label: object is enclosed by white paper (printed box)');
      return null;
    }
    return _Candidate(points, area);
  }

  static List<Float64List> _kMeans(_Frame rgb, List<int> samples) {
    final count = samples.length;
    double sq(int index, Float64List c) {
      final dr = rgb.r[index] - c[0];
      final dg = rgb.g[index] - c[1];
      final db = rgb.b[index] - c[2];
      return dr * dr + dg * dg + db * db;
    }

    var mr = 0.0, mg = 0.0, mb = 0.0;
    for (final i in samples) {
      mr += rgb.r[i];
      mg += rgb.g[i];
      mb += rgb.b[i];
    }
    final centres = <Float64List>[
      Float64List.fromList([mr / count, mg / count, mb / count]),
    ];
    // Deterministic farthest-point start: rare frame colours (yellow
    // stitching, a dark fold) get their own centre instead of being averaged
    // away.
    final nearest = Float64List(count);
    for (var s = 0; s < count; s++) {
      nearest[s] = sq(samples[s], centres[0]);
    }
    while (centres.length < _clusters) {
      var far = 0;
      for (var s = 1; s < count; s++) {
        if (nearest[s] > nearest[far]) far = s;
      }
      final i = samples[far];
      final c = Float64List.fromList(
          [rgb.r[i].toDouble(), rgb.g[i].toDouble(), rgb.b[i].toDouble()]);
      centres.add(c);
      for (var s = 0; s < count; s++) {
        nearest[s] = math.min(nearest[s], sq(samples[s], c));
      }
    }
    final labels = Int32List(count);
    for (var iteration = 0; iteration < 12; iteration++) {
      for (var s = 0; s < count; s++) {
        var bestK = 0;
        var bestD = double.infinity;
        for (var k = 0; k < centres.length; k++) {
          final d = sq(samples[s], centres[k]);
          if (d < bestD) {
            bestD = d;
            bestK = k;
          }
        }
        labels[s] = bestK;
      }
      for (var k = 0; k < centres.length; k++) {
        var sr = 0.0, sg = 0.0, sb = 0.0;
        var members = 0;
        for (var s = 0; s < count; s++) {
          if (labels[s] != k) continue;
          final i = samples[s];
          sr += rgb.r[i];
          sg += rgb.g[i];
          sb += rgb.b[i];
          members++;
        }
        if (members > 0) {
          centres[k][0] = sr / members;
          centres[k][1] = sg / members;
          centres[k][2] = sb / members;
        }
      }
    }
    return centres;
  }

  /// Colour difference from the nearest surface colour. Hue counts fully;
  /// brightness counts when the pixel is brighter than the surface, but a
  /// pixel up to ~45% darker is treated as the surface in shadow. This keeps
  /// a card's cast shadow out of the outline.
  static Float32List _distanceMap(_Frame rgb, List<Float64List> centres) {
    final n = rgb.r.length;
    final out = Float32List(n);
    final cr = <double>[], cg = <double>[], cl = <double>[];
    for (final c in centres) {
      final sum = c[0] + c[1] + c[2] + 30.0;
      cr.add(c[0] / sum);
      cg.add(c[1] / sum);
      cl.add((c[0] + c[1] + c[2]) / 3);
    }
    for (var i = 0; i < n; i++) {
      final r = rgb.r[i], g = rgb.g[i], b = rgb.b[i];
      final sum = r + g + b + 30.0;
      final pr = r / sum, pg = g / sum, light = (r + g + b) / 3;
      var best = double.infinity;
      for (var k = 0; k < cr.length; k++) {
        final chroma = math.sqrt((pr - cr[k]) * (pr - cr[k]) +
                (pg - cg[k]) * (pg - cg[k])) *
            420.0;
        final up = math.max(0.0, light - cl[k]);
        final down = math.max(0.0, cl[k] * .55 - light);
        final d = math.sqrt(chroma * chroma + up * up + down * down);
        if (d < best) best = d;
      }
      out[i] = best;
    }
    return out;
  }

  /// 3x3 dilation; pixels outside the photo count as background.
  static Uint8List _dilate(Uint8List m, int w, int h) {
    final out = Uint8List(m.length);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var on = 0;
        for (var dy = -1; dy <= 1 && on == 0; dy++) {
          final yy = y + dy;
          if (yy < 0 || yy >= h) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final xx = x + dx;
            if (xx < 0 || xx >= w) continue;
            if (m[yy * w + xx] != 0) {
              on = 1;
              break;
            }
          }
        }
        out[y * w + x] = on;
      }
    }
    return out;
  }

  /// 3x3 erosion; pixels outside the photo count as foreground, so an
  /// object pressed against the frame is not eaten away from that side.
  static Uint8List _erode(Uint8List m, int w, int h) {
    final out = Uint8List(m.length);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var on = 1;
        for (var dy = -1; dy <= 1 && on == 1; dy++) {
          final yy = y + dy;
          if (yy < 0 || yy >= h) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final xx = x + dx;
            if (xx < 0 || xx >= w) continue;
            if (m[yy * w + xx] == 0) {
              on = 0;
              break;
            }
          }
        }
        out[y * w + x] = on;
      }
    }
    return out;
  }

  /// Largest 4-connected object that touches no photo edge, or only the
  /// [skip] edge (and then must touch it).
  static Uint8List? _largestComponent(Uint8List m, int w, int h, int? skip) {
    final labels = Int32List(m.length);
    final queue = Int32List(m.length);
    var nextLabel = 0;
    var bestLabel = 0;
    var bestCount = 0;
    final minimum = .02 * w * h;
    for (var start = 0; start < m.length; start++) {
      if (m[start] == 0 || labels[start] != 0) continue;
      nextLabel++;
      var head = 0, tail = 0;
      queue[tail++] = start;
      labels[start] = nextLabel;
      var count = 0;
      final touches = <int>[0, 0, 0, 0];
      while (head < tail) {
        final index = queue[head++];
        final x = index % w;
        final y = index ~/ w;
        count++;
        if (y == 0) touches[0]++;
        if (x == w - 1) touches[1]++;
        if (y == h - 1) touches[2]++;
        if (x == 0) touches[3]++;
        void visit(int nx, int ny) {
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) return;
          final ni = ny * w + nx;
          if (m[ni] == 0 || labels[ni] != 0) return;
          labels[ni] = nextLabel;
          queue[tail++] = ni;
        }

        visit(x, y - 1);
        visit(x, y + 1);
        visit(x - 1, y);
        visit(x + 1, y);
      }
      if (count <= minimum) continue;
      var allowed = true;
      for (var side = 0; side < 4; side++) {
        if (touches[side] > 0 && side != skip) allowed = false;
      }
      if (skip != null && touches[skip] == 0) allowed = false;
      if (allowed && count > bestCount) {
        bestCount = count;
        bestLabel = nextLabel;
      }
    }
    if (bestLabel == 0) return null;
    final out = Uint8List(m.length);
    for (var i = 0; i < m.length; i++) {
      if (labels[i] == bestLabel) out[i] = 1;
    }
    return out;
  }

  /// Text, a face or a chip inside the card become part of the object.
  static Uint8List _fillHoles(Uint8List component, int w, int h) {
    final reached = Uint8List(component.length);
    final queue = Int32List(component.length);
    var head = 0, tail = 0;
    void seed(int x, int y) {
      final i = y * w + x;
      if (component[i] != 0 || reached[i] != 0) return;
      reached[i] = 1;
      queue[tail++] = i;
    }

    for (var x = 0; x < w; x++) {
      seed(x, 0);
      seed(x, h - 1);
    }
    for (var y = 0; y < h; y++) {
      seed(0, y);
      seed(w - 1, y);
    }
    while (head < tail) {
      final index = queue[head++];
      final x = index % w;
      final y = index ~/ w;
      if (y > 0) seed(x, y - 1);
      if (y < h - 1) seed(x, y + 1);
      if (x > 0) seed(x - 1, y);
      if (x < w - 1) seed(x + 1, y);
    }
    final filled = Uint8List(component.length);
    for (var i = 0; i < filled.length; i++) {
      filled[i] = reached[i] == 0 ? 1 : 0;
    }
    return filled;
  }

  /// Four corners of the object: the largest quadrilateral on its convex
  /// hull gives the sides, and a straight line through each side's middle
  /// boundary pixels gives exact corners even for rounded card corners.
  static List<math.Point<double>>? _fitQuad(Uint8List filled, int w, int h) {
    final edge = _erode(filled, w, h);
    final boundary = <math.Point<double>>[];
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (filled[i] != 0 && edge[i] == 0) {
          boundary.add(math.Point(x + .5, y + .5));
        }
      }
    }
    if (boundary.length < 12) return null;
    final hull = _convexHull(boundary);
    if (hull.length < 4) return null;
    final corners = _largestInscribedQuad(hull);
    if (corners == null) return null;

    final lines = <_Line>[];
    for (var s = 0; s < 4; s++) {
      final a = corners[s];
      final b = corners[(s + 1) % 4];
      final dx = b.x - a.x, dy = b.y - a.y;
      final length = math.sqrt(dx * dx + dy * dy);
      if (length < 4) return null;
      final ux = dx / length, uy = dy / length;
      final nx = -uy, ny = ux;
      final band = math.max(2.5, .04 * length);
      final selected = <math.Point<double>>[];
      for (final p in boundary) {
        final rx = p.x - a.x, ry = p.y - a.y;
        final t = rx * ux + ry * uy;
        final off = rx * nx + ry * ny;
        if (t > .15 * length && t < .85 * length && off.abs() < band) {
          selected.add(p);
        }
      }
      lines.add(selected.length < 6
          ? _Line(a.x, a.y, ux, uy)
          : _Line.fit(selected));
    }
    final result = <math.Point<double>>[];
    for (var s = 0; s < 4; s++) {
      final p = lines[(s + 3) % 4].intersect(lines[s]);
      if (p == null) return null;
      result.add(math.Point(math.min(math.max(p.x, 0.0), w.toDouble()),
          math.min(math.max(p.y, 0.0), h.toDouble())));
    }
    return _orderClockwise(result);
  }

  static List<math.Point<double>> _convexHull(List<math.Point<double>> input) {
    final points = input.toSet().toList()
      ..sort((a, b) => a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
    if (points.length < 3) return points;
    double cross(math.Point<double> o, math.Point<double> a,
            math.Point<double> b) =>
        (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
    final lower = <math.Point<double>>[];
    for (final p in points) {
      while (lower.length >= 2 &&
          cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }
    final upper = <math.Point<double>>[];
    for (final p in points.reversed) {
      while (upper.length >= 2 &&
          cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }
    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }

  static List<math.Point<double>>? _largestInscribedQuad(
      List<math.Point<double>> hull) {
    final n = hull.length;
    double triangle(int a, int b, int c) =>
        ((hull[b].x - hull[a].x) * (hull[c].y - hull[a].y) -
                (hull[b].y - hull[a].y) * (hull[c].x - hull[a].x))
            .abs() /
        2;
    var bestArea = 0.0;
    List<int>? best;
    for (var i = 0; i < n; i++) {
      for (var k = i + 2; k < n; k++) {
        if (n - (k - i) < 2) continue;
        var bj = i + 1;
        var bjArea = -1.0;
        for (var j = i + 1; j < k; j++) {
          final t = triangle(i, j, k);
          if (t > bjArea) {
            bjArea = t;
            bj = j;
          }
        }
        var bl = (k + 1) % n;
        var blArea = -1.0;
        for (var l = k + 1; l < i + n; l++) {
          final t = triangle(k, l % n, i);
          if (t > blArea) {
            blArea = t;
            bl = l % n;
          }
        }
        final area = bjArea + blArea;
        if (area > bestArea) {
          bestArea = area;
          best = [i, bj, k, bl];
        }
      }
    }
    return best?.map((index) => hull[index]).toList();
  }

  /// Top-left, top-right, bottom-right, bottom-left (clockwise on screen).
  static List<math.Point<double>> _orderClockwise(
      List<math.Point<double>> points) {
    final cx = points.fold<double>(0, (s, p) => s + p.x) / points.length;
    final cy = points.fold<double>(0, (s, p) => s + p.y) / points.length;
    final sorted = List.of(points)
      ..sort((a, b) => math
          .atan2(a.y - cy, a.x - cx)
          .compareTo(math.atan2(b.y - cy, b.x - cx)));
    var first = 0;
    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i].x + sorted[i].y < sorted[first].x + sorted[first].y) {
        first = i;
      }
    }
    return [...sorted.sublist(first), ...sorted.sublist(0, first)];
  }

  static double _polygonArea(List<math.Point<double>> p) {
    var sum = 0.0;
    for (var i = 0; i < p.length; i++) {
      final a = p[i];
      final b = p[(i + 1) % p.length];
      sum += a.x * b.y - b.x * a.y;
    }
    return sum.abs() / 2;
  }

  /// Corners between 50° and 130°, opposite sides of comparable length.
  static bool _documentLike(List<math.Point<double>> p) {
    for (var i = 0; i < 4; i++) {
      final a = p[(i + 3) % 4], b = p[i], c = p[(i + 1) % 4];
      final v1x = a.x - b.x, v1y = a.y - b.y;
      final v2x = c.x - b.x, v2y = c.y - b.y;
      final l1 = math.sqrt(v1x * v1x + v1y * v1y);
      final l2 = math.sqrt(v2x * v2x + v2y * v2y);
      if (l1 == 0 || l2 == 0) return false;
      final cosine =
          math.min(1.0, math.max(-1.0, (v1x * v2x + v1y * v2y) / (l1 * l2)));
      final angle = math.acos(cosine) * 180 / math.pi;
      if (angle < 50 || angle > 130) return false;
    }
    double side(int i) => p[i].distanceTo(p[(i + 1) % 4]);
    final top = side(0), right = side(1), bottom = side(2), left = side(3);
    return math.min(top, bottom) >= .55 * math.max(top, bottom) &&
        math.min(left, right) >= .55 * math.max(left, right);
  }

  /// Just inside each side must be the object; just outside must be mostly
  /// the learnt surface. A side lying on the skipped photo edge is exempt.
  static bool _surfaceOnEverySide(List<math.Point<double>> q,
      Uint8List filled, Float32List distance, double threshold, int w, int h,
      int? skip) {
    for (var s = 0; s < 4; s++) {
      final a = q[s], b = q[(s + 1) % 4];
      if (skip != null && _photoEdgeOf(a, b, w, h) == skip) continue;
      final dx = b.x - a.x, dy = b.y - a.y;
      final length = math.sqrt(dx * dx + dy * dy);
      if (length == 0) return false;
      final ux = dx / length, uy = dy / length;
      // Outward normal for clockwise screen order.
      final nx = uy, ny = -ux;
      var inside = 0, insideOn = 0, outside = 0, outsideOn = 0;
      for (var step = 0; step < 24; step++) {
        final f = .12 + (.88 - .12) * step / 23;
        final px = a.x + dx * f, py = a.y + dy * f;
        for (final sign in const [-1, 1]) {
          for (final offset in const [3, 5]) {
            final xi = (px + nx * offset * sign).toInt();
            final yi = (py + ny * offset * sign).toInt();
            if (xi < 0 || yi < 0 || xi >= w || yi >= h) continue;
            final i = yi * w + xi;
            if (sign < 0) {
              inside++;
              if (filled[i] != 0) insideOn++;
            } else {
              outside++;
              if (distance[i] > threshold) outsideOn++;
            }
          }
        }
      }
      if (outside < 10) continue;
      if (inside > 0 && insideOn / inside < .6) return false;
      if (outsideOn / outside > .35) return false;
    }
    return true;
  }

  static int _photoEdgeOf(
      math.Point<double> a, math.Point<double> b, int w, int h) {
    const tolerance = 3;
    final mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2;
    if (my <= tolerance) return 0;
    if (mx >= w - tolerance) return 1;
    if (my >= h - tolerance) return 2;
    if (mx <= tolerance) return 3;
    return -1;
  }

  /// Share of plain near-white paper in a thin ring around the outline.
  /// A coloured block printed on a page is ringed by paper; a card on a
  /// table or cloth is not.
  static double _paperAround(
      List<math.Point<double>> q, _Frame rgb, int w, int h) {
    final outer = _raster(_scaled(q, 1.10), w, h);
    final inner = _raster(_scaled(q, 1.03), w, h);
    var ring = 0, paper = 0;
    for (var i = 0; i < outer.length; i++) {
      if (outer[i] == 0 || inner[i] != 0) continue;
      ring++;
      final r = rgb.r[i], g = rgb.g[i], b = rgb.b[i];
      final light = (r + g + b) / 3;
      final chroma = math.max(r, math.max(g, b)) - math.min(r, math.min(g, b));
      if (light > 165 && chroma < 28) paper++;
    }
    return ring < 20 ? 0 : paper / ring;
  }

  static List<math.Point<double>> _scaled(
      List<math.Point<double>> q, double factor) {
    final cx = q.fold<double>(0, (s, p) => s + p.x) / q.length;
    final cy = q.fold<double>(0, (s, p) => s + p.y) / q.length;
    return [
      for (final p in q)
        math.Point(cx + (p.x - cx) * factor, cy + (p.y - cy) * factor),
    ];
  }

  static Uint8List _raster(List<math.Point<double>> q, int w, int h) {
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      final py = y + .5;
      for (var x = 0; x < w; x++) {
        final px = x + .5;
        var inside = true;
        for (var i = 0; i < 4 && inside; i++) {
          final a = q[i], b = q[(i + 1) % 4];
          if ((b.x - a.x) * (py - a.y) - (b.y - a.y) * (px - a.x) < 0) {
            inside = false;
          }
        }
        if (inside) out[y * w + x] = 1;
      }
    }
    return out;
  }

  static void _log(String message) {
    if (kDebugMode) debugPrint('[AutoCrop] background contour: $message');
  }
}

ImageDetection? _detectWorker(Uint8List bytes) =>
    BackgroundContrastContour.detectBytes(bytes);

class _Candidate {
  _Candidate(this.points, this.area);

  final List<math.Point<double>> points;
  final double area;
}

class _Line {
  _Line(this.x, this.y, this.dx, this.dy);

  /// Least-squares line through [points] (principal direction).
  factory _Line.fit(List<math.Point<double>> points) {
    var mx = 0.0, my = 0.0;
    for (final p in points) {
      mx += p.x;
      my += p.y;
    }
    mx /= points.length;
    my /= points.length;
    var sxx = 0.0, syy = 0.0, sxy = 0.0;
    for (final p in points) {
      final dx = p.x - mx, dy = p.y - my;
      sxx += dx * dx;
      syy += dy * dy;
      sxy += dx * dy;
    }
    final angle = .5 * math.atan2(2 * sxy, sxx - syy);
    return _Line(mx, my, math.cos(angle), math.sin(angle));
  }

  final double x, y, dx, dy;

  math.Point<double>? intersect(_Line other) {
    final denominator = dx * other.dy - dy * other.dx;
    if (denominator.abs() < 1e-6) return null;
    final t = ((other.x - x) * other.dy - (other.y - y) * other.dx) /
        denominator;
    return math.Point(x + t * dx, y + t * dy);
  }
}

/// Working-resolution RGB planes.
class _Frame {
  _Frame(this.width, this.height, this.r, this.g, this.b);

  factory _Frame.fromImage(img.Image image) {
    final w = image.width, h = image.height;
    final r = Float32List(w * h), g = Float32List(w * h), b = Float32List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final pixel = image.getPixel(x, y);
        final i = y * w + x;
        r[i] = pixel.r.toDouble();
        g[i] = pixel.g.toDouble();
        b[i] = pixel.b.toDouble();
      }
    }
    return _Frame(w, h, r, g, b);
  }

  final int width, height;
  final Float32List r, g, b;

  /// Two 3x3 box blurs (edge-clamped): suppresses JPEG and cloth speckle
  /// without erasing a thin white photo margin.
  _Frame blurred() {
    Float32List pass(Float32List input) {
      var current = input;
      for (var round = 0; round < 2; round++) {
        final horizontal = Float32List(current.length);
        for (var y = 0; y < height; y++) {
          for (var x = 0; x < width; x++) {
            final left = x > 0 ? x - 1 : 0;
            final right = x < width - 1 ? x + 1 : width - 1;
            horizontal[y * width + x] = (current[y * width + left] +
                    current[y * width + x] +
                    current[y * width + right]) /
                3;
          }
        }
        final vertical = Float32List(current.length);
        for (var y = 0; y < height; y++) {
          final up = y > 0 ? y - 1 : 0;
          final down = y < height - 1 ? y + 1 : height - 1;
          for (var x = 0; x < width; x++) {
            vertical[y * width + x] = (horizontal[up * width + x] +
                    horizontal[y * width + x] +
                    horizontal[down * width + x]) /
                3;
          }
        }
        current = vertical;
      }
      return current;
    }

    return _Frame(width, height, pass(r), pass(g), pass(b));
  }
}
