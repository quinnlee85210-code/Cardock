import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../entitlements/distribution_channel.dart';

/// The three languages deliberately supported by Cardock.
///
/// Existing saved choices are preserved. Google Play Android follows supported
/// system languages for missing preferences without saving an inferred choice.
enum CardockLanguage { simplifiedChinese, english, japanese }

extension CardockLanguageProperties on CardockLanguage {
  Locale get locale => switch (this) {
    CardockLanguage.simplifiedChinese => const Locale('zh', 'CN'),
    CardockLanguage.english => const Locale('en'),
    CardockLanguage.japanese => const Locale('ja'),
  };

  String get nativeName => switch (this) {
    CardockLanguage.simplifiedChinese => '简体中文',
    CardockLanguage.english => 'English',
    CardockLanguage.japanese => '日本語',
  };

  String get storageCode => switch (this) {
    CardockLanguage.simplifiedChinese => 'zh_CN',
    CardockLanguage.english => 'en',
    CardockLanguage.japanese => 'ja',
  };
}

CardockLanguage? cardockLanguageFromStorageCode(Object? value) {
  if (value is! String) return null;
  for (final language in CardockLanguage.values) {
    if (language.storageCode == value) return language;
  }
  return null;
}

@immutable
class LanguagePreferences {
  const LanguagePreferences({
    this.language = CardockLanguage.simplifiedChinese,
  });

  static const int formatVersion = 1;

  final CardockLanguage language;

  Map<String, Object> toJson() => <String, Object>{
    'version': formatVersion,
    'language': language.storageCode,
  };

  static LanguagePreferences? tryParse(Object? value) {
    if (value is! Map<Object?, Object?> || value['version'] != formatVersion) {
      return null;
    }
    final language = cardockLanguageFromStorageCode(value['language']);
    if (language == null) return null;
    return LanguagePreferences(language: language);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LanguagePreferences && language == other.language;

  @override
  int get hashCode => language.hashCode;
}

abstract interface class LanguagePreferencesStore {
  Future<LanguagePreferences?> read();

  Future<void> write(LanguagePreferences preferences);
}

class MemoryLanguagePreferencesStore implements LanguagePreferencesStore {
  MemoryLanguagePreferencesStore([this.value]);

  LanguagePreferences? value;

  @override
  Future<LanguagePreferences?> read() async => value;

  @override
  Future<void> write(LanguagePreferences preferences) async {
    value = preferences;
  }
}

/// Stores the global UI language outside every real, read-only and decoy vault.
///
/// The file contains only a version and a locale code, so it is intentionally
/// excluded from portable encrypted backups and never affects vault schema.
class FileLanguagePreferencesStore implements LanguagePreferencesStore {
  FileLanguagePreferencesStore(this._file);

  final File _file;

  static Future<LanguagePreferencesStore> create() async {
    try {
      final directory = await getApplicationSupportDirectory();
      return FileLanguagePreferencesStore(
        File(
          '${directory.path}${Platform.pathSeparator}'
          'cardock_language_v1.json',
        ),
      );
    } on Object {
      return MemoryLanguagePreferencesStore();
    }
  }

  @override
  Future<LanguagePreferences?> read() async {
    try {
      if (!await _file.exists()) return null;
      return LanguagePreferences.tryParse(
        jsonDecode(await _file.readAsString()),
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(LanguagePreferences preferences) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(jsonEncode(preferences.toJson()), flush: true);
  }
}

/// Match the complete preference list; Traditional Chinese is not a supported
/// localization and must not silently select Simplified Chinese resources.
CardockLanguage resolveCardockSystemLanguage(Iterable<Locale> locales) {
  for (final locale in locales) {
    if (locale.languageCode == 'en') return CardockLanguage.english;
    if (locale.languageCode == 'ja') return CardockLanguage.japanese;
    if (locale.languageCode == 'zh' &&
        (locale.scriptCode == 'Hans' ||
            (locale.scriptCode == null &&
                !const {'TW', 'HK', 'MO'}.contains(locale.countryCode)))) {
      return CardockLanguage.simplifiedChinese;
    }
  }
  return CardockLanguage.english;
}

class CardockLanguageController extends ChangeNotifier {
  CardockLanguageController({
    required this.store,
    List<Locale> Function()? systemLocales,
  }) : _systemLocales =
           systemLocales ??
           (defaultTargetPlatform == TargetPlatform.android &&
                   CardockDistributionConfig.channel ==
                       CardockDistributionChannel.googlePlay
               ? (() => WidgetsBinding.instance.platformDispatcher.locales)
               : null);

  // Other platforms retain their existing default until separately adopted.
  final List<Locale> Function()? _systemLocales;
  bool _hasExplicitChoice = false;
  bool get followsSystem => !_hasExplicitChoice && _systemLocales != null;
  LanguagePreferences get _systemPreferences => LanguagePreferences(
    language: _systemLocales == null
        ? CardockLanguage.simplifiedChinese
        : resolveCardockSystemLanguage(_systemLocales()),
  );

  void refreshSystemLanguage() {
    if (!_loaded || !followsSystem) return;
    final next = _systemPreferences;
    if (next == _preferences) return;
    _preferences = next;
    _notifyIfActive();
  }

  final LanguagePreferencesStore store;
  LanguagePreferences _preferences = const LanguagePreferences();
  Future<void> _operationTail = Future<void>.value();
  bool _loaded = false;
  bool _disposed = false;

  LanguagePreferences get preferences => _preferences;
  CardockLanguage get language => _preferences.language;
  Locale get locale => language.locale;
  bool get isLoaded => _loaded;

  Future<void> load() => _runExclusive(() async {
    try {
      final saved = await store.read();
      // Version 1 has no default/manual marker: preserve every saved choice.
      _hasExplicitChoice = saved != null;
      _preferences = saved ?? _systemPreferences;
    } on Object {
      _hasExplicitChoice = false;
      _preferences = _systemPreferences;
    } finally {
      _loaded = true;
      _notifyIfActive();
    }
  });

  /// Persists first and publishes the new locale only after the write succeeds.
  /// This prevents the UI from claiming a language that would be lost on the
  /// next launch. Rapid changes are serialized in request order.
  Future<void> setLanguage(CardockLanguage language) => _runExclusive(() async {
    if (_hasExplicitChoice && language == _preferences.language) return;
    final next = LanguagePreferences(language: language);
    await store.write(next);
    _hasExplicitChoice = true;
    _preferences = next;
    _notifyIfActive();
  });

  Future<T> _runExclusive<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  void _notifyIfActive() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class CardockLanguageScope
    extends InheritedNotifier<CardockLanguageController> {
  const CardockLanguageScope({
    required CardockLanguageController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static CardockLanguageController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'CardockLanguageScope is missing.');
    return controller!;
  }

  static CardockLanguageController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<CardockLanguageScope>()
        ?.notifier;
  }
}
