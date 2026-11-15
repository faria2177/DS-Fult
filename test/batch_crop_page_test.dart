import 'package:docscanner/src/screens/batch_crop_screen.dart';
import 'package:docscanner/src/services/image_processor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Batch crop starts with eight handles and keeps the raw source safe', () {
    final page = BatchCropPageState();
    expect(page.handles, hasLength(8));
    expect(page.confirmed, isFalse);
    expect(page.touched, isFalse);
    expect(page.turns, 0);
    expect(CropQuad(page.corners).isValid, isTrue);
  });

  test('Batch crop edge handle moves both corners and keeps a convex quad', () {
    final page = BatchCropPageState();
    final original = [...page.corners];
    expect(page.updateHandle(4, const Offset(0, .05)), isTrue);
    expect(page.corners[0].dy, closeTo(original[0].dy + .05, .0001));
    expect(page.corners[1].dy, closeTo(original[1].dy + .05, .0001));
    expect(page.corners[2], original[2]);
    expect(page.confirmed, isTrue);
    expect(page.touched, isTrue);
    expect(CropQuad(page.corners).isValid, isTrue);
  });

  test('Passive auto-detected state cannot silently modify saved ID side', () {
    final page = BatchCropPageState();
    // The UI may suggest a different contour on reopen, but until the
    // user confirms a handle/rotate/Auto Crop gesture the saved working
    // side must remain unmodified in onlyEdited mode.
    expect(page.touched, isFalse);
    page.corners
      ..clear()
      ..addAll(CropQuad.inset().corners);
    page.confirmed = true;
    expect(page.touched, isFalse);
    expect(page.updateHandle(4, const Offset(0, .03)), isTrue);
    expect(page.touched, isTrue);
  });

  test('CamScanner All selects entire current image rather than re-detect', () {
    final page = BatchCropPageState();
    expect(page.confirmed, isFalse);
    page.selectWholeImage();
    expect(page.corners, const [
      Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1),
    ]);
    expect(page.confirmed, isTrue);
    expect(page.touched, isTrue);
    expect(page.fullImageSelected, isTrue);
    expect(CropQuad(page.corners).isValid, isTrue);

    // A manual corner adjustment switches to actual perspective cropping.
    expect(page.updateHandle(0, const Offset(.04, .03)), isTrue);
    expect(page.fullImageSelected, isFalse);
    expect(page.corners[0], const Offset(.04, .03));
  });

  test('video workflow: All -> Auto Crop restores green capture outline', () {
    final state = BatchCropPageState();
    const green = [
      Offset(.30, .25), Offset(.65, .26),
      Offset(.67, .71), Offset(.29, .70),
    ];
    state.selectWholeImage();
    expect(state.fullImageSelected, isTrue);
    expect(state.restoreCapturedOutline(green), isTrue);
    expect(state.corners, green);
    expect(state.confirmed, isTrue);
    expect(state.fullImageSelected, isFalse);
    state.selectWholeImage();
    expect(state.fullImageSelected, isTrue);
    expect(state.restoreCapturedOutline(green), isTrue);
    expect(state.corners, green);
  });

  test('invalid captured green quad must not replace full image', () {
    final state = BatchCropPageState()..selectWholeImage();
    final original = List<Offset>.from(state.corners);
    expect(state.restoreCapturedOutline(const [
      Offset(.1, .1), Offset(.9, .9),
      Offset(.9, .1), Offset(.1, .9),
    ]), isFalse);
    expect(state.corners, original);
    expect(state.fullImageSelected, isTrue);
  });

  test('All selection never silently changes another batch page', () {
    final one = BatchCropPageState();
    final two = BatchCropPageState();
    final preserved = List<Offset>.from(two.corners);
    one.selectWholeImage();
    expect(two.corners, preserved);
    expect(two.confirmed, isFalse);
    expect(two.touched, isFalse);
  });

  test('All: copies confirmed corners without changing the source shape', () {
    final original = BatchCropPageState();
    final other = BatchCropPageState();
    expect(other.copyCornersFrom(original), isFalse);
    expect(original.updateHandle(4, const Offset(0, .025)), isTrue);
    expect(other.copyCornersFrom(original), isTrue);
    expect(other.corners, original.corners);
    expect(other.confirmed, isTrue);
    expect(other.touched, isTrue);
    expect(CropQuad(other.corners).isValid, isTrue);
  });

  test('All: skips page geometry with incompatible image aspect ratio', () {
    expect(BatchCropPageState.matchingPageAspect(.73, .74), isTrue);
    expect(BatchCropPageState.matchingPageAspect(.73, 1.73), isFalse);
    expect(BatchCropPageState.matchingPageAspect(0, 1.0), isFalse);
  });

  test('Dragging a corner beyond the image is rejected without mutation', () {
    final page = BatchCropPageState();
    final original = [...page.corners];
    expect(page.updateHandle(0, const Offset(-2, -2)), isFalse);
    expect(page.corners, original);
    expect(page.confirmed, isFalse);
    expect(page.touched, isFalse);
  });
}
