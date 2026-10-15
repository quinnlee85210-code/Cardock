import '../preferences/appearance_preferences.dart';
import '../theme/cardock_theme_types.dart';
import 'entitlement_model.dart';

enum LimitedRecordType { account, subscription }

final class EntitlementLimitDecision {
  const EntitlementLimitDecision._({
    required this.allowed,
    required this.recordType,
    required this.current,
    required this.maximum,
  });

  const EntitlementLimitDecision.allowed({
    required LimitedRecordType recordType,
    required int current,
    required int maximum,
  }) : this._(
         allowed: true,
         recordType: recordType,
         current: current,
         maximum: maximum,
       );

  const EntitlementLimitDecision.denied({
    required LimitedRecordType recordType,
    required int current,
    required int maximum,
  }) : this._(
         allowed: false,
         recordType: recordType,
         current: current,
         maximum: maximum,
       );

  final bool allowed;
  final LimitedRecordType recordType;
  final int current;
  final int maximum;

  String get usageLabel => switch (recordType) {
    LimitedRecordType.account => '账户 $current/$maximum',
    LimitedRecordType.subscription => '订阅 $current/$maximum',
  };
}

/// Single source of truth for product limits and theme access.
final class EntitlementGuard {
  const EntitlementGuard();

  static const int maxSubscriptions = 5;
  static const int maxAccounts = 15;

  EntitlementLimitDecision accountCreation({
    required ProductEntitlement entitlement,
    required int currentAccounts,
  }) => _creationDecision(
    entitlement: entitlement,
    recordType: LimitedRecordType.account,
    current: currentAccounts,
    maximum: maxAccounts,
  );

  EntitlementLimitDecision subscriptionCreation({
    required ProductEntitlement entitlement,
    required int currentSubscriptions,
  }) => _creationDecision(
    entitlement: entitlement,
    recordType: LimitedRecordType.subscription,
    current: currentSubscriptions,
    maximum: maxSubscriptions,
  );

  EntitlementLimitDecision _creationDecision({
    required ProductEntitlement entitlement,
    required LimitedRecordType recordType,
    required int current,
    required int maximum,
  }) {
    if (entitlement.hasFullVersion || current < maximum) {
      return EntitlementLimitDecision.allowed(
        recordType: recordType,
        current: current,
        maximum: maximum,
      );
    }
    return EntitlementLimitDecision.denied(
      recordType: recordType,
      current: current,
      maximum: maximum,
    );
  }

  bool canRestoreBackup({
    required ProductEntitlement entitlement,
    required int importedAccounts,
    required int importedSubscriptions,
  }) => true;

  bool isThemePremium(CardockThemeFamily family) => family.isPremium;

  bool canUseTheme({
    required ProductEntitlement entitlement,
    required CardockThemeFamily family,
  }) => entitlement.hasFullVersion || !isThemePremium(family);

  bool isThemeLocked({
    required ProductEntitlement entitlement,
    required CardockThemeFamily family,
  }) => !canUseTheme(entitlement: entitlement, family: family);

  bool canUseLauncher({
    required ProductEntitlement entitlement,
    required CardockLauncherFamily family,
  }) =>
      entitlement.hasFullVersion ||
      family == CardockLauncherFamily.paperArchive;

  CardockDesktopIconMode allowedDesktopIconMode({
    required ProductEntitlement entitlement,
    required CardockDesktopIconMode requested,
  }) =>
      requested == CardockDesktopIconMode.followTheme ||
          canUseLauncher(
            entitlement: entitlement,
            family: requested.fixedFamily!,
          )
      ? requested
      : CardockDesktopIconMode.followTheme;

  CardockThemeFamily allowedPersistedTheme({
    required ProductEntitlement entitlement,
    required CardockThemeFamily requested,
  }) => canUseTheme(entitlement: entitlement, family: requested)
      ? requested
      : cardockDefaultThemeFamily;
}
