import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:account_subscription_manager/l10n/context_l10n.dart';
import 'package:account_subscription_manager/l10n/localized_material.dart'
    as localized;
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('静态文本与富文本按 locale 翻译，用户值可明确保持原样', (tester) async {
    await tester.pumpWidget(
      material.MaterialApp(
        locale: const material.Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const material.Column(
          children: <material.Widget>[
            localized.Text(
              '确定',
              key: material.ValueKey<String>('localized-key'),
            ),
            localized.Text('确定', translate: false),
            localized.Text.rich(material.TextSpan(text: '取消')),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('OK'), findsOneWidget);
    expect(find.text('确定'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(
      find.byKey(const material.ValueKey<String>('localized-key')),
      findsOneWidget,
    );
  });

  testWidgets('独立组件缺少 App 级代理时固定回退简体中文', (tester) async {
    await tester.pumpWidget(
      material.MaterialApp(
        home: material.Builder(
          builder: (context) => material.Text(context.tr('确定')),
        ),
      ),
    );

    expect(find.text('确定'), findsOneWidget);
  });
}
