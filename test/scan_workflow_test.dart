import 'package:docscanner/src/services/document_edges.dart';
import 'package:docscanner/src/services/scan_workflow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reliable auto-crops go straight to enhancement and preview', () {
    final batch = ScanWorkflowBatch.fromCropResult(
      ['raw-a.jpg', 'raw-b.jpg'],
      const AutoCropBatch(['crop-a.jpg', 'crop-b.jpg'], 2),
      autoCropEnabled: true,
    );
    expect(batch.reviewIndexes, isEmpty);
    expect(batch.outputPaths, ['crop-a.jpg', 'crop-b.jpg']);
    expect(batch.pages.every((page) => page.isConfirmedCrop), isTrue);
  });

  test('weak page returns original and enters manual corner review', () {
    final batch = ScanWorkflowBatch.fromCropResult(
      ['raw-a.jpg', 'raw-b.jpg'],
      const AutoCropBatch(
        ['crop-a.jpg', 'raw-b.jpg'], 1, failedIndexes: [1],
      ),
      autoCropEnabled: true,
    );
    expect(batch.reviewIndexes, [1]);
    expect(batch.pages[1].boundary, ScanBoundaryState.needsCornerReview);
    expect(batch.pages[1].outputPath, batch.pages[1].sourcePath);
    expect(batch.pages[1].isConfirmedCrop, isFalse);
    final corrected = batch.withManualCrop(1, 'manual-b.jpg');
    expect(corrected.reviewIndexes, isEmpty);
    expect(corrected.outputPaths, ['crop-a.jpg', 'manual-b.jpg']);
    expect(corrected.pages[1].isConfirmedCrop, isTrue);
    // Immutable batch: the source photo and original proposal are unchanged.
    expect(batch.reviewIndexes, [1]);
    expect(batch.pages[1].sourcePath, 'raw-b.jpg');
  });

  test('disabling Auto Crop never asks for review or crops originals', () {
    final batch = ScanWorkflowBatch.fromCropResult(
      ['a.jpg', 'b.jpg'],
      const AutoCropBatch(['cropped-a.jpg', 'cropped-b.jpg'], 2),
      autoCropEnabled: false,
    );
    expect(batch.reviewIndexes, isEmpty);
    expect(batch.outputPaths, ['a.jpg', 'b.jpg']);
    expect(batch.pages.every((page) =>
        page.boundary == ScanBoundaryState.original), isTrue);
  });

  test('unverified untouched path cannot be marked as successful crop', () {
    final batch = ScanWorkflowBatch.fromCropResult(
      ['a.jpg'],
      const AutoCropBatch(['a.jpg'], 0),
      autoCropEnabled: true,
    );
    expect(batch.reviewIndexes, [0]);
  });

  test('no page may be silently dropped by a malformed crop batch', () {
    expect(
      () => ScanWorkflowBatch.fromCropResult(
        ['a.jpg', 'b.jpg'], const AutoCropBatch(['crop-a.jpg'], 1),
        autoCropEnabled: true,
      ),
      throwsArgumentError,
    );
  });
}
