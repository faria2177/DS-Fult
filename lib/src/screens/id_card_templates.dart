import '../models.dart';

/// The six presets shown on the reference ID Cards carousel.
enum IdCardTemplate {
  general('General', 'General', 1),
  idCard('ID Card', 'Front', 2),
  driverLicense('Driver License', 'Front', 2),
  passport('Passport', 'Passport', 1),
  bankCard('Bank Card', 'Front', 2),
  certificate('Certificate', 'Certificate', 1);

  const IdCardTemplate(this.label, this.firstSide, this.sideCount);

  final String label;
  final String firstSide;
  final int sideCount;

  bool get portraitGuide =>
      this == passport || this == certificate;

  DocumentKind get documentKind => switch (this) {
        IdCardTemplate.idCard => DocumentKind.idCard,
        IdCardTemplate.driverLicense => DocumentKind.driverLicense,
        IdCardTemplate.bankCard => DocumentKind.bankCard,
        _ => DocumentKind.document,
      };

  String sideName(int index) =>
      sideCount == 1 ? firstSide : (index == 0 ? 'Front' : 'Back');
}
