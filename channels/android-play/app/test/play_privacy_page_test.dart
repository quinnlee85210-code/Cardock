import 'package:account_subscription_manager/features/about/presentation/play_privacy_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final entry in {
    'zh': ['隐私政策', '联系与变更'],
    'en': ['Privacy policy', 'Support and changes'],
    'ja': ['プライバシーポリシー', 'お問い合わせと変更'],
  }.entries) {
    testWidgets('offline Play privacy can be read end to end in ${entry.key}', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(entry.key),
          supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const PlayPrivacyPage(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(entry.value.first), findsOneWidget);
      await tester.scrollUntilVisible(find.text(entry.value.last), 400);
      expect(find.text(entry.value.last), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Missing production URL must never become a fabricated external link.
      expect(find.byType(TextButton), findsNothing);
    });
  }
}
