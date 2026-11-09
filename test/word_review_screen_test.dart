import 'package:docscanner/src/models.dart';
import 'package:docscanner/src/screens/word_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _sample = ScanDocument(id: 'word-1', name: 'Letter',
  createdAt: DateTime(2026, 11, 9),
  pages: const [
    ScanPage(id: 'a', path: '/missing-a.png', originalPath: '/missing-a.png'),
    ScanPage(id: 'b', path: '/missing-b.png', originalPath: '/missing-b.png'),
  ]);

void main() {
  testWidgets('DS Word review matches editing and sharing reference flow',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: WordReviewScreen(
      document: _sample,
      pageTexts: const ['To Whom It May Concern\nAn official letter.',
        'Second page text.'],
    )));
    await tester.pump();
    expect(find.text('To Word_Letter'), findsOneWidget);
    expect(find.textContaining('51 characters'), findsNothing);
    expect(find.textContaining('characters'), findsOneWidget);
    expect(find.text('DS Formatting'), findsOneWidget);
    expect(find.text('DS Writing'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Save as PDF'), findsOneWidget);
    expect(find.textContaining('CS AI'), findsNothing);

    await tester.tap(find.byKey(const Key('word-page-preview')));
    await tester.pumpAndSettle();
    expect(find.text('Edit text'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('word-edit-field')),
      'This edited page has meaningful content.');
    await tester.tap(find.byKey(const Key('word-apply-edit')));
    await tester.pumpAndSettle();
    expect(find.text('This edited page has meaningful content.'), findsOneWidget);
    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(find.text('An official letter.'), findsOneWidget);
    await tester.tap(find.byTooltip('Redo'));
    await tester.pump();
    expect(find.text('This edited page has meaningful content.'), findsOneWidget);

    await tester.tap(find.text('DS Formatting'));
    await tester.pumpAndSettle();
    expect(find.text('One-Tap Formatting'), findsOneWidget);
    expect(find.text('Text Size'), findsOneWidget);
    expect(find.text('Line Spacing'), findsOneWidget);
    await tester.tap(find.text('Large'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(find.text('Share as Word'), findsOneWidget);
    expect(find.text('Share as PDF'), findsOneWidget);
    expect(find.text('Share as Images'), findsOneWidget);
    await tester.binding.handlePopRoute();
  });

  testWidgets('DS writing offers real local text-cleanup actions',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: WordReviewScreen(
      document: _sample,
      pageTexts: const ['A  sentence  with  extra  spaces.',
        'Something else.'],
    )));
    await tester.tap(find.text('DS Writing'));
    await tester.pumpAndSettle();
    expect(find.text('DS Polish'), findsOneWidget);
    expect(find.text('DS Proofread'), findsOneWidget);
    expect(find.textContaining('run offline'), findsOneWidget);
    expect(find.byKey(const Key('word-ai-proofread')), findsOneWidget);
    await tester.tap(find.byKey(const Key('word-polish')));
    await tester.pumpAndSettle();
    expect(find.text('A sentence with extra spaces.'), findsOneWidget);
    expect(find.byTooltip('Undo'), findsOneWidget);
  });
}
