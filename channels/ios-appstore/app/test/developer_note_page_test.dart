import 'package:account_subscription_manager/core/theme/app_theme.dart';
import 'package:account_subscription_manager/core/theme/cardock_tokens.dart';
import 'package:account_subscription_manager/features/about/presentation/developer_note_page.dart';
import 'package:account_subscription_manager/l10n/app_localizations.dart';
import 'package:account_subscription_manager/shared/widgets/cardock_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('开发者的话使用权威中文结构且不包含赞赏收款内容', (tester) async {
    await _setViewport(tester, const Size(420, 900));
    await _pumpDeveloperNote(tester);

    expect(find.text('开发者的话'), findsOneWidget);
    expect(find.text('谢谢你选择 Cardock'), findsOneWidget);
    expect(find.text('第一款作品'), findsOneWidget);
    expect(find.text('9.9 元一次买断'), findsOneWidget);
    expect(find.text('长期维护'), findsOneWidget);
    _expectNoDonationContent();

    await _scrollTo(tester, 'developer-note-letter');
    expect(find.text('为什么做 Cardock'), findsOneWidget);
    expect(find.text('账号、密码和订阅记录，都是非常私人的信息。'), findsOneWidget);
    expect(find.textContaining('它不是一个做完就放下的试验项目'), findsOneWidget);
    _expectNoDonationContent();

    await _scrollTo(tester, 'developer-note-principles');
    expect(find.text('我会坚持的三件事'), findsOneWidget);
    expect(find.text('认真维护'), findsOneWidget);
    expect(find.text('保持克制'), findsOneWidget);
    expect(find.text('尊重购买'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('developer-note-principles')),
        matching: find.byType(CardockSurfaceCard),
      ),
      findsNothing,
      reason: '三项坚持必须位于同一张卡片中，不嵌套三张大卡片',
    );
    _expectNoDonationContent();

    await _scrollTo(tester, 'developer-note-purchase');
    expect(find.text('一次购买，就是最直接的支持'), findsOneWidget);
    expect(find.text('复制推荐文案'), findsOneWidget);
    _expectNoDonationContent();

    await _scrollTo(tester, 'developer-note-contact');
    expect(find.text('联系与反馈'), findsOneWidget);
    expect(find.text('kawucardock'), findsOneWidget);
    expect(find.text('隐私与安全说明'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    _expectNoDonationContent();

    await _scrollTo(tester, 'developer-note-signature');
    expect(find.text('谢谢你愿意使用 Cardock。'), findsOneWidget);
    expect(find.text('我会认真把它维护下去。'), findsOneWidget);
    expect(find.text('—— Cardock 开发者'), findsOneWidget);
    _expectNoDonationContent();
  });

  testWidgets('微信号使用普通 Clipboard 精确复制并显示成功提示', (tester) async {
    MethodCall? clipboardCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') clipboardCall = call;
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await _setViewport(tester, const Size(420, 900));
    await _pumpDeveloperNote(tester);
    await _scrollTo(tester, 'developer-note-contact');
    await tester.tap(
      find.byKey(const ValueKey<String>('developer-note-copy-wechat')),
    );
    await tester.pumpAndSettle();

    expect(clipboardCall?.method, 'Clipboard.setData');
    expect(
      (clipboardCall?.arguments as Map<Object?, Object?>)['text'],
      'kawucardock',
    );
    expect(find.text('微信号已复制'), findsOneWidget);
  });

  testWidgets('推荐文案使用普通 Clipboard 且不附加商店链接', (tester) async {
    MethodCall? clipboardCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') clipboardCall = call;
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await _setViewport(tester, const Size(420, 900));
    await _pumpDeveloperNote(tester);
    await _scrollTo(tester, 'developer-note-purchase');
    await tester.tap(
      find.byKey(const ValueKey<String>('developer-note-copy-recommendation')),
    );
    await tester.pumpAndSettle();

    const expected = 'Cardock：一款本地保存账号与订阅记录的工具，9.9 元一次买断，无广告、无订阅。';
    expect(
      (clipboardCall?.arguments as Map<Object?, Object?>)['text'],
      expected,
    );
    expect(expected, isNot(contains('http')));
    expect(find.text('推荐文案已复制'), findsOneWidget);
  });

  testWidgets('隐私与安全说明进入现有 AboutCardockPage', (tester) async {
    await _setViewport(tester, const Size(420, 900));
    await _pumpDeveloperNote(tester);
    await _scrollTo(tester, 'developer-note-contact');
    await tester.tap(
      find.byKey(const ValueKey<String>('developer-note-open-about')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('about-cardock-page')),
      findsOneWidget,
    );
  });

  testWidgets('中英日三语框架在320x640和200%字体下可滚动且无溢出', (tester) async {
    await _setViewport(tester, const Size(320, 640));

    for (final locale in AppLocalizations.supportedLocales) {
      await _pumpDeveloperNote(
        tester,
        locale: locale,
        textScale: 2,
        theme: AppTheme.light(family: CardockThemeFamily.paperArchive),
      );
      expect(tester.takeException(), isNull, reason: locale.toString());
      await _scrollTo(tester, 'developer-note-signature', delta: 240);
      expect(tester.takeException(), isNull, reason: locale.toString());
      expect(
        find.byKey(const ValueKey<String>('developer-note-signature')),
        findsOneWidget,
      );
    }
  });

  testWidgets('全部固定主题与Custom的浅深模式均复用主题体系', (tester) async {
    await _setViewport(tester, const Size(390, 844));

    for (final family in cardockSelectableThemeFamilies) {
      for (final brightness in Brightness.values) {
        await _pumpDeveloperNote(
          tester,
          theme: AppTheme.build(family, brightness),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: '${family.name}/$brightness',
        );
        expect(
          find.byKey(const ValueKey<String>('developer-note-hero')),
          findsOneWidget,
        );
        expect(find.byType(CardockSurfaceCard), findsWidgets);
      }
    }
  });
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _pumpDeveloperNote(
  WidgetTester tester, {
  Locale locale = const Locale('zh', 'CN'),
  double textScale = 1,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: theme ?? AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const DeveloperNotePage(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(
  WidgetTester tester,
  String key, {
  double delta = 300,
}) async {
  await tester.scrollUntilVisible(
    find.byKey(ValueKey<String>(key)),
    delta,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void _expectNoDonationContent() {
  expect(find.textContaining('¥6'), findsNothing);
  expect(find.textContaining('¥18'), findsNothing);
  expect(find.textContaining('¥66'), findsNothing);
  expect(find.textContaining('赞赏码'), findsNothing);
  expect(find.textContaining('支付宝收款码'), findsNothing);
  expect(find.textContaining('长按图片可保存'), findsNothing);
}
