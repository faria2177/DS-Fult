import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../screens/gallery_import_review_screen.dart';
import '../screens/gallery_picker_screen.dart';
import 'gallery_asset_source.dart';
import 'image_processor.dart';

/// Import Images entry point shared by Scan, Home and Add page.
///
/// Opens the in-app "Select Photo" grid. If photo access is refused or the
/// photo library cannot be read on this device, it falls back to the system
/// photo picker followed by the older confirmation screen, so importing
/// keeps working either way. Returns null when the user backs out.
Future<GalleryImportResult?> pickAndImportFromGallery(
  BuildContext context, {
  required ImagePicker picker,
  int? limit,
  bool initialAutoCrop = true,
  ScanFilter initialFilter = ScanFilter.enhance,
  bool preferIdCardBounds = false,
}) async {
  Future<List<String>> pickWithSystem() async {
    if (limit == 1) {
      final photo = await picker.pickImage(source: ImageSource.gallery);
      return [if (photo != null) photo.path];
    }
    final photos = await picker.pickMultiImage(
        limit: limit, requestFullMetadata: false);
    return [for (final photo in photos) photo.path];
  }

  PhotoLibrarySource? source;
  try {
    source = await PhotoLibrarySource.open();
  } catch (error) {
    debugPrint('In-app gallery unavailable, using system picker: $error');
  }
  if (!context.mounted) return null;
  final navigator = Navigator.of(context);
  if (source != null) {
    final library = source;
    return navigator.push<GalleryImportResult>(MaterialPageRoute(
      builder: (_) => GalleryPickerScreen(
        source: library,
        maxSelection: limit,
        initialAutoCrop: initialAutoCrop,
        initialFilter: initialFilter,
        preferIdCardBounds: preferIdCardBounds,
        limitedAccess: library.limited,
        onAllowAll: PhotoLibrarySource.openAccessSettings,
        onBrowse: pickWithSystem,
      ),
    ));
  }
  final paths = await pickWithSystem();
  if (paths.isEmpty || !navigator.mounted) return null;
  return navigator.push<GalleryImportResult>(MaterialPageRoute(
    builder: (_) => GalleryImportReviewScreen(
      imagePaths: paths,
      initialAutoCrop: initialAutoCrop,
      initialFilter: initialFilter,
      preferIdCardBounds: preferIdCardBounds,
    ),
  ));
}
