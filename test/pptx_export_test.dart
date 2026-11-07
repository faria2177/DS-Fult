import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:docscanner/src/services/pptx_export.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PowerPoint export creates separate image-backed slides', () async {
    final original = await rootBundle.load('assets/pptx/blank_template.pptx');
    final template = original.buffer.asUint8List(
        original.offsetInBytes, original.lengthInBytes);
    final sample = img.Image(width: 200, height: 100);
    img.fill(sample, color: img.ColorRgb8(255, 255, 255));
    final jpeg = Uint8List.fromList(img.encodeJpg(sample));

    final generated = PptxExport.buildPptxBytes(template, [
      PptxPageImage(jpeg, 200, 100),
      PptxPageImage(jpeg, 100, 200),
    ]);
    final zip = ZipDecoder().decodeBytes(generated, verify: true);
    String xml(String path) => utf8.decode(zip.findFile(path)!.readBytes()!);

    expect(zip.findFile('ppt/media/image1.jpg')!.readBytes(), isNotEmpty);
    expect(zip.findFile('ppt/media/image2.jpg')!.readBytes(), isNotEmpty);
    expect(zip.findFile('ppt/slideMasters/slideMaster1.xml'), isNotNull);
    expect(zip.findFile('ppt/theme/theme1.xml'), isNotNull);
    expect(xml('ppt/presentation.xml'), contains('r:id="rId7"'));
    expect(xml('ppt/presentation.xml'), contains('r:id="rId8"'));
    expect(xml('ppt/presentation.xml'), contains('type="screen16x9"'));
    expect(xml('ppt/_rels/presentation.xml.rels'), contains('Target="slides/slide2.xml"'));
    expect(xml('[Content_Types].xml'), contains('/ppt/slides/slide2.xml'));
    expect(xml('ppt/slides/slide1.xml'), contains('Scanned page 1'));
    expect(xml('ppt/slides/slide2.xml'), contains('Scanned page 2'));
    expect(xml('ppt/slides/slide2.xml'), contains('<p:pic>'));
    expect(xml('ppt/slides/_rels/slide2.xml.rels'),
        contains('Target="../media/image2.jpg"'));
  });

  test('PowerPoint requires pages', () async {
    final original = await rootBundle.load('assets/pptx/blank_template.pptx');
    final template = original.buffer.asUint8List(
        original.offsetInBytes, original.lengthInBytes);
    expect(() => PptxExport.buildPptxBytes(template, const []),
        throwsFormatException);
  });
}
