import 'navigation/vault_navigation.dart';
import '../core/entitlements/distribution_channel.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../core/entitlements/entitlement_guard.dart';
import '../core/entitlements/entitlement_service.dart';
import '../core/entitlements/mock_store_gateway.dart';
import '../core/entitlements/promo_activation_codec.dart';
import '../core/entitlements/promo_activation_config.dart';
import '../core/entitlements/promo_activation_service.dart';
import '../core/entitlements/promo_activation_store.dart';
import '../core/entitlements/purchase_gateway.dart';
import '../core/notifications/reminder_scheduler.dart';
import '../core/platform/app_language_bridge.dart';
import '../core/platform/desktop_icon_controller.dart';
import '../core/platform/notification_reliability.dart';
import '../core/platform/screen_protection.dart';
import '../core/platform/share_intake_bridge.dart';
import '../core/platform/temporary_web_runtime_keeper.dart';
import '../core/preferences/appearance_preferences.dart';
import '../core/preferences/language_preferences.dart';
import '../core/security/vault_contract.dart';
import '../core/temporary_web/temporary_web_address_provider_io.dart';
import '../core/temporary_web/temporary_web_controller.dart';
import '../core/temporary_web/temporary_web_models.dart';
import '../core/temporary_web/temporary_web_server_io.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/cardock_tokens.dart';
import '../features/data_import/infrastructure/app_state_temporary_web_batch_import_port.dart';
import '../features/subscriptions/presentation/share_subscription_draft_page.dart';
import '../features/vault/presentation/vault_gate.dart';
import '../l10n/app_localizations.dart';
import '../l10n/context_l10n.dart';
import 'app_state.dart';
import 'temporary_web_app_state_gateway.dart';

class AccountSubscriptionApp extends StatefulWidget {
  const AccountSubscriptionApp({
    this.vaultStore,
    this.reminderScheduler = const NoopReminderScheduler(),
    this.appearanceStore,
    this.languageController,
    this.desktopIconBridge,
    this.notificationReliabilityService,
    this.screenProtectionService,
    this.shareIntakeBridge,
    this.purchaseGateway,
    this.promoActivationStore,
    this.promoActivationVerifier,
    super.key,
  });

  final VaultStore? vaultStore;
  final ReminderScheduler reminderScheduler;
  final AppearancePreferencesStore? appearanceStore;
  final CardockLanguageController? languageController;
  final DesktopIconBridge? desktopIconBridge;
  final NotificationReliabilityService? notificationReliabilityService;
  final ScreenProtectionService? screenProtectionService;
  final ShareIntakeBridge? shareIntakeBridge;
  final PurchaseGateway? purchaseGateway;
  final PromoActivationStore? promoActivationStore;
  final PromoActivationVerifier? promoActivationVerifier;

  @override
  State<AccountSubscriptionApp> createState() => _AccountSubscriptionAppState();
}

class _AccountSubscriptionAppState extends State<AccountSubscriptionApp>
    with WidgetsBindingObserver {
  late final AppState _appState;
  late final AppStateTemporaryWebVaultGateway _temporaryWebGateway;
  late final TemporaryWebSessionController _temporaryWebController;
  late final ShareIntakeBridge _shareIntakeBridge;
  late final bool _ownsShareIntakeBridge;
  late final CardockAppearanceController _appearanceController;
  late final CardockLanguageController _languageController;
  late final bool _ownsLanguageController;
  late final PromoActivationController _promoActivationController;
  late final ProductEntitlementController _entitlementController;
  static const EntitlementGuard _entitlementGuard = EntitlementGuard();
  final _navigatorKey = GlobalKey<NavigatorState>();
  bool _privacyShieldVisible = false;
  int _gateEpoch = 0;
  final _navigation = VaultNavigation();
  final Stopwatch _monotonicClock = Stopwatch();
  Timer? _backgroundLockTimer;
  int? _backgroundedAtMilliseconds;
  final Set<String> _presentedTemporaryWebApprovalIds = <String>{};
  bool _temporaryWebApprovalDialogScheduled = false;
  String? _activeTemporaryWebApprovalDialogId;
  VaultPhase _lastVaultPhase = VaultPhase.initializing;
  bool _shareIntakeScheduled = false;
  String? _activeShareToken;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _monotonicClock.start();
    _promoActivationController = PromoActivationController(
      store: widget.promoActivationStore ?? MemoryPromoActivationStore(),
      verifier:
          widget.promoActivationVerifier ??
          PromoActivationVerifier(
            publicKeyBytes: PromoActivationConfig.publicKeyBytes,
          ),
    );
    _entitlementController = ProductEntitlementController(
      gateway: widget.purchaseGateway ?? MockStoreGateway(),
      promoEntitlementListenable: _promoActivationController,
    );
    _ownsLanguageController = widget.languageController == null;
    _languageController =
        widget.languageController ??
        CardockLanguageController(store: MemoryLanguagePreferencesStore());
    _appState = AppState(
      vaultStore: widget.vaultStore,
      reminderScheduler: widget.reminderScheduler,
      notificationReliabilityService: widget.notificationReliabilityService,
      screenProtectionService: widget.screenProtectionService,
      entitlementListenable: _entitlementController,
    );
    _ownsShareIntakeBridge = widget.shareIntakeBridge == null;
    _shareIntakeBridge =
        widget.shareIntakeBridge ?? MethodChannelShareIntakeBridge();
    _shareIntakeBridge.addListener(_handleSharePendingAvailable);
    _lastVaultPhase = _appState.vaultPhase;
    _temporaryWebGateway = AppStateTemporaryWebVaultGateway(_appState);
    _temporaryWebController = TemporaryWebSessionController(
      _temporaryWebGateway,
      IoTemporaryWebTransport(),
      const IoTemporaryWebAddressProvider(),
      language: _languageController.language,
      batchImportPort: AppStateTemporaryWebBatchImportPort(appState: _appState),
      runtimeKeeper: createDefaultTemporaryWebRuntimeKeeper(),
    );
    _appState.addListener(_handleAppStateChanged);
    _temporaryWebController.addListener(_handleTemporaryWebStateChanged);
    _appearanceController = CardockAppearanceController(
      store: widget.appearanceStore ?? MemoryAppearancePreferencesStore(),
      desktopIconBridge:
          widget.desktopIconBridge ?? MethodChannelDesktopIconBridge(),
    );
    _languageController.addListener(_applyLanguageToIntegrations);
    _applyLanguageToIntegrations();
    if (_ownsLanguageController) {
      unawaited(_languageController.load());
    }
    _entitlementController.addListener(_enforceThemeEntitlement);
    unawaited(_initializeProductAndAppearance());
    unawaited(_appState.initialize());
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    _languageController.refreshSystemLanguage();
  }

  void _applyLanguageToIntegrations() {
    final language = _languageController.language;
    _temporaryWebController.updateLanguage(language);
    final scheduler = widget.reminderScheduler;
    if (scheduler case final LanguageAwareReminderScheduler languageAware) {
      languageAware.updateLanguage(language);
    }
    unawaited(_syncPlatformLanguage(language));
    unawaited(
      _appState.refreshReminderScheduleForReliability(contentOnly: true),
    );
  }

  Future<void> _syncPlatformLanguage(CardockLanguage language) async {
    try {
      await const CardockPlatformLanguageBridge().updateLanguage(language);
    } on Object {
      // The native bridge is best-effort on unsupported test/desktop hosts.
    }
  }

  Future<void> _initializeProductAndAppearance() async {
    await _promoActivationController.initialize();
    await _entitlementController.initialize();
    await _appearanceController.load(
      sanitizeIconMode: (mode) => _entitlementGuard.allowedDesktopIconMode(
        entitlement: _entitlementController.value,
        requested: mode,
      ),
      sanitizeFamily: (family) => _entitlementGuard.allowedPersistedTheme(
        entitlement: _entitlementController.value,
        requested: family,
      ),
    );
    _enforceThemeEntitlement();
  }

  void _enforceThemeEntitlement() {
    if (!_entitlementController.isInitialized ||
        !_appearanceController.isLoaded) {
      return;
    }
    final allowed = _entitlementGuard.allowedPersistedTheme(
      entitlement: _entitlementController.value,
      requested: _appearanceController.family,
    );
    final allowedIcon = _entitlementGuard.allowedDesktopIconMode(
      entitlement: _entitlementController.value,
      requested: _appearanceController.desktopIconMode,
    );
    if (allowed == _appearanceController.family &&
        allowedIcon == _appearanceController.desktopIconMode) {
      return;
    }
    unawaited(() async {
      await _appearanceController.enforceFamilyFallback(
        allowed,
        desktopIconMode: allowedIcon,
      );
    }());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_entitlementController.distributionChannel !=
          CardockDistributionChannel.development) {
        unawaited(_entitlementController.initialize());
      }
      _backgroundLockTimer?.cancel();
      _backgroundLockTimer = null;
      final backgroundedAt = _backgroundedAtMilliseconds;
      _backgroundedAtMilliseconds = null;
      if (backgroundedAt != null &&
          !_appState.externalInteractionInProgress &&
          _appState.isUnlocked &&
          _monotonicClock.elapsedMilliseconds - backgroundedAt >=
              _appState.autoLockSeconds * 1000) {
        _lockAndResetNavigation(
          stopTemporaryWebSession: false,
          preserveNavigation: true,
        );
      }
      if (mounted && _privacyShieldVisible) {
        setState(() => _privacyShieldVisible = false);
      }
      _scheduleTemporaryWebApprovalDialog();
      _scheduleShareIntake();
      // The recovery record gate prevents ordinary resumes from rebuilding
      // reminders. This is intentionally non-blocking so foreground rendering
      // never waits for a platform diagnostic or notification operation.
      unawaited(_appState.refreshReminderScheduleForSystemTimeRecovery());
      return;
    }

    if (mounted) {
      setState(() => _privacyShieldVisible = true);
    }
    if (state == AppLifecycleState.detached) {
      _lockAndResetNavigation();
      return;
    }
    if (_backgroundedAtMilliseconds != null ||
        _appState.externalInteractionInProgress ||
        !_appState.isUnlocked) {
      return;
    }
    _backgroundedAtMilliseconds = _monotonicClock.elapsedMilliseconds;
    final lockSeconds = _appState.autoLockSeconds;
    if (lockSeconds == 0) {
      _lockAndResetNavigation(
        stopTemporaryWebSession: false,
        preserveNavigation: true,
      );
      return;
    }
    _backgroundLockTimer?.cancel();
    _backgroundLockTimer = Timer(Duration(seconds: lockSeconds), () {
      if (!mounted ||
          _backgroundedAtMilliseconds == null ||
          _appState.externalInteractionInProgress) {
        return;
      }
      _lockAndResetNavigation(
        stopTemporaryWebSession: false,
        preserveNavigation: true,
      );
    });
  }

  void _lockManually() {
    _backgroundLockTimer?.cancel();
    _backgroundLockTimer = null;
    _backgroundedAtMilliseconds = null;
    _lockAndResetNavigation(stopTemporaryWebSession: false);
  }

  void _lockAndResetNavigation({
    bool stopTemporaryWebSession = true,
    bool preserveNavigation = false,
  }) {
    _navigation.lock(
      preserveNavigation ? _appState.navigationVaultScope : null,
    );
    unawaited(_shareIntakeBridge.clearPending());
    _activeShareToken = null;
    if (stopTemporaryWebSession && _temporaryWebController.snapshot.isRunning) {
      _temporaryWebController.stop(TemporaryWebStopReason.phoneLocked);
    }
    _appState.lock();
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    if (mounted) {
      setState(() => _gateEpoch += 1);
    }
  }

  void _enforceTemporaryWebEligibility() {
    if (!_temporaryWebController.snapshot.isRunning) return;
    _temporaryWebController.handleVaultAccessStateChanged();
  }

  void _handleAppStateChanged() {
    final previousPhase = _lastVaultPhase;
    final currentPhase = _appState.vaultPhase;
    _lastVaultPhase = currentPhase;
    if (previousPhase == VaultPhase.unlocked &&
        currentPhase != VaultPhase.unlocked) {
      unawaited(_shareIntakeBridge.clearPending());
      _activeShareToken = null;
    }
    _handleTemporaryWebStateChanged();
    _scheduleShareIntake();
  }

  void _handleTemporaryWebStateChanged() {
    _enforceTemporaryWebEligibility();
    _scheduleTemporaryWebApprovalDialog();
  }

  void _handleSharePendingAvailable() {
    if (_activeShareToken != null) {
      unawaited(_shareIntakeBridge.clearPending());
      return;
    }
    _scheduleShareIntake();
  }

  void _scheduleShareIntake() {
    if (!mounted ||
        _shareIntakeScheduled ||
        _activeShareToken != null ||
        !_appState.isUnlocked ||
        !_appState.hasFullVaultAccess ||
        _appState.isBusy ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
        _activeTemporaryWebApprovalDialogId != null ||
        _temporaryWebApprovalDialogScheduled) {
      return;
    }
    _shareIntakeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _shareIntakeScheduled = false;
      if (mounted) unawaited(_consumeAndPresentShare());
    });
  }

  Future<void> _consumeAndPresentShare() async {
    if (_activeShareToken != null ||
        !_appState.isUnlocked ||
        !_appState.hasFullVaultAccess ||
        _appState.isBusy) {
      return;
    }
    final result = await _shareIntakeBridge.consumePending();
    if (!mounted || result == null) return;
    final payload = result.payload;
    if (payload == null) {
      _showShareMessage(_shareErrorMessage(result.errorCode));
      return;
    }
    if (!_appState.isUnlocked ||
        !_appState.hasFullVaultAccess ||
        _appState.isBusy ||
        _activeShareToken != null) {
      await _shareIntakeBridge.clearPending();
      return;
    }
    _activeShareToken = payload.token;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      _activeShareToken = null;
      return;
    }
    final pageResult = await navigator.push<ShareDraftPageResult>(
      MaterialPageRoute<ShareDraftPageResult>(
        builder: (context) =>
            ShareSubscriptionDraftPage(appState: _appState, payload: payload),
      ),
    );
    if (_activeShareToken == payload.token) _activeShareToken = null;
    if (!mounted) return;
    switch (pageResult) {
      case ShareDraftPageResult.saved:
        _showShareMessage('待完善订阅草稿已加密保存到当前保险库。');
      case ShareDraftPageResult.expired:
        _showShareMessage('分享内容已过期并从内存中清除。');
      case ShareDraftPageResult.canceled ||
          ShareDraftPageResult.cleared ||
          null:
        break;
    }
    _scheduleTemporaryWebApprovalDialog();
    _scheduleShareIntake();
  }

  String _shareErrorMessage(String? code) => switch (code) {
    'EXPIRED' => '分享内容已过期并从内存中清除。',
    'TEXT_TOO_LONG' => '分享的文字过长，未交给 Cardock 处理。',
    _ => '这项分享不是受支持的纯文本或 http(s) 链接。',
  };

  void _showShareMessage(String message) {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.tr(message))));
  }

  void _scheduleTemporaryWebApprovalDialog() {
    final activeApprovalId = _activeTemporaryWebApprovalDialogId;
    if (activeApprovalId != null &&
        !_temporaryWebController.snapshot.pendingApprovals.any(
          (approval) => approval.id == activeApprovalId,
        )) {
      _navigatorKey.currentState?.pop();
      _activeTemporaryWebApprovalDialogId = null;
    }
    if (!mounted ||
        !_appState.isUnlocked ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
        _temporaryWebApprovalDialogScheduled ||
        _activeTemporaryWebApprovalDialogId != null ||
        _activeShareToken != null) {
      return;
    }
    final approval = _temporaryWebController.snapshot.pendingApprovals
        .where((item) => !_presentedTemporaryWebApprovalIds.contains(item.id))
        .firstOrNull;
    if (approval == null) return;
    _temporaryWebApprovalDialogScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _temporaryWebApprovalDialogScheduled = false;
      if (!mounted || !_appState.isUnlocked) return;
      final current = _temporaryWebController.snapshot.pendingApprovals
          .where((item) => item.id == approval.id)
          .firstOrNull;
      if (current != null) {
        unawaited(_showTemporaryWebApprovalDialog(current));
      }
    });
  }

  Future<void> _showTemporaryWebApprovalDialog(
    TemporaryWebApproval approval,
  ) async {
    final context = _navigatorKey.currentContext;
    if (context == null ||
        !_presentedTemporaryWebApprovalIds.add(approval.id) ||
        _activeTemporaryWebApprovalDialogId != null) {
      return;
    }
    _activeTemporaryWebApprovalDialogId = approval.id;
    final approve = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: Text(context.tr(approval.title)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('电脑网页正在等待你的决定。请核对下面内容后直接批准或拒绝。'),
            const SizedBox(height: 12),
            Text(
              context.tr(
                approval.detailTranslationKey ?? approval.detail,
                approval.detailTranslationValues,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('拒绝'),
          ),
          FilledButton(
            key: const ValueKey<String>(
              'temporary-web-approval-dialog-approve',
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              approval.duplicateConfirmationRequired ? '仍然新增' : '批准本次操作',
            ),
          ),
        ],
      ),
    );
    if (_activeTemporaryWebApprovalDialogId == approval.id) {
      _activeTemporaryWebApprovalDialogId = null;
    }
    if (!mounted || approve == null) return;
    final stillPending = _temporaryWebController.snapshot.pendingApprovals.any(
      (item) => item.id == approval.id,
    );
    if (!stillPending) return;
    if (approve) {
      await _temporaryWebController.approve(approval.id);
    } else {
      unawaited(_temporaryWebController.reject(approval.id));
    }
    _scheduleTemporaryWebApprovalDialog();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _languageController.removeListener(_applyLanguageToIntegrations);
    _backgroundLockTimer?.cancel();
    _monotonicClock.stop();
    _appState.removeListener(_handleAppStateChanged);
    _temporaryWebController.removeListener(_handleTemporaryWebStateChanged);
    _shareIntakeBridge.removeListener(_handleSharePendingAvailable);
    unawaited(_shareIntakeBridge.clearPending());
    if (_ownsShareIntakeBridge) _shareIntakeBridge.dispose();
    _temporaryWebController.dispose();
    _entitlementController.removeListener(_enforceThemeEntitlement);
    _entitlementController.dispose();
    _promoActivationController.dispose();
    _appState.dispose();
    _appearanceController.dispose();
    if (_ownsLanguageController) {
      _languageController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _languageController,
      builder: (context, child) => CardockLanguageScope(
        controller: _languageController,
        child: ListenableBuilder(
          listenable: _appearanceController,
          builder: (context, child) => PromoActivationScope(
            controller: _promoActivationController,
            child: ProductEntitlementScope(
              controller: _entitlementController,
              child: CardockAppearanceScope(
                controller: _appearanceController,
                child: MaterialApp(
                  onGenerateTitle: (context) =>
                      AppLocalizations.of(context).appTitle,
                  debugShowCheckedModeBanner: false,
                  locale: _languageController.locale,
                  supportedLocales: AppLocalizations.supportedLocales,
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  theme: AppTheme.light(
                    family: _appearanceController.family,
                    customTheme: _appearanceController.preferences.customTheme,
                  ),
                  darkTheme: AppTheme.dark(
                    family: _appearanceController.family,
                    customTheme: _appearanceController.preferences.customTheme,
                  ),
                  themeMode: _appearanceController.themeMode,
                  themeAnimationDuration: CardockMotion.themeTransition,
                  themeAnimationCurve: CardockMotion.standard,
                  navigatorKey: _navigatorKey,
                  navigatorObservers: [_navigation],
                  builder: (context, child) => VaultNavigationScope(
                    navigation: _navigation,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ?child,
                        if (_privacyShieldVisible) const _PrivacyShield(),
                      ],
                    ),
                  ),
                  home: ListenableBuilder(
                    listenable: _appState,
                    builder: (context, child) => KeyedSubtree(
                      key: ValueKey<int>(_gateEpoch),
                      child: VaultGate(
                        appState: _appState,
                        temporaryWebController: _temporaryWebController,
                        onManualLock: _lockManually,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PrivacyShield extends StatelessWidget {
  const _PrivacyShield();

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    return ColoredBox(
      key: const ValueKey<String>('privacy-shield'),
      color: palette.background,
      child: Center(
        child: Icon(Icons.lock_outline, color: palette.textPrimary, size: 56),
      ),
    );
  }
}
