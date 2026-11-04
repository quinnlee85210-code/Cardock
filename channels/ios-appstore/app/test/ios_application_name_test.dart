import 'package:account_subscription_manager/core/theme/app_theme.dart';
import 'package:account_subscription_manager/features/about/presentation/about_cardock_page.dart';
import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets(
      'iOS name in ${locale.languageCode} fits narrow screen and large text',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 640);
        tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(
          tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: const AboutCardockPage(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(AppLocalizations(locale).appTitle), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
