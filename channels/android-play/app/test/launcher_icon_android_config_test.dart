import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MainActivity保留安全渠道、可切换防截屏并接入launcher channel', () async {
    final activity = await File(
      'android/app/src/main/kotlin/com/localaccount/'
      'account_subscription_manager/MainActivity.kt',
    ).readAsString();

    expect(
      activity,
      contains('class MainActivity : FlutterFragmentActivity()'),
    );
    expect(activity, contains('FLAG_SECURE'));
    expect(activity, contains('cardock/screen_protection'));
    expect(
      activity,
      contains('configureScreenProtectionChannel(flutterEngine)'),
    );
    expect(
      activity,
      contains('account_subscription_manager/sensitive_clipboard'),
    );
    expect(activity, contains('account_subscription_manager/quick_unlock_v2'));
    expect(
      activity,
      contains('configureSensitiveClipboardChannel(flutterEngine)'),
    );
    expect(activity, contains('configureQuickUnlockChannel(flutterEngine)'));
    expect(
      RegExp(
        r'super\.configureFlutterEngine\(flutterEngine\)',
      ).allMatches(activity),
      hasLength(1),
    );
    expect(activity, contains('override fun onStop()'));
    expect(activity, contains('override fun onDestroy()'));
    expect(activity, contains('cancelActiveQuickUnlockForLifecycle'));

    expect(
      activity,
      contains('LAUNCHER_ICON_CHANNEL = "cardock/launcher_icon"'),
    );
    expect(activity, contains('configureLauncherIconChannel(flutterEngine)'));
    expect(activity, contains('"setLauncherIcon"'));
    expect(activity, contains('"getLauncherIcon"'));
    expect(activity, contains('"INVALID_VARIANT"'));
    expect(activity, contains('"NO_ENABLED_ALIAS"'));
    expect(activity, contains('"MULTIPLE_ENABLED_ALIASES"'));
    expect(activity, contains('"ICON_SWITCH_FAILED"'));
    expect(activity, contains('PackageManager.DONT_KILL_APP'));
  });

  test('launcher状态识别DEFAULT且切换顺序保持至少一个入口', () async {
    final activity = await File(
      'android/app/src/main/kotlin/com/localaccount/'
      'account_subscription_manager/MainActivity.kt',
    ).readAsString();

    expect(activity, contains('LAUNCHER_PAPER_ARCHIVE to true'));
    for (final constant in <String>[
      'LAUNCHER_SAKURA_MIST',
      'LAUNCHER_CERAMIC_BLUE',
      'LAUNCHER_LILAC_MOON',
      'LAUNCHER_GLACIER_BLUE',
      'LAUNCHER_MIST_CORAL',
      'LAUNCHER_NEON_ZERO',
      'LAUNCHER_OBSIDIAN_GOLD',
      'LEGACY_LAUNCHER_STANDARD',
      'LEGACY_LAUNCHER_PRIME',
      'LEGACY_LAUNCHER_VIVID',
    ]) {
      expect(activity, contains('$constant to false'), reason: constant);
    }
    for (final alias in <String>[
      'CeramicBlueAlias',
      'SakuraMistAlias',
      'PaperArchiveAlias',
      'LilacMoonAlias',
      'GlacierBlueAlias',
      'MistCoralAlias',
      'NeonZeroAlias',
      'ObsidianGoldAlias',
      'StandardAlias',
      'PrimeAlias',
      'VividAlias',
    ]) {
      expect(activity, contains('.launcher.$alias'), reason: alias);
    }
    expect(
      activity,
      contains('PackageManager.COMPONENT_ENABLED_STATE_DEFAULT'),
    );
    expect(activity, contains('LAUNCHER_MANIFEST_DEFAULTS.getValue(variant)'));
    expect(
      activity,
      contains('PackageManager.COMPONENT_ENABLED_STATE_DISABLED_USER'),
    );
    expect(
      activity,
      contains('PackageManager.COMPONENT_ENABLED_STATE_DISABLED_UNTIL_USED'),
    );

    final enableSelected = activity.indexOf(
      'setLauncherComponentEnabled(selectedComponent, enabled = true)',
    );
    final disableOthers = activity.indexOf(
      'aliases.forEach { (variant, component) ->',
      enableSelected,
    );
    final finalInvariant = activity.indexOf(
      'check(enabledLauncherVariants(aliases) == listOf(selected))',
      disableOthers,
    );
    expect(enableSelected, greaterThanOrEqualTo(0));
    expect(disableOthers, greaterThan(enableSelected));
    expect(finalInvariant, greaterThan(disableOthers));
    expect(activity, contains('restoreLauncherFallback(aliases, fallback)'));
    expect(
      activity,
      contains('setLauncherComponentEnabled(component, enabled = true)'),
    );
  });
}
