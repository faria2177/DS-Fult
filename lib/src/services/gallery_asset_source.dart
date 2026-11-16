import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

/// The photos shown by the in-app "Select Photo" grid, newest first.
///
/// Kept abstract so the screen can be widget-tested without the platform
/// photo library.
abstract class GalleryAssetSource {
  /// Number of photos available.
  int get count;

  /// Small square preview for the grid, or null when it cannot be read.
  Future<Uint8List?> thumbnail(int index);

  /// Path of a readable full-resolution copy, or null when unavailable.
  Future<String?> filePath(int index);
}

/// The device photo library, read through MediaStore.
class PhotoLibrarySource implements GalleryAssetSource {
  PhotoLibrarySource._(this._album, this.count);

  static const _pageSize = 90;

  final AssetPathEntity _album;
  final Map<int, Future<List<AssetEntity>>> _pages = {};

  @override
  final int count;

  /// Asks for photo access and opens the "all photos" album. Returns null
  /// when access is refused or the library is empty, so the caller can fall
  /// back to the system photo picker.
  static Future<PhotoLibrarySource?> open() async {
    final permission = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.image,
          mediaLocation: false,
        ),
      ),
    );
    if (!permission.hasAccess) return null;
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
    );
    if (albums.isEmpty) return null;
    final total = await albums.first.assetCountAsync;
    if (total <= 0) return null;
    return PhotoLibrarySource._(albums.first, total);
  }

  Future<AssetEntity?> _asset(int index) async {
    if (index < 0 || index >= count) return null;
    final page = index ~/ _pageSize;
    final assets = await _pages.putIfAbsent(page,
        () => _album.getAssetListPaged(page: page, size: _pageSize));
    final offset = index - page * _pageSize;
    return offset < assets.length ? assets[offset] : null;
  }

  @override
  Future<Uint8List?> thumbnail(int index) async {
    final asset = await _asset(index);
    if (asset == null) return null;
    return asset.thumbnailDataWithSize(const ThumbnailSize.square(256));
  }

  @override
  Future<String?> filePath(int index) async {
    final asset = await _asset(index);
    if (asset == null) return null;
    final file = await asset.file ?? await asset.originFile;
    return file?.path;
  }
}
