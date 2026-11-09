import 'package:docscanner/src/models.dart';
import 'package:docscanner/src/screens/excel_review_screen.dart';
import 'package:docscanner/src/services/xlsx_export.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _sample = ScanDocument(id: 'excel-1', name: 'Tournament Schedule',
  createdAt: DateTime(2026, 11, 9), pages: const [
    ScanPage(id: '1', path: '/missing-excel-1.png',
      originalPath: '/missing-excel-1.png'),
    ScanPage(id: '2', path: '/missing-excel-2.png',
      originalPath: '/missing-excel-2.png'),
  ]);

void main() {
  test('Excel OCR grid preserves rows, columns and non-tab single cells', () {
    expect(ExcelReviewScreen.parseRows('Report\nName\tScore\nTeam A\t5'), [
      ['Report'], ['Name', 'Score'], ['Team A', '5'],
    ]);
    expect(ExcelReviewScreen.parseRows('A  B\nC  D'), [
      ['A', 'B'], ['C', 'D'],
    ]);
  });

  testWidgets('Excel preview supports cell selection, edit, undo and redo',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: ExcelReviewScreen(
      document: _sample, pageTexts: const [
        'Tournament Schedule\nGroup\tTeam\nA\tFalcons',
        'Day\tTime\nFriday\t09:00',
      ],
    )));
    await tester.pump();
    expect(find.text('To Excel_Tournament Schedule'), findsOneWidget);
    expect(find.text('DS Formatting'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Only tables'), findsOneWidget);
    expect(find.text('All content'), findsOneWidget);
    expect(find.byKey(const Key('excel-cell-0-2-1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('excel-cell-0-2-1')));
    // InkWell resolves a possible double-tap before firing the single-tap
    // selection callback, so the test must advance that gesture timeout.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Edit text'));
    await tester.pumpAndSettle();
    expect(find.text('Edit cell B3'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('excel-cell-editor')), 'Eagles');
    await tester.tap(find.byKey(const Key('excel-cell-save')));
    await tester.pumpAndSettle();
    expect(find.text('Eagles'), findsOneWidget);
    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(find.text('Falcons'), findsOneWidget);
    await tester.tap(find.byTooltip('Redo'));
    await tester.pump();
    expect(find.text('Eagles'), findsOneWidget);

    await tester.tap(find.byKey(const Key('excel-only-tables')));
    await tester.pump();
    expect(find.byKey(const Key('excel-cell-0-0-0')), findsNothing);
    expect(find.byKey(const Key('excel-cell-0-2-1')), findsOneWidget);
    await tester.tap(find.byTooltip('Next sheet'));
    await tester.pump();
    expect(find.text('Page 2 / 2'), findsOneWidget);
    expect(find.byKey(const Key('excel-cell-1-1-1')), findsOneWidget);
  });

  testWidgets('Excel share and formatting expose actual options',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: ExcelReviewScreen(
      document: _sample, pageTexts: const ['Name\tValue\nA\t1'],
    )));
    await tester.pump();
    await tester.tap(find.text('DS Formatting'));
    await tester.pumpAndSettle();
    expect(find.text('Bold first row'), findsOneWidget);
    expect(find.text('Compact'), findsOneWidget);
    expect(find.text('Large'), findsOneWidget);
    await tester.tap(find.text('Large'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(find.text('Share as Excel'), findsOneWidget);
    expect(find.text('Share as PDF'), findsOneWidget);
    expect(find.text('Save as PDF'), findsOneWidget);
    expect(find.textContaining('CS AI'), findsNothing);
  });

  test('Excel layout preserves user-selected font and sheet dimensions', () {
    const custom = XlsxLayout(fontSize: 14, columnWidth: 22,
      rowHeight: 37, boldFirstRow: true);
    expect(custom.fontSize, 14);
    expect(custom.columnWidth, 22);
    expect(custom.rowHeight, 37);
    expect(custom.boldFirstRow, true);
  });
}
