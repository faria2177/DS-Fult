import 'dart:typed_data';

import 'package:docscanner/src/services/id_card_page_composer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _solid(int red, int green, int blue) {
  final card = img.Image(width: 320, height: 200);
  img.fill(card, color: img.ColorRgb8(red, green, blue));
  return Uint8List.fromList(img.encodeJpg(card));
}

void main() {
  test('Front and Back are two regions of one A4 image', () {
    final output = IdCardPageComposer.composeSync((
      sides: [_solid(240, 20, 20), _solid(20, 20, 240)],
      compact: false,
    ));
    final page = img.decodeImage(output)!;
    expect(page.width, IdCardPageComposer.pageWidth);
    expect(page.height, IdCardPageComposer.pageHeight);
    final paper = page.getPixel(10, 10);
    expect(paper.r, greaterThan(245));
    final front = page.getPixel(620, 565);
    expect(front.r, greaterThan(180));
    expect(front.b, lessThan(80));
    final back = page.getPixel(620, 1190);
    expect(back.b, greaterThan(180));
    expect(back.r, lessThan(80));
  });

  test('Compact template keeps both card sides visible', () {
    final output = IdCardPageComposer.composeSync((
      sides: [_solid(200, 50, 30), _solid(30, 50, 200)],
      compact: true,
    ));
    final page = img.decodeImage(output)!;
    expect(page.getPixel(620, 680).r, greaterThan(150));
    expect(page.getPixel(620, 1080).b, greaterThan(150));
  });

  test('Card copy is printed at approximately physical ID-1 scale on A4', () {
    final output = IdCardPageComposer.composeSync((
      sides: [_solid(240, 20, 20), _solid(20, 20, 240)],
      compact: false,
    ));
    final page = img.decodeImage(output)!;
    // A4 is 210 mm wide; a typical ID-1 card is 85.6 mm wide.
    // A slight oversize margin is allowed, but it must not fill the page.
    expect(page.getPixel(620, 565).r, greaterThan(180));
    expect(page.getPixel(310, 565).r, greaterThan(240));
    expect(page.getPixel(930, 565).r, greaterThan(240));
  });

  test('Saving only Front or only Back cannot make a completed card', () {
    expect(() => IdCardPageComposer.composeSync((
      sides: [_solid(200, 20, 20)], compact: false,
    )), throwsArgumentError);
  });
  test('Reference layout places equal-size Front above Back on portrait A4', () {
    expect(IdCardPageComposer.pageWidth, lessThan(IdCardPageComposer.pageHeight));
    final centers = IdCardPageComposer.cardCenterFractions();
    expect(centers[0], closeTo(.322, .002));
    expect(centers[1], closeTo(.679, .002));
    expect(IdCardPageComposer.cardWidthFraction(), closeTo(.484, .002));
    expect(IdCardPageComposer.cardHeightFraction(), closeTo(.217, .002));
    final compact = IdCardPageComposer.cardCenterFractions(compact: true);
    expect(compact[0], lessThan(compact[1]));
  });

  test('Portrait camera capture is oriented horizontally on A4', () {
    // The source may be an otherwise correct card captured sideways by
    // CameraX, or an old gallery JPG whose EXIF orientation is already baked.
    final sideways = img.Image(width: 200, height: 320);
    img.fill(sideways, color: img.ColorRgb8(230, 40, 35));
    final source = Uint8List.fromList(img.encodePng(sideways));
    final output = IdCardPageComposer.composeSync((
      sides: [source, _solid(30, 40, 230)],
      compact: false,
    ));
    final page = img.decodeImage(output)!;
    // With a landscape placement the card reaches well beyond x=425.
    // Before the fix a portrait card was only about 237 pixels wide.
    expect(page.getPixel(425, 565).r, greaterThan(180));
    expect(page.getPixel(820, 565).r, greaterThan(180));
    expect(page.getPixel(300, 565).r, greaterThan(245));
    expect(page.getPixel(620, 1190).b, greaterThan(180));
    // Original bytes remain unchanged; only the A4 print copy rotates.
    final original = img.decodeImage(source)!;
    expect(original.width, 200);
    expect(original.height, 320);
  });

}
