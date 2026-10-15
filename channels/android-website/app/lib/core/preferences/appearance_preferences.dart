import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../platform/desktop_icon_controller.dart';
import '../theme/cardock_theme_types.dart';
import '../theme/custom_theme.dart';

enum CardockBrightnessMode { system, light, dark }

extension CardockBrightnessModeLabel on CardockBrightnessMode {
  String get label => switch (this) {
    CardockBrightnessMode.system => '跟随系统',
    CardockBrightnessMode.light => '浅色',
    CardockBrightnessMode.dark => '深色',
  };

  ThemeMode get themeMode => switch (this) {
    CardockBrightnessMode.system => ThemeMode.system,
    CardockBrightnessMode.light => ThemeMode.light,
    CardockBrightnessMode.dark => ThemeMode.dark,
  };
}

enum CardockDesktopIconMode {
  followTheme,
  ceramicBlue,
  sakuraMist,
  paperArchive,
  lilacMoon,
  glacierBlue,
  mistCoral,
  neonZero,
  obsidianGold,
}

extension CardockDesktopIconModeLabel on CardockDesktopIconMode {
  String get label => switch (this) {
    CardockDesktopIconMode.followTheme => '跟随主题',
    CardockDesktopIconMode.ceramicBlue => '瓷蓝晴光',
    CardockDesktopIconMode.sakuraMist => '樱雾柔光',
    CardockDesktopIconMode.paperArchive => '橙墨旧刊',
    CardockDesktopIconMode.lilacMoon => '月纱丁香',
    CardockDesktopIconMode.glacierBlue => '冰川蓝釉',
    CardockDesktopIconMode.mistCoral => '雾海珊瑚',
    CardockDesktopIconMode.neonZero => '零域荧绿',
    CardockDesktopIconMode.obsidianGold => '曜石鎏金',
  };

  CardockLauncherFamily? get fixedFamily => switch (this) {
    CardockDesktopIconMode.followTheme => null,
    CardockDesktopIconMode.ceramicBlue => CardockLauncherFamily.ceramicBlue,
    CardockDesktopIconMode.sakuraMist => CardockLauncherFamily.sakuraMist,
    CardockDesktopIconMode.paperArchive => CardockLauncherFamily.paperArchive,
    CardockDesktopIconMode.lilacMoon => CardockLauncherFamily.lilacMoon,
    CardockDesktopIconMode.glacierBlue => CardockLauncherFamily.glacierBlue,
    CardockDesktopIconMode.mistCoral => CardockLauncherFamily.mistCoral,
    CardockDesktopIconMode.neonZero => CardockLauncherFamily.neonZero,
    CardockDesktopIconMode.obsidianGold => CardockLauncherFamily.obsidianGold,
  };
}

CardockDesktopIconMode cardockDesktopIconModeFor(
  CardockLauncherFamily family,
) => switch (family) {
  CardockLauncherFamily.ceramicBlue => CardockDesktopIconMode.ceramicBlue,
  CardockLauncherFamily.sakuraMist => CardockDesktopIconMode.sakuraMist,
  CardockLauncherFamily.paperArchive => CardockDesktopIconMode.paperArchive,
  CardockLauncherFamily.lilacMoon => CardockDesktopIconMode.lilacMoon,
  CardockLauncherFamily.glacierBlue => CardockDesktopIconMode.glacierBlue,
  CardockLauncherFamily.mistCoral => CardockDesktopIconMode.mistCoral,
  CardockLauncherFamily.neonZero => CardockDesktopIconMode.neonZero,
  CardockLauncherFamily.obsidianGold => CardockDesktopIconMode.obsidianGold,
};

@immutable
class AppearancePreferences {
  const AppearancePreferences({
    this.family = cardockDefaultThemeFamily,
    this.desktopIconMode = CardockDesktopIconMode.followTheme,
    this.brightnessMode = CardockBrightnessMode.system,
    this.customTheme = CardockCustomTheme.defaults,
  });

  static const int formatVersion = 5;
  static const int _legacyV1 = 1;
  static const int _legacyV2 = 2;
  static const int _legacyV3 = 3;
  static const int _legacyV4 = 4;

  final CardockThemeFamily family;
  final CardockDesktopIconMode desktopIconMode;
  final CardockBrightnessMode brightnessMode;
  final CardockCustomTheme customTheme;

  CardockLauncherFamily get resolvedLauncherFamily {
    final fixed = desktopIconMode.fixedFamily;
    if (fixed != null) return fixed;
    return resolveCardockLauncherFamily(
      themeFamily: family,
      customFallback: customTheme.launcherFallback,
    );
  }

  /// Compatibility view for callers that only need the effective fixed icon.
  CardockLauncherFamily get desktopIconFamily => resolvedLauncherFamily;

  AppearancePreferences copyWith({
    CardockThemeFamily? family,
    CardockDesktopIconMode? desktopIconMode,
    CardockBrightnessMode? brightnessMode,
    CardockCustomTheme? customTheme,
  }) {
    return AppearancePreferences(
      family: family ?? this.family,
      desktopIconMode: desktopIconMode ?? this.desktopIconMode,
      brightnessMode: brightnessMode ?? this.brightnessMode,
      customTheme: customTheme ?? this.customTheme,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'version': formatVersion,
    'family': family.name,
    'desktopIconMode': desktopIconMode.name,
    'brightnessMode': brightnessMode.name,
    'customTheme': customTheme.toJson(),
  };

  static AppearancePreferences? tryParse(Object? value) {
    if (value is! Map<Object?, Object?>) return null;

    final version = value['version'];
    if (version != _legacyV1 &&
        version != _legacyV2 &&
        version != _legacyV3 &&
        version != _legacyV4 &&
        version != formatVersion) {
      return null;
    }

    final brightness = _brightnessModeFromName(value['brightnessMode']);
    if (brightness == null) return null;

    final family = version == formatVersion || version == _legacyV4
        ? cardockThemeFamilyFromName(value['family'])
        : cardockLegacyThemeFamilyFromName(
            value['family'],
            formatVersion: version as int,
          );
    if (family == null) return null;

    if (version == _legacyV1 || version == _legacyV2) {
      final launcherFamily = version == _legacyV1
          ? CardockLauncherFamily.ceramicBlue
          : cardockLauncherFamilyFromName(value['desktopIconFamily']);
      if (launcherFamily == null) return null;

      // V1's independent in-app logo value remains intentionally ignored.
      // Both legacy formats become an explicit fixed launcher choice; they
      // must never migrate to followTheme.
      return AppearancePreferences(
        family: family,
        desktopIconMode: cardockDesktopIconModeFor(launcherFamily),
        brightnessMode: brightness,
      );
    }

    final desktopIconMode = version == formatVersion
        ? _desktopIconModeFromName(value['desktopIconMode'])
        : _legacyDesktopIconModeFromName(value['desktopIconMode']);
    if (desktopIconMode == null) return null;

    return AppearancePreferences(
      family: family,
      desktopIconMode: desktopIconMode,
      brightnessMode: brightness,
      customTheme: CardockCustomTheme.tryParse(value['customTheme']),
    );
  }

  static CardockBrightnessMode? _brightnessModeFromName(Object? value) {
    if (value is! String) return null;
    for (final mode in CardockBrightnessMode.values) {
      if (mode.name == value) return mode;
    }
    return null;
  }

  static CardockDesktopIconMode? _desktopIconModeFromName(Object? value) {
    if (value is! String) return null;
    for (final mode in CardockDesktopIconMode.values) {
      if (mode.name == value) return mode;
    }
    return null;
  }

  static CardockDesktopIconMode? _legacyDesktopIconModeFromName(
    Object? value,
  ) => switch (value) {
    'followTheme' => CardockDesktopIconMode.followTheme,
    'standard' => CardockDesktopIconMode.ceramicBlue,
    'prime' => CardockDesktopIconMode.obsidianGold,
    'vivid' => CardockDesktopIconMode.mistCoral,
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppearancePreferences &&
          family == other.family &&
          desktopIconMode == other.desktopIconMode &&
          brightnessMode == other.brightnessMode &&
          customTheme == other.customTheme;

  @override
  int get hashCode =>
      Object.hash(family, desktopIconMode, brightnessMode, customTheme);
}

abstract interface class AppearancePreferencesStore {
  Future<AppearancePreferences?> read();

  Future<void> write(AppearancePreferences preferences);
}

class MemoryAppearancePreferencesStore implements AppearancePreferencesStore {
  MemoryAppearancePreferencesStore([this.value]);

  AppearancePreferences? value;

  @override
  Future<AppearancePreferences?> read() async => value;

  @override
  Future<void> write(AppearancePreferences preferences) async {
    value = preferences;
  }
}

class FileAppearancePreferencesStore implements AppearancePreferencesStore {
  FileAppearancePreferencesStore(this._file);

  final File _file;

  static Future<AppearancePreferencesStore> create() async {
    try {
      final directory = await getApplicationSupportDirectory();
      return FileAppearancePreferencesStore(
        File(
          '${directory.path}${Platform.pathSeparator}cardock_appearance_v1.json',
        ),
      );
    } on Object {
      return MemoryAppearancePreferencesStore();
    }
  }

  @override
  Future<AppearancePreferences?> read() async {
    try {
      if (!await _file.exists()) return null;
      final decoded = jsonDecode(await _file.readAsString());
      if (decoded is Map &&
          decoded['version'] is int &&
          (decoded['version'] as int) > AppearancePreferences.formatVersion) {
        throw const _FutureAppearanceVersion();
      }
      final preferences = AppearancePreferences.tryParse(decoded);
      if (preferences == null) return null;

      final version = decoded is Map<Object?, Object?>
          ? decoded['version']
          : null;
      if (version != AppearancePreferences.formatVersion) {
        try {
          await write(preferences);
        } on Object {
          // A valid legacy preference remains usable in memory. The same
          // migration is retried on the next successful read.
        }
      }
      return preferences;
    } on _FutureAppearanceVersion {
      rethrow;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(AppearancePreferences preferences) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(jsonEncode(preferences.toJson()), flush: true);
  }
}

class _FutureAppearanceVersion implements Exception {
  const _FutureAppearanceVersion();
}

class CardockAppearanceController extends ChangeNotifier {
  CardockAppearanceController({
    required this.store,
    required this.desktopIconBridge,
  });

  final AppearancePreferencesStore store;
  final DesktopIconBridge desktopIconBridge;
  AppearancePreferences _preferences = const AppearancePreferences();
  Future<void> _operationTail = Future<void>.value();
  bool _loaded = false;
  bool _disposed = false;

  AppearancePreferences get preferences => _preferences;
  CardockThemeFamily get family => _preferences.family;
  CardockDesktopIconMode get desktopIconMode => _preferences.desktopIconMode;
  CardockLauncherFamily get resolvedLauncherFamily =>
      _preferences.resolvedLauncherFamily;
  CardockLauncherFamily get desktopIconFamily => resolvedLauncherFamily;
  CardockCustomTheme get customTheme => _preferences.customTheme;
  CardockBrightnessMode get brightnessMode => _preferences.brightnessMode;
  ThemeMode get themeMode => brightnessMode.themeMode;
  bool get isLoaded => _loaded;

  Future<void> load({
    CardockThemeFamily Function(CardockThemeFamily family)? sanitizeFamily,
    CardockDesktopIconMode Function(CardockDesktopIconMode mode)?
    sanitizeIconMode,
  }) => _runExclusive(() async {
    var shouldSynchronizeLauncher = true;
    try {
      final stored = await store.read();
      if (stored != null) {
        final sanitizedFamily =
            sanitizeFamily?.call(stored.family) ?? stored.family;
        final sanitized = stored.copyWith(
          family: sanitizedFamily,
          desktopIconMode:
              sanitizeIconMode?.call(stored.desktopIconMode) ??
              stored.desktopIconMode,
        );
        _preferences = sanitized;
        if (sanitized != stored) {
          try {
            await store.write(sanitized);
          } on Object {
            // Keep the safe in-memory family even if the silent repair cannot
            // be persisted. A later launch will enforce the same rule again.
          }
        }
      }
    } on _FutureAppearanceVersion {
      shouldSynchronizeLauncher = false;
      _preferences = const AppearancePreferences();
    } on Object {
      _preferences = const AppearancePreferences();
    } finally {
      _loaded = true;
      _notifyIfActive();
    }

    if (_disposed || !shouldSynchronizeLauncher) return;
    try {
      await _synchronizeDesktopIcon(_preferences.resolvedLauncherFamily);
    } on Object {
      // Startup synchronization is retried on a later launch or explicit
      // selection. It must never escape an unawaited application load.
    }
  });

  Future<void> setFamily(CardockThemeFamily family) => _runExclusive(() async {
    if (family == _preferences.family) return;
    await _applyPreferences(
      _preferences.copyWith(family: family),
      synchronizeLauncher:
          _preferences.desktopIconMode == CardockDesktopIconMode.followTheme,
    );
  });

  Future<void> setFamilyAndFollowDesktopIcon(CardockThemeFamily family) =>
      _runExclusive(() async {
        if (family == _preferences.family &&
            _preferences.desktopIconMode ==
                CardockDesktopIconMode.followTheme) {
          await _synchronizeDesktopIcon(_preferences.resolvedLauncherFamily);
          return;
        }
        await _applyPreferences(
          _preferences.copyWith(
            family: family,
            desktopIconMode: CardockDesktopIconMode.followTheme,
          ),
          synchronizeLauncher: true,
        );
      });

  /// Applies a fail-safe entitlement fallback.
  ///
  /// Unlike an explicit user selection, a failed preference write must not
  /// restore a theme the current entitlement cannot use. Persistence and the
  /// launcher alias are retried on a later startup.
  Future<void> enforceFamilyFallback(
    CardockThemeFamily family, {
    CardockDesktopIconMode? desktopIconMode,
  }) => _runExclusive(() async {
    if (family == _preferences.family &&
        (desktopIconMode == null ||
            desktopIconMode == _preferences.desktopIconMode)) {
      return;
    }
    _preferences = _preferences.copyWith(
      family: family,
      desktopIconMode: desktopIconMode,
    );
    _notifyIfActive();
    try {
      await store.write(_preferences);
    } on Object {
      // Still enforce the safe native icon; retry persistence on startup.
    }
    try {
      await _synchronizeDesktopIcon(_preferences.resolvedLauncherFamily);
    } on Object {
      // The in-app theme remains safe even if Android cannot update the
      // non-sensitive launcher alias during this attempt.
    }
  });

  Future<void> setBrightnessMode(CardockBrightnessMode mode) =>
      _runExclusive(() async {
        if (mode == _preferences.brightnessMode) return;
        await _applyPreferences(
          _preferences.copyWith(brightnessMode: mode),
          synchronizeLauncher: false,
        );
      });

  Future<void> setDesktopIconMode(CardockDesktopIconMode mode) =>
      _runExclusive(() async {
        if (mode == _preferences.desktopIconMode) {
          await _synchronizeDesktopIcon(_preferences.resolvedLauncherFamily);
          return;
        }
        await _applyPreferences(
          _preferences.copyWith(desktopIconMode: mode),
          synchronizeLauncher: true,
        );
      });

  /// Compatibility API for selecting one of the eight fixed launcher icons.
  Future<void> setDesktopIconFamily(CardockLauncherFamily family) =>
      setDesktopIconMode(cardockDesktopIconModeFor(family));

  Future<void> setCustomTheme(CardockCustomTheme customTheme) => _runExclusive(
    () async {
      final issues = customTheme.validate();
      if (issues.isNotEmpty) {
        throw CardockCustomThemeValidationException(issues);
      }
      if (customTheme == _preferences.customTheme) return;

      final fallbackChanged =
          customTheme.launcherFallback !=
          _preferences.customTheme.launcherFallback;
      await _applyPreferences(
        _preferences.copyWith(customTheme: customTheme),
        synchronizeLauncher:
            fallbackChanged &&
            _preferences.family == CardockThemeFamily.custom &&
            _preferences.desktopIconMode == CardockDesktopIconMode.followTheme,
      );
    },
  );

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

  Future<void> _applyPreferences(
    AppearancePreferences next, {
    required bool synchronizeLauncher,
  }) async {
    final previous = _preferences;
    _preferences = next;
    _notifyIfActive();
    try {
      await store.write(next);
    } on Object {
      _preferences = previous;
      _notifyIfActive();
      rethrow;
    }

    if (!synchronizeLauncher) return;
    try {
      await _synchronizeDesktopIcon(next.resolvedLauncherFamily);
    } catch (error, stackTrace) {
      _preferences = previous;
      _notifyIfActive();
      try {
        await store.write(previous);
      } on Object {
        // Keep the in-memory rollback and original channel failure. A later
        // retry persists the requested value again before switching.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _synchronizeDesktopIcon(CardockLauncherFamily desired) async {
    CardockLauncherFamily? active;
    try {
      active = await desktopIconBridge.getActiveIcon();
    } on DesktopIconMigrationRequiredException {
      await _setAndVerifyDesktopIcon(desired);
      return;
    } on PlatformException catch (error) {
      if (error.code != 'NO_ENABLED_ALIAS' &&
          error.code != 'MULTIPLE_ENABLED_ALIASES') {
        rethrow;
      }
      await _setAndVerifyDesktopIcon(desired);
      return;
    }
    if (active == null || active == desired) return;
    await _setAndVerifyDesktopIcon(desired);
  }

  Future<void> _setAndVerifyDesktopIcon(CardockLauncherFamily desired) async {
    await desktopIconBridge.setIcon(desired);
    if (await desktopIconBridge.getActiveIcon() != desired) {
      throw const DesktopIconProtocolException(
        'Launcher did not apply the selected icon.',
      );
    }
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

class CardockAppearanceScope
    extends InheritedNotifier<CardockAppearanceController> {
  const CardockAppearanceScope({
    required CardockAppearanceController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static CardockAppearanceController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'CardockAppearanceScope is missing.');
    return controller!;
  }

  static CardockAppearanceController? maybeOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<CardockAppearanceScope>();
    return scope?.notifier;
  }
}
