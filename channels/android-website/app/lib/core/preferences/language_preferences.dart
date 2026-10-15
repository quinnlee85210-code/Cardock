import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// The three languages deliberately supported by Cardock.
///
/// Existing installations default to Simplified Chinese instead of following
/// the operating system. This keeps upgrades deterministic for current users.
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

class CardockLanguageController extends ChangeNotifier {
  CardockLanguageController({required this.store});

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
      _preferences = await store.read() ?? const LanguagePreferences();
    } on Object {
      _preferences = const LanguagePreferences();
    } finally {
      _loaded = true;
      _notifyIfActive();
    }
  });

  /// Persists first and publishes the new locale only after the write succeeds.
  /// This prevents the UI from claiming a language that would be lost on the
  /// next launch. Rapid changes are serialized in request order.
  Future<void> setLanguage(CardockLanguage language) => _runExclusive(() async {
    if (language == _preferences.language) return;
    final next = LanguagePreferences(language: language);
    await store.write(next);
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
