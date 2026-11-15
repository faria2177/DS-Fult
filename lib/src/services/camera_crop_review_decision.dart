import 'dart:typed_data';

/// The nullable result of Adjust Corners has three meaningful states:
/// - null: the user pressed Cancel or system Back — discard this capture.
/// - empty map: Done was pressed without any manual edits — accept original.
/// - nonempty map: Done supplied one or more corrected page images.
///
/// This distinction is camera-only. Gallery and document imports keep their
/// existing separate review/commit workflows.
enum CameraCropReviewDecision { discard, accept }

CameraCropReviewDecision cameraCropReviewDecision(
    Map<int, Uint8List>? acceptedEdits) {
  return acceptedEdits == null
      ? CameraCropReviewDecision.discard
      : CameraCropReviewDecision.accept;
}
