import 'dart:convert';
import 'dart:io';

import 'package:account_subscription_manager/core/preferences/language_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('缺少偏好时固定回退简体中文，不跟随系统语言', () async {
    final controller = CardockLanguageController(
      store: MemoryLanguagePreferencesStore(),
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.language, CardockLanguage.simplifiedChinese);
    expect(controller.locale.languageCode, 'zh');
    expect(controller.locale.countryCode, 'CN');
  });

  test('英语与日语按稳定代码往返并在重建控制器后保持', () async {
    final store = MemoryLanguagePreferencesStore();
    final first = CardockLanguageController(store: store);
    addTearDown(first.dispose);
    await first.load();

    await first.setLanguage(CardockLanguage.english);
    expect(store.value?.toJson(), <String, Object>{
      'version': 1,
      'language': 'en',
    });

    final second = CardockLanguageController(store: store);
    addTearDown(second.dispose);
    await second.load();
    expect(second.language, CardockLanguage.english);

    await second.setLanguage(CardockLanguage.japanese);
    final third = CardockLanguageController(store: store);
    addTearDown(third.dispose);
    await third.load();
    expect(third.language, CardockLanguage.japanese);
  });

  test('损坏、未知语言及未来格式只读回退中文', () {
    expect(LanguagePreferences.tryParse(null), isNull);
    expect(LanguagePreferences.tryParse(<String, Object>{}), isNull);
    expect(
      LanguagePreferences.tryParse(<String, Object>{
        'version': 1,
        'language': 'future',
      }),
      isNull,
    );
    expect(
      LanguagePreferences.tryParse(<String, Object>{
        'version': 2,
        'language': 'ja',
      }),
      isNull,
    );
  });

  test('文件偏好损坏或未来版本时不覆盖原文件并回退中文', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cardock-language-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File(
      '${directory.path}${Platform.pathSeparator}language.json',
    );
    final store = FileLanguagePreferencesStore(file);

    await file.writeAsString('{broken');
    final brokenBytes = await file.readAsBytes();
    expect(await store.read(), isNull);
    expect(await file.readAsBytes(), brokenBytes);

    final futureJson = jsonEncode(<String, Object>{
      'version': 99,
      'language': 'ja',
    });
    await file.writeAsString(futureJson);
    expect(await store.read(), isNull);
    expect(await file.readAsString(), futureJson);
  });

  test('持久化失败时保持原语言且不发出切换通知', () async {
    final store = _FailingLanguageStore(
      const LanguagePreferences(language: CardockLanguage.english),
    );
    final controller = CardockLanguageController(store: store);
    addTearDown(controller.dispose);
    await controller.load();
    var notifications = 0;
    controller.addListener(() => notifications++);

    await expectLater(
      controller.setLanguage(CardockLanguage.japanese),
      throwsA(isA<FileSystemException>()),
    );

    expect(controller.language, CardockLanguage.english);
    expect(notifications, 0);
  });

  test('快速连续切换按请求顺序串行写入，最终状态与最后一次一致', () async {
    final store = _OrderedLanguageStore();
    final controller = CardockLanguageController(store: store);
    addTearDown(controller.dispose);
    await controller.load();

    final english = controller.setLanguage(CardockLanguage.english);
    final japanese = controller.setLanguage(CardockLanguage.japanese);
    await Future.wait(<Future<void>>[english, japanese]);

    expect(store.writes, <CardockLanguage>[
      CardockLanguage.english,
      CardockLanguage.japanese,
    ]);
    expect(controller.language, CardockLanguage.japanese);
  });

  test('三种语言的本族名称固定且无需翻译', () {
    expect(
      CardockLanguage.values.map((language) => language.nativeName),
      <String>['简体中文', 'English', '日本語'],
    );
  });
}

class _FailingLanguageStore implements LanguagePreferencesStore {
  _FailingLanguageStore(this.value);

  LanguagePreferences? value;

  @override
  Future<LanguagePreferences?> read() async => value;

  @override
  Future<void> write(LanguagePreferences preferences) {
    throw const FileSystemException('test write failure');
  }
}

class _OrderedLanguageStore implements LanguagePreferencesStore {
  final List<CardockLanguage> writes = <CardockLanguage>[];
  LanguagePreferences? value;

  @override
  Future<LanguagePreferences?> read() async => value;

  @override
  Future<void> write(LanguagePreferences preferences) async {
    await Future<void>.delayed(const Duration(milliseconds: 2));
    writes.add(preferences.language);
    value = preferences;
  }
}
