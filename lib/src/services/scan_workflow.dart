import 'document_edges.dart';

/// One consistent state contract for camera stills, gallery photos and
/// imported images. The scan never overwrites a source photograph.
enum ScanBoundaryState {
  /// A validated outer boundary was perspective-corrected.
  autoCropped,
  /// The user accepted an edited four-corner crop.
  manuallyCorrected,
  /// No trustworthy outside boundary was found. Keep original intact.
  needsCornerReview,
  /// Auto Crop was explicitly disabled, so the original is intentional.
  original,
}

class ScanWorkflowPage {
  const ScanWorkflowPage({
    required this.sourcePath,
    required this.outputPath,
    required this.boundary,
  });

  final String sourcePath;
  final String outputPath;
  final ScanBoundaryState boundary;

  bool get needsReview => boundary == ScanBoundaryState.needsCornerReview;

  /// Strong document-only colour filters must not bleach an uncut backdrop.
  bool get isConfirmedCrop =>
      boundary == ScanBoundaryState.autoCropped ||
      boundary == ScanBoundaryState.manuallyCorrected;

  ScanWorkflowPage manuallyCorrected(String path) {
    if (path.isEmpty) throw ArgumentError.value(path, 'path');
    return ScanWorkflowPage(
      sourcePath: sourcePath,
      outputPath: path,
      boundary: ScanBoundaryState.manuallyCorrected,
    );
  }
}

class ScanWorkflowBatch {
  ScanWorkflowBatch._(List<ScanWorkflowPage> pages)
      : pages = List<ScanWorkflowPage>.unmodifiable(pages);

  final List<ScanWorkflowPage> pages;

  factory ScanWorkflowBatch.fromCropResult(
    List<String> sourcePaths,
    AutoCropBatch crop, {
    required bool autoCropEnabled,
  }) {
    if (crop.paths.length != sourcePaths.length) {
      throw ArgumentError('One crop result is required for every source page.');
    }
    final failed = crop.failedIndexes.toSet();
    return ScanWorkflowBatch._([
      for (var i = 0; i < sourcePaths.length; i++)
        ScanWorkflowPage(
          sourcePath: sourcePaths[i],
          outputPath: autoCropEnabled && !failed.contains(i)
              ? crop.paths[i] : sourcePaths[i],
          boundary: !autoCropEnabled
              ? ScanBoundaryState.original
              : failed.contains(i) || crop.paths[i] == sourcePaths[i]
                  ? ScanBoundaryState.needsCornerReview
                  : ScanBoundaryState.autoCropped,
        ),
    ]);
  }

  List<int> get reviewIndexes => [
        for (var i = 0; i < pages.length; i++)
          if (pages[i].needsReview) i,
      ];

  List<String> get outputPaths =>
      [for (final page in pages) page.outputPath];

  bool get needsReview => pages.any((page) => page.needsReview);

  ScanWorkflowBatch withManualCrop(int index, String newPath) {
    if (index < 0 || index >= pages.length) {
      throw RangeError.index(index, pages, 'index');
    }
    final edited = [...pages];
    edited[index] = edited[index].manuallyCorrected(newPath);
    return ScanWorkflowBatch._(edited);
  }
}
