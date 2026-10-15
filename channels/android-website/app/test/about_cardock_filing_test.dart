import 'package:account_subscription_manager/core/entitlements/distribution_channel.dart';
import 'package:account_subscription_manager/core/platform/safe_url_launcher.dart';
import 'package:account_subscription_manager/core/theme/app_theme.dart';
import 'package:account_subscription_manager/features/about/presentation/about_cardock_page.dart';
import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const entry = ValueKey<String>('about-app-filing');
  if (CardockDistributionConfig.channel != CardockDistributionChannel.website) {
    testWidgets('备案入口仅在网站 Android 渠道显示', (tester) async {
      final launcher = _RecordingLauncher();
      await _pumpAbout(tester, launcher);
      expect(find.byKey(entry), findsNothing);
      expect(launcher.urls, isEmpty);
    });
    return;
  }

  testWidgets('展示完整备案号，只有点击才打开官方查询入口', (tester) async {
    final launcher = _RecordingLauncher();
    await _pumpAbout(tester, launcher);
    expect(find.text('蜀ICP备2026057650号-2A'), findsOneWidget);
    expect(find.text('APP备案号 · 工信部查询'), findsOneWidget);
    expect(launcher.urls, isEmpty);
    await tester.tap(find.byKey(entry));
    await tester.pumpAndSettle();
    expect(launcher.urls, ['https://beian.miit.gov.cn/']);
    expect(tester.takeException(), isNull);
  });

  for (final throwsError in [false, true]) {
    testWidgets('浏览器${throwsError ? '异常' : '不可用'}时保留备案号并提示', (tester) async {
      final launcher = _RecordingLauncher(
        result: false,
        throwsError: throwsError,
      );
      await _pumpAbout(tester, launcher);
      await tester.tap(find.byKey(entry));
      await tester.pumpAndSettle();
      expect(find.text('打开网址失败。'), findsOneWidget);
      expect(find.text('蜀ICP备2026057650号-2A'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('320px 和200%字体下三语备案号完整且无溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final launcher = _RecordingLauncher();
    for (final locale in AppLocalizations.supportedLocales) {
      await _pumpAbout(tester, launcher, locale: locale, textScale: 2);
      await tester.ensureVisible(find.byKey(entry));
      await tester.pumpAndSettle();
      expect(find.text('蜀ICP备2026057650号-2A'), findsOneWidget);
      expect(find.byIcon(Icons.open_in_new), findsOneWidget);
      expect(tester.takeException(), isNull, reason: locale.toString());
      await tester.tap(find.byKey(entry));
      await tester.pumpAndSettle();
    }
    expect(launcher.urls, List.filled(3, 'https://beian.miit.gov.cn/'));
  });
}

Future<void> _pumpAbout(
  WidgetTester tester,
  ExternalUrlLauncher launcher, {
  Locale locale = const Locale('zh', 'CN'),
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: AboutCardockPage(urlLauncher: launcher),
    ),
  );
  await tester.pumpAndSettle();
}

class _RecordingLauncher implements ExternalUrlLauncher {
  _RecordingLauncher({this.result = true, this.throwsError = false});
  final bool result;
  final bool throwsError;
  final List<String> urls = [];

  @override
  Future<bool> open(String input) async {
    urls.add(input);
    if (throwsError) throw StateError('Browser unavailable in test');
    return result;
  }
}
