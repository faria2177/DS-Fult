import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';

/// A scanned page normalized to a JPEG with dimensions for slide placement.
class PptxPageImage {
  const PptxPageImage(this.jpeg, this.width, this.height);

  final Uint8List jpeg;
  final int width;
  final int height;
}

/// A real Office OpenXML PowerPoint with one independent picture per slide.
/// Page contents remain image-backed; OCR text and layout are not reconstructed
/// into separate editable PowerPoint text objects.
class PptxExport {
  static const _templatePath = 'assets/pptx/blank_template.pptx';
  static const _slideWidth = 12191999;
  static const _slideHeight = 6858000;
  static const _slideMargin = 180000;

  static Future<File> createFile(ScanDocument document) async {
    if (document.pages.isEmpty) {
      throw const FormatException('This document has no pages.');
    }
    final pages = <PptxPageImage>[];
    for (final page in document.pages) {
      final source = img.decodeImage(await File(page.path).readAsBytes());
      if (source == null) {
        throw FormatException('Cannot decode scanned image: ${page.path}');
      }
      // Keep presentation files reasonably small without stretching the page.
      final scale = [1920 / source.width, 1440 / source.height, 1.0]
          .reduce((a, b) => a < b ? a : b);
      final resized = scale < 1
          ? img.copyResize(source,
              width: (source.width * scale).round(),
              height: (source.height * scale).round())
          : source;
      pages.add(PptxPageImage(
        Uint8List.fromList(img.encodeJpg(resized, quality: 88)),
        resized.width,
        resized.height,
      ));
    }
    final asset = await rootBundle.load(_templatePath);
    final template = asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes);
    final result = buildPptxBytes(template, pages);
    final folder = await getTemporaryDirectory();
    final filename = document.name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final file = File(p.join(folder.path,
        '${filename}_${DateTime.now().microsecondsSinceEpoch}.pptx'));
    await file.writeAsBytes(result, flush: true);
    return file;
  }

  static Future<void> shareFile(File file, String name) async {
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType:
          'application/vnd.openxmlformats-officedocument.presentationml.presentation')],
      subject: name,
    ));
  }

  /// Reuses a standards-compliant blank Office presentation skeleton; new
  /// slides get unique slide IDs, relationships and JPEG media parts.
  static Uint8List buildPptxBytes(Uint8List blankTemplate, List<PptxPageImage> pages) {
    if (pages.isEmpty) {
      throw const FormatException('At least one page is required.');
    }
    final template = ZipDecoder().decodeBytes(blankTemplate, verify: true);
    final files = <String, Uint8List>{};
    for (final entry in template.files) {
      if (entry.isFile) {
        final bytes = entry.readBytes();
        if (bytes == null) throw FormatException('Invalid template entry: ${entry.name}');
        files[entry.name] = bytes;
      }
    }
    String source(String name) {
      final bytes = files[name];
      if (bytes == null) throw FormatException('Missing template entry: $name');
      return utf8.decode(bytes);
    }
    void update(String name, String xml) => files[name] = Uint8List.fromList(utf8.encode(xml));

    final initialPresentation = source('ppt/presentation.xml');
    final firstSlideId = RegExp(r'<p:sldId id="(\d+)" r:id="rId(\d+)"/>')
        .firstMatch(initialPresentation);
    if (firstSlideId == null) throw const FormatException('PPTX template has no slide');
    final relationship = int.parse(firstSlideId.group(2)!);
    final ids = StringBuffer();
    for (var i = 0; i < pages.length; i++) {
      ids.write('<p:sldId id="${256 + i}" r:id="rId${relationship + i}"/>');
    }
    final presentation = initialPresentation.replaceFirst(
      RegExp(r'<p:sldIdLst>.*?</p:sldIdLst>', dotAll: true),
      '<p:sldIdLst>$ids</p:sldIdLst>',
    ).replaceFirst('type="screen4x3"', 'type="screen16x9"');
    update('ppt/presentation.xml', presentation);

    var presentationRels = source('ppt/_rels/presentation.xml.rels');
    var contentTypes = source('[Content_Types].xml');
    if (!contentTypes.contains('Extension="jpg"')) {
      contentTypes = contentTypes.replaceFirst('</Types>',
          '<Default Extension="jpg" ContentType="image/jpeg"/></Types>');
    }
    final blankSlide = source('ppt/slides/slide1.xml');
    final blankRelationships = source('ppt/slides/_rels/slide1.xml.rels');
    for (var i = 0; i < pages.length; i++) {
      final number = i + 1;
      final page = pages[i];
      if (page.width <= 0 || page.height <= 0 || page.jpeg.isEmpty) {
        throw FormatException('Invalid image for page $number');
      }
      final (x, y, w, h) = _contain(page.width, page.height);
      final picture = '<p:pic>'
          '<p:nvPicPr><p:cNvPr id="2" name="Scanned page $number"/>'
          '<p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>'
          '<p:blipFill><a:blip r:embed="rId2"/>'
          '<a:stretch><a:fillRect/></a:stretch></p:blipFill>'
          '<p:spPr><a:xfrm><a:off x="$x" y="$y"/>'
          '<a:ext cx="$w" cy="$h"/></a:xfrm>'
          '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>'
          '</p:pic>';
      update('ppt/slides/slide$number.xml',
          blankSlide.replaceFirst('</p:spTree>', '$picture</p:spTree>'));
      update('ppt/slides/_rels/slide$number.xml.rels',
          blankRelationships.replaceFirst('</Relationships>',
              '<Relationship Id="rId2" '
              'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
              'Target="../media/image$number.jpg"/></Relationships>'));
      files['ppt/media/image$number.jpg'] = page.jpeg;
      if (number > 1) {
        presentationRels = presentationRels.replaceFirst('</Relationships>',
            '<Relationship Id="rId${relationship + i}" '
            'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" '
            'Target="slides/slide$number.xml"/></Relationships>');
        contentTypes = contentTypes.replaceFirst('</Types>',
            '<Override PartName="/ppt/slides/slide$number.xml" '
            'ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>'
            '</Types>');
      }
    }
    update('ppt/_rels/presentation.xml.rels', presentationRels);
    update('[Content_Types].xml', contentTypes);
    final archive = Archive();
    for (final entry in files.entries) {
      archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
    }
    return ZipEncoder().encodeBytes(archive);
  }

  static (int, int, int, int) _contain(int width, int height) {
    final availableW = _slideWidth - 2 * _slideMargin;
    final availableH = _slideHeight - 2 * _slideMargin;
    final ratio = (availableW / width) < (availableH / height)
        ? availableW / width
        : availableH / height;
    final w = (width * ratio).round();
    final h = (height * ratio).round();
    return ((_slideWidth - w) ~/ 2, (_slideHeight - h) ~/ 2, w, h);
  }
}
