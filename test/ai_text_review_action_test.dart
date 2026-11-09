import 'package:docscanner/src/models.dart';
import 'package:docscanner/src/screens/ai_text_review_action.dart';
import 'package:docscanner/src/screens/word_review_screen.dart';
import 'package:docscanner/src/screens/excel_review_screen.dart';
import 'package:docscanner/src/services/ai_text_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTextAi implements AiTextEngine {
  int calls = 0;
  String? sentText;
  AiTextTask? sentTask;
  bool enabled = true;

  @override
  Future<AiTextConfig?> activeConfiguration() async => enabled
      ? const AiTextConfig(providerId: 'groq', providerName: 'Groq Cloud',
          modelId: 'llama-3.3-70b-versatile')
      : null;

  @override
  Future<String> rewrite({required AiTextConfig config,
      required AiTextTask task, required String text}) async {
    calls++;
    sentText = text;
    sentTask = task;
    return task == AiTextTask.proofread ? 'Corrected page.' : 'Name\tScore\nA\t8';
  }
}

final _doc = ScanDocument(id: 'ai-doc', name: 'Local Test',
  createdAt: DateTime(2026, 11, 9), pages: const [
    ScanPage(id: 'ai-p', path: '/missing-ai.jpg',
      originalPath: '/missing-ai.jpg'),
  ]);

void main() {
  testWidgets('nothing is sent before separate confirmation, apply or discard',
      (tester) async {
    final ai = _FakeTextAi();
    String? result;
    await tester.pumpWidget(MaterialApp(home: Builder(
      builder: (screenContext) => Scaffold(body: Center(
        child: FilledButton(onPressed: () async {
          result = await AiTextReviewAction.run(screenContext,
            text: 'Original OCR text.', task: AiTextTask.proofread,
            engine: ai);
        }, child: const Text('Start AI')),
      )),
    )));
    await tester.tap(find.text('Start AI'));
    await tester.pumpAndSettle();
    expect(find.text('Send text to external AI?'), findsOneWidget);
    expect(find.textContaining('Original OCR text.'), findsOneWidget);
    expect(ai.calls, 0);
    await tester.tap(find.byKey(const Key('ai-cancel-send')));
    await tester.pumpAndSettle();
    expect(ai.calls, 0);
    expect(result, isNull);

    await tester.tap(find.text('Start AI'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-confirm-send')));
    await tester.pumpAndSettle();
    expect(ai.calls, 1);
    expect(ai.sentText, 'Original OCR text.');
    expect(find.text('Review AI suggestion'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ai-discard-result')));
    await tester.pumpAndSettle();
    expect(result, isNull);

    await tester.tap(find.text('Start AI'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-confirm-send')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-apply-result')));
    await tester.pumpAndSettle();
    expect(result, 'Corrected page.');
    expect(ai.calls, 2);
  });

  testWidgets('Word AI proofreading changes only reviewed page and can undo',
      (tester) async {
    final ai = _FakeTextAi();
    await tester.binding.setSurfaceSize(const Size(430, 980));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: WordReviewScreen(
      document: _doc, pageTexts: const ['Ocr text.'], aiEngine: ai,
    )));
    await tester.tap(find.text('DS Writing'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('word-ai-proofread')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('word-ai-proofread')));
    // An indeterminate progress bar runs while the review is open.
    await tester.pump(const Duration(milliseconds: 400));
    expect(ai.calls, 0);
    await tester.tap(find.byKey(const Key('ai-confirm-send')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('ai-apply-result')));
    await tester.pumpAndSettle();
    expect(find.text('Corrected page.'), findsOneWidget);
    expect(ai.sentText, 'Ocr text.');
    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(find.text('Ocr text.'), findsOneWidget);
  });

  testWidgets('Excel sends sheet text only after consent and applies tabular AI',
      (tester) async {
    final ai = _FakeTextAi();
    await tester.binding.setSurfaceSize(const Size(430, 980));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: ExcelReviewScreen(
      document: _doc, pageTexts: const ['Name\tScore\nA\t3'], aiEngine: ai,
    )));
    await tester.tap(find.byKey(const Key('excel-ai-clean')));
    // Excel's busy overlay animates until the user accepts or cancels.
    await tester.pump(const Duration(milliseconds: 400));
    expect(ai.calls, 0);
    await tester.tap(find.byKey(const Key('ai-confirm-send')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(ai.sentTask, AiTextTask.tableCleanup);
    await tester.tap(find.byKey(const Key('ai-apply-result')));
    await tester.pumpAndSettle();
    expect(find.text('8'), findsOneWidget);
    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
  });
}
