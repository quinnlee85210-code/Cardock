import 'dart:async';

import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';
import '../../../l10n/translations_records.dart';

import '../../../app/app_state.dart';
import 'vault_rebuild_page.dart';
import '../../../app/navigation/app_shell.dart';
import '../../../core/preferences/language_preferences.dart';
import '../../../core/security/offline_password_advisor.dart';
import '../../../core/security/vault_recovery.dart';
import '../../../core/temporary_web/temporary_web_controller.dart';
import '../../../core/theme/cardock_tokens.dart';
import '../../../shared/widgets/cardock_ui.dart';

class VaultGate extends StatelessWidget {
  const VaultGate({
    required this.appState,
    required this.onManualLock,
    this.temporaryWebController,
    super.key,
  });

  final AppState appState;
  final VoidCallback onManualLock;
  final TemporaryWebSessionController? temporaryWebController;

  @override
  Widget build(BuildContext context) {
    return switch (appState.vaultPhase) {
      VaultPhase.initializing => const _VaultLoadingPage(),
      VaultPhase.needsSetup => MasterPasswordSetupPage(appState: appState),
      VaultPhase.locked => VaultUnlockPage(appState: appState),
      VaultPhase.unlocked => AppShell(
        appState: appState,
        onManualLock: onManualLock,
        temporaryWebController: temporaryWebController,
      ),
      VaultPhase.error => _VaultErrorPage(appState: appState),
    };
  }
}

class MasterPasswordSetupPage extends StatefulWidget {
  const MasterPasswordSetupPage({required this.appState, super.key});

  final AppState appState;

  @override
  State<MasterPasswordSetupPage> createState() =>
      _MasterPasswordSetupPageState();
}

class _MasterPasswordSetupPageState extends State<MasterPasswordSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _showPassword = false;
  String? _localError;
  String? _passwordGuidance;

  @override
  void dispose() {
    _clearControllers();
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _localError = null);
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final password = _passwordController.text;
    final confirmation = _confirmationController.text;
    _clearControllers();
    FocusScope.of(context).unfocus();

    if (password != confirmation) {
      setState(() => _localError = '两次输入的主密码不一致，请重新输入。');
      return;
    }
    await widget.appState.createVault(password);
  }

  void _clearControllers() {
    _passwordController.clear();
    _confirmationController.clear();
  }

  void _generateOfflinePassword() {
    final generated = OfflinePasswordAdvisor.generate();
    final assessment = OfflinePasswordAdvisor.assess(generated);
    setState(() {
      _passwordController.text = generated;
      _confirmationController.text = generated;
      _showPassword = true;
      _localError = null;
      _passwordGuidance = context.tr(
        '{assessment} 请立即离线保存并核对；应用不会替你保存或找回。',
        <String, Object?>{'assessment': context.tr(assessment.message)},
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = MediaQuery.sizeOf(context).width <= 360
        ? 18.0
        : 24.0;
    return Scaffold(
      key: const ValueKey<String>('vault-setup-page'),
      backgroundColor: Colors.transparent,
      body: _CalmVaultBackground(
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                20,
                horizontalPadding,
                32,
              ),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _VaultBrandHeader(iconSize: 64),
                        const SizedBox(height: 22),
                        CardockSurfaceCard(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '设置本地主密码',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '创建只属于这台设备的本机加密库',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: context
                                          .cardockTheme
                                          .palette
                                          .textSecondary,
                                    ),
                              ),
                              const SizedBox(height: 16),
                              const _VaultInformationText(
                                text:
                                    '主密码只用于解锁本机数据，不会上传，也无法通过短信或邮箱找回。请设置仅用于本应用的高强度主密码，并妥善离线保存。',
                              ),
                              const SizedBox(height: 24),
                              _MasterPasswordField(
                                fieldKey: const ValueKey<String>(
                                  'master-password-field',
                                ),
                                controller: _passwordController,
                                label: '主密码',
                                showPassword: _showPassword,
                                onToggleVisibility: () {
                                  setState(
                                    () => _showPassword = !_showPassword,
                                  );
                                },
                                requireStrongNewPassword: true,
                              ),
                              const SizedBox(height: 16),
                              _MasterPasswordField(
                                fieldKey: const ValueKey<String>(
                                  'master-password-confirmation-field',
                                ),
                                controller: _confirmationController,
                                label: '再次输入主密码',
                                showPassword: _showPassword,
                                onToggleVisibility: () {
                                  setState(
                                    () => _showPassword = !_showPassword,
                                  );
                                },
                                onSubmitted: (_) => _submit(),
                                requireStrongNewPassword: true,
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                key: const ValueKey<String>(
                                  'generate-offline-password',
                                ),
                                onPressed: widget.appState.isBusy
                                    ? null
                                    : _generateOfflinePassword,
                                icon: const Icon(Icons.casino_outlined),
                                label: const Text('离线生成高强度随机密码'),
                              ),
                              if (_passwordGuidance != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  _passwordGuidance!,
                                  translate: false,
                                  key: const ValueKey<String>(
                                    'offline-password-guidance',
                                  ),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                              if (_localError != null) ...[
                                const SizedBox(height: 12),
                                _VaultInlineMessage(
                                  key: const ValueKey<String>(
                                    'vault-local-error',
                                  ),
                                  message: _localError!,
                                ),
                              ],
                              if (widget.appState.errorMessage != null) ...[
                                const SizedBox(height: 12),
                                _VaultInlineMessage(
                                  key: const ValueKey<String>(
                                    'vault-state-error',
                                  ),
                                  message: widget.appState.errorMessage!,
                                ),
                              ],
                              const SizedBox(height: 24),
                              FilledButton.icon(
                                key: const ValueKey<String>(
                                  'create-vault-button',
                                ),
                                onPressed: widget.appState.isBusy
                                    ? null
                                    : _submit,
                                icon: widget.appState.isBusy
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.enhanced_encryption_outlined,
                                      ),
                                label: const Text('创建加密库'),
                              ),
                              const SizedBox(height: 12),
                              const _VaultFootnote(
                                text: '忘记主密码将无法恢复本地记录。创建后可在设置中启用生物识别并导出加密备份。',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class VaultUnlockPage extends StatefulWidget {
  const VaultUnlockPage({required this.appState, super.key});

  final AppState appState;

  @override
  State<VaultUnlockPage> createState() => _VaultUnlockPageState();
}

class _VaultUnlockPageState extends State<VaultUnlockPage> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  bool _showPassword = false;
  int _logoTapCount = 0;
  bool _openingRecovery = false;
  Timer? _logoTapTimer;
  Timer? _cooldownRefreshTimer;

  @override
  void initState() {
    super.initState();
    _cooldownRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !widget.appState.passwordUnlockBlocked) return;
      unawaited(widget.appState.refreshUnlockThrottle());
    });
  }

  @override
  void dispose() {
    _logoTapTimer?.cancel();
    _cooldownRefreshTimer?.cancel();
    _passwordController.clear();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final password = _passwordController.text;
    _passwordController.clear();
    FocusScope.of(context).unfocus();
    await widget.appState.unlock(password);
  }

  Future<void> _quickUnlock() async {
    FocusScope.of(context).unfocus();
    await widget.appState.unlockWithQuickUnlock();
  }

  void _activateRecoveryLogo() {
    if (!widget.appState.hasRecoveryEntryMode(
          VaultRecoveryEntryMode.logoFiveTap,
        ) ||
        _openingRecovery) {
      return;
    }
    _logoTapTimer ??= Timer(const Duration(seconds: 3), _resetLogoTaps);
    _logoTapCount += 1;
    if (_logoTapCount < 5) return;
    _resetLogoTaps();
    unawaited(_openRecovery(VaultRecoveryEntryMode.logoFiveTap));
  }

  void _resetLogoTaps() {
    _logoTapTimer?.cancel();
    _logoTapTimer = null;
    _logoTapCount = 0;
  }

  Future<void> _openRecovery(VaultRecoveryEntryMode requestEntryMode) async {
    if (!widget.appState.hasRecoveryEntryMode(requestEntryMode) ||
        _openingRecovery) {
      return;
    }
    _openingRecovery = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => VaultRecoveryPage(
            appState: widget.appState,
            requestEntryMode: requestEntryMode,
          ),
        ),
      );
    } finally {
      _openingRecovery = false;
      _resetLogoTaps();
    }
  }

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = MediaQuery.sizeOf(context).width <= 360
        ? 18.0
        : 24.0;
    return Scaffold(
      key: const ValueKey<String>('vault-unlock-page'),
      backgroundColor: Colors.transparent,
      body: _CalmVaultBackground(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      24,
                      horizontalPadding,
                      20,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _VaultBrandHeader(
                              iconSize: 72,
                              onBrandActivated:
                                  widget.appState.hasRecoveryEntryMode(
                                    VaultRecoveryEntryMode.logoFiveTap,
                                  )
                                  ? _activateRecoveryLogo
                                  : null,
                            ),
                            const SizedBox(height: 24),
                            CardockSurfaceCard(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    '本地记录已锁定',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '请输入本地主密码。应用离开前台后会保持锁定。',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: context
                                              .cardockTheme
                                              .palette
                                              .textSecondary,
                                        ),
                                  ),
                                  const SizedBox(height: 24),
                                  _MasterPasswordField(
                                    fieldKey: const ValueKey<String>(
                                      'unlock-master-password-field',
                                    ),
                                    controller: _passwordController,
                                    label: '主密码',
                                    showPassword: _showPassword,
                                    minimumLength: 6,
                                    enabled:
                                        !widget
                                            .appState
                                            .passwordUnlockBlocked &&
                                        !widget.appState.isBusy,
                                    onToggleVisibility: () {
                                      setState(
                                        () => _showPassword = !_showPassword,
                                      );
                                    },
                                    onSubmitted: (_) => _submit(),
                                  ),
                                  if (widget.appState.errorMessage != null) ...[
                                    const SizedBox(height: 12),
                                    _VaultInlineMessage(
                                      key: const ValueKey<String>(
                                        'vault-state-error',
                                      ),
                                      message: widget.appState.errorMessage!,
                                    ),
                                  ],
                                  if (widget
                                      .appState
                                      .passwordUnlockBlocked) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      context.tr(
                                        '主密码输入暂缓，约{duration}后可重试；生物识别和已配置的恢复方式仍可使用。',
                                        <String, Object?>{
                                          'duration': _formatCooldown(
                                            widget
                                                .appState
                                                .unlockCooldownRemaining,
                                            context.l10n.language,
                                          ),
                                        },
                                      ),
                                      translate: false,
                                      key: const ValueKey<String>(
                                        'password-unlock-cooldown',
                                      ),
                                      textAlign: TextAlign.center,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                  const SizedBox(height: 24),
                                  FilledButton.icon(
                                    key: const ValueKey<String>(
                                      'unlock-vault-button',
                                    ),
                                    onPressed:
                                        widget.appState.isBusy ||
                                            widget
                                                .appState
                                                .passwordUnlockBlocked
                                        ? null
                                        : _submit,
                                    icon: widget.appState.isBusy
                                        ? const SizedBox.square(
                                            dimension: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.lock_open_outlined),
                                    label: const Text('解锁'),
                                  ),
                                  if (widget.appState.quickUnlockEnabled) ...[
                                    const SizedBox(height: 12),
                                    OutlinedButton.icon(
                                      key: const ValueKey<String>(
                                        'biometric-unlock-button',
                                      ),
                                      onPressed: widget.appState.isBusy
                                          ? null
                                          : _quickUnlock,
                                      icon: const Icon(Icons.fingerprint),
                                      label: const Text('使用指纹或人脸解锁'),
                                    ),
                                  ],
                                  if (widget.appState.hasRecoveryEntryMode(
                                    VaultRecoveryEntryMode.visible,
                                  )) ...[
                                    const SizedBox(height: 8),
                                    TextButton.icon(
                                      key: const ValueKey<String>(
                                        'visible-vault-recovery-entry',
                                      ),
                                      onPressed: widget.appState.isBusy
                                          ? null
                                          : () => _openRecovery(
                                              VaultRecoveryEntryMode.visible,
                                            ),
                                      icon: const Icon(
                                        Icons.help_outline_rounded,
                                      ),
                                      label: const Text('忘记密码？恢复保险库访问'),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            _VaultFootnote(
                              text:
                                  !widget.appState.hasRecoveryEntryMode(
                                    VaultRecoveryEntryMode.visible,
                                  )
                                  ? '主密码不会被保存或显示；请定期导出加密备份，并与备份密码分开保存。'
                                  : '恢复功能不会显示旧密码，只会在选对三道密保并通过本机系统强认证后重设保险库密码。',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: const ValueKey<String>(
                      'vault-controlled-rebuild-entry',
                    ),
                    onPressed: widget.appState.isBusy
                        ? null
                        : () => Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => VaultRebuildPage(
                                appState: widget.appState,
                                onRecovery:
                                    widget.appState.hasRecoveryEntryMode(
                                      VaultRecoveryEntryMode.visible,
                                    )
                                    ? () => _openRecovery(
                                        VaultRecoveryEntryMode.visible,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                    style: TextButton.styleFrom(
                      foregroundColor:
                          context.cardockTheme.palette.textSecondary,
                      minimumSize: const Size(48, 48),
                      textStyle: Theme.of(context).textTheme.bodySmall,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                    ),
                    icon: const Icon(Icons.help_outline_rounded, size: 16),
                    label: const Text('忘记密码或重新开始'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class VaultRecoveryPage extends StatefulWidget {
  const VaultRecoveryPage({
    required this.appState,
    required this.requestEntryMode,
    super.key,
  });

  final AppState appState;
  final VaultRecoveryEntryMode requestEntryMode;

  @override
  State<VaultRecoveryPage> createState() => _VaultRecoveryPageState();
}

class _VaultRecoveryPageState extends State<VaultRecoveryPage> {
  final _formKey = GlobalKey<FormState>();
  final _answerControllers = List<TextEditingController>.generate(
    3,
    (_) => TextEditingController(),
  );
  final _newPasswordController = TextEditingController();
  final _confirmationController = TextEditingController();
  late final List<List<String>> _availableQuestionSets;
  late List<String> _questionIds;
  int _selectedQuestionSetIndex = 0;
  bool _showSensitiveValues = false;
  String? _localError;

  @override
  void initState() {
    super.initState();
    _availableQuestionSets = widget.appState.recoveryQuestionSetsForEntryMode(
      widget.requestEntryMode,
    );
    _questionIds = _availableQuestionSets.isEmpty
        ? <String>[]
        : List<String>.of(_availableQuestionSets.first);
  }

  @override
  void dispose() {
    _clearSensitiveInputs();
    for (final controller in _answerControllers) {
      controller.dispose();
    }
    _newPasswordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  void _clearSensitiveInputs() {
    for (final controller in _answerControllers) {
      controller.clear();
    }
    _newPasswordController.clear();
    _confirmationController.clear();
  }

  void _selectQuestionSet(int index) {
    if (index == _selectedQuestionSetIndex ||
        index < 0 ||
        index >= _availableQuestionSets.length) {
      return;
    }
    for (final controller in _answerControllers) {
      controller.clear();
    }
    setState(() {
      _selectedQuestionSetIndex = index;
      _questionIds = List<String>.of(_availableQuestionSets[index]);
      _localError = null;
    });
  }

  Future<void> _submit() async {
    setState(() => _localError = null);
    if (_questionIds.length != 3 || _questionIds.toSet().length != 3) {
      setState(() => _localError = '当前入口没有可用的密码恢复配置');
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final newPassword = _newPasswordController.text;
    if (newPassword != _confirmationController.text) {
      setState(() => _localError = '两次输入的新密码不一致。');
      return;
    }
    final answers = _answerControllers
        .map((controller) => controller.text)
        .toList(growable: false);
    _clearSensitiveInputs();
    FocusScope.of(context).unfocus();
    final recovered = await widget.appState.recoverMasterPassword(
      questionIds: List<String>.unmodifiable(_questionIds),
      answers: answers,
      newMasterPassword: newPassword,
      requestEntryMode: widget.requestEntryMode,
    );
    if (!mounted) return;
    if (recovered) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    setState(() {
      _localError =
          widget.appState.errorMessage ??
          '无法完成恢复；请核对当前显示的三道问题及对应答案，并通过本机系统强认证。';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey<String>('vault-recovery-page'),
      appBar: AppBar(title: const Text('恢复保险库访问')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CardockSurfaceCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(Icons.security_rounded, size: 48),
                          const SizedBox(height: 12),
                          Text(
                            '旧密码不会被显示',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '下方会直接显示你设置时选择的三道问题。请填写对应答案，再通过本机指纹或安全级人脸。成功后会生成全新数据密钥并重设密码。',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          if (_availableQuestionSets.length > 1) ...[
                            const Text(
                              '此入口有多组已配置的密保问题。请选择要回答的一组；页面不会标明它对应哪个保险库。',
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<int>(
                              key: const ValueKey<String>(
                                'recovery-question-set-selector',
                              ),
                              initialValue: _selectedQuestionSetIndex,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: context.tr('已配置密保问题组'),
                              ),
                              items: [
                                for (
                                  var index = 0;
                                  index < _availableQuestionSets.length;
                                  index++
                                )
                                  DropdownMenuItem<int>(
                                    value: index,
                                    child: Text(
                                      context.tr(
                                        '问题组 {number}',
                                        <String, Object?>{'number': index + 1},
                                      ),
                                      translate: false,
                                    ),
                                  ),
                              ],
                              onChanged: widget.appState.isBusy
                                  ? null
                                  : (value) {
                                      if (value != null) {
                                        _selectQuestionSet(value);
                                      }
                                    },
                            ),
                            const SizedBox(height: 16),
                          ],
                          for (
                            var index = 0;
                            index < _questionIds.length;
                            index++
                          ) ...[
                            InputDecorator(
                              key: ValueKey<String>(
                                'recovery-question-${index + 1}',
                              ),
                              decoration: InputDecoration(
                                labelText: context.tr(
                                  '密保问题 {number}',
                                  <String, Object?>{'number': index + 1},
                                ),
                                prefixIcon: const Icon(
                                  Icons.help_outline_rounded,
                                ),
                              ),
                              child: Text(
                                localizedVaultRecoveryQuestion(
                                  context.l10n.language,
                                  _questionIds[index],
                                ),
                                translate: false,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              key: ValueKey<String>(
                                'recovery-answer-${index + 1}',
                              ),
                              controller: _answerControllers[index],
                              obscureText: !_showSensitiveValues,
                              autocorrect: false,
                              enableSuggestions: false,
                              enableIMEPersonalizedLearning: false,
                              maxLength: 256,
                              decoration: const InputDecoration(
                                labelText: '答案',
                                counterText: '',
                                prefixIcon: Icon(
                                  Icons.question_answer_outlined,
                                ),
                              ),
                              validator: (value) {
                                final length = value?.trim().runes.length ?? 0;
                                if (length < 1 || length > 256) {
                                  return context.tr('请输入该问题的完整答案');
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                          ],
                          _MasterPasswordField(
                            fieldKey: const ValueKey<String>(
                              'recovery-new-master-password',
                            ),
                            controller: _newPasswordController,
                            label: '新保险库密码',
                            showPassword: _showSensitiveValues,
                            requireStrongNewPassword: true,
                            minimumLength: 16,
                            maximumLength: 32,
                            onToggleVisibility: () => setState(
                              () =>
                                  _showSensitiveValues = !_showSensitiveValues,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            key: const ValueKey<String>(
                              'recovery-confirm-master-password',
                            ),
                            controller: _confirmationController,
                            obscureText: !_showSensitiveValues,
                            autocorrect: false,
                            enableSuggestions: false,
                            enableIMEPersonalizedLearning: false,
                            maxLength: 32,
                            decoration: InputDecoration(
                              labelText: context.tr('再次输入新保险库密码'),
                              counterText: '',
                              prefixIcon: const Icon(Icons.password_outlined),
                            ),
                            validator: (value) =>
                                value == _newPasswordController.text
                                ? null
                                : context.tr('两次输入的新密码不一致。'),
                            onFieldSubmitted: (_) => _submit(),
                          ),
                          if (_localError != null) ...[
                            const SizedBox(height: 12),
                            _VaultInlineMessage(
                              key: const ValueKey<String>(
                                'vault-recovery-error',
                              ),
                              message: _localError!,
                            ),
                          ],
                          const SizedBox(height: 20),
                          FilledButton(
                            key: const ValueKey<String>(
                              'submit-vault-recovery',
                            ),
                            onPressed: widget.appState.isBusy ? null : _submit,
                            child: widget.appState.isBusy
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    '验证并重设保险库密码',
                                    textAlign: TextAlign.center,
                                  ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const _VaultFootnote(
                      text: '恢复不会显示旧密码或密保答案，只会在答对当前显示的三道问题并通过本机系统强认证后重设密码。',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MasterPasswordField extends StatelessWidget {
  const _MasterPasswordField({
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.showPassword,
    required this.onToggleVisibility,
    this.onSubmitted,
    this.requireStrongNewPassword = false,
    this.minimumLength = 16,
    this.maximumLength = 128,
    this.enabled = true,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final bool showPassword;
  final VoidCallback onToggleVisibility;
  final ValueChanged<String>? onSubmitted;
  final bool requireStrongNewPassword;
  final int minimumLength;
  final int maximumLength;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: fieldKey,
      controller: controller,
      enabled: enabled,
      obscureText: !showPassword,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: onSubmitted == null
          ? TextInputAction.next
          : TextInputAction.done,
      maxLength: maximumLength,
      onFieldSubmitted: enabled ? onSubmitted : null,
      decoration: InputDecoration(
        labelText: context.tr(label),
        helperText: requireStrongNewPassword && maximumLength == 32
            ? context.tr('密码恢复时，新密码统一为16–32个字符；建议使用大小写字母、数字和符号。')
            : requireStrongNewPassword
            ? context.tr('16–128个字符；建议含大小写字母、数字和符号，或使用本机离线生成。')
            : context.tr('{minimum}到128个字符；输入只在本机验证。', <String, Object?>{
                'minimum': minimumLength,
              }),
        helperMaxLines: 3,
        errorMaxLines: 4,
        counterText: '',
        prefixIcon: const Icon(Icons.password_outlined),
        suffixIcon: IconButton(
          key: ValueKey<String>('$label-visibility'),
          onPressed: enabled ? onToggleVisibility : null,
          tooltip: context.tr(showPassword ? '隐藏密码' : '显示密码'),
          icon: Icon(
            showPassword ? Icons.visibility_off_outlined : Icons.visibility,
          ),
        ),
      ),
      validator: (value) {
        final length = value?.runes.length ?? 0;
        if (length < minimumLength || length > maximumLength) {
          if (requireStrongNewPassword && maximumLength == 32) {
            return context.tr('密码恢复时，新密码统一为16–32个字符；建议使用大小写字母、数字和符号。');
          }
          return context.tr('请输入{minimum}到{maximum}个字符的密码', <String, Object?>{
            'minimum': minimumLength,
            'maximum': maximumLength,
          });
        }
        if (requireStrongNewPassword) {
          final assessment = OfflinePasswordAdvisor.assess(value ?? '');
          return assessment.accepted ? null : context.tr(assessment.message);
        }
        return null;
      },
    );
  }
}

class _VaultLoadingPage extends StatelessWidget {
  const _VaultLoadingPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey<String>('vault-loading-page'),
      backgroundColor: Colors.transparent,
      body: _CalmVaultBackground(
        child: const SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _VaultBrandHeader(iconSize: 76),
                SizedBox(height: 28),
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在打开本机加密库…'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VaultErrorPage extends StatelessWidget {
  const _VaultErrorPage({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey<String>('vault-error-page'),
      backgroundColor: Colors.transparent,
      body: _CalmVaultBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _VaultBrandHeader(iconSize: 72),
                    const SizedBox(height: 24),
                    CardockSurfaceCard(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: 56,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            context.tr(appState.errorMessage ?? '无法访问本机加密存储。'),
                            translate: false,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            key: const ValueKey<String>(
                              'retry-vault-initialize',
                            ),
                            onPressed: appState.isBusy
                                ? null
                                : appState.initialize,
                            icon: const Icon(Icons.refresh),
                            label: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CalmVaultBackground extends StatelessWidget {
  const _CalmVaultBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: context.cardockTheme.palette.calmGradient,
      ),
      child: child,
    );
  }
}

class _VaultInformationText extends StatelessWidget {
  const _VaultInformationText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(CardockRadius.control),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, size: 20, color: palette.fieldPassword),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _VaultInlineMessage extends StatelessWidget {
  const _VaultInlineMessage({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(CardockRadius.control),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: colors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.tr(message),
              translate: false,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _VaultFootnote extends StatelessWidget {
  const _VaultFootnote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

class _VaultBrandHeader extends StatelessWidget {
  const _VaultBrandHeader({required this.iconSize, this.onBrandActivated});

  final double iconSize;
  final VoidCallback? onBrandActivated;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: onBrandActivated != null,
          label: context.tr(
            onBrandActivated == null ? 'Cardock 标志' : 'Cardock 标志按钮',
          ),
          onTap: onBrandActivated,
          child: ExcludeSemantics(
            child: InkResponse(
              key: const ValueKey<String>('vault-brand-mark-action'),
              onTap: onBrandActivated,
              radius: iconSize / 1.5,
              child: SizedBox.square(
                dimension: iconSize < 48 ? 48 : iconSize,
                child: Center(
                  child: CardockBrandMark(
                    showWordmark: false,
                    iconSize: iconSize,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Semantics(
          header: true,
          child: Text(
            'Cardock',
            textAlign: TextAlign.center,
            maxLines: 2,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(height: 1.2),
          ),
        ),
      ],
    );
  }
}

String _formatCooldown(Duration duration, CardockLanguage language) {
  final totalSeconds = (duration.inMilliseconds / 1000).ceil().clamp(0, 1800);
  if (totalSeconds < 60) {
    return switch (language) {
      CardockLanguage.simplifiedChinese => '$totalSeconds秒',
      CardockLanguage.english =>
        totalSeconds == 1 ? '1 second' : '$totalSeconds seconds',
      CardockLanguage.japanese => '$totalSeconds秒',
    };
  }
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return switch (language) {
    CardockLanguage.simplifiedChinese =>
      seconds == 0 ? '$minutes分钟' : '$minutes分$seconds秒',
    CardockLanguage.english =>
      seconds == 0
          ? (minutes == 1 ? '1 minute' : '$minutes minutes')
          : '$minutes m $seconds s',
    CardockLanguage.japanese =>
      seconds == 0 ? '$minutes分' : '$minutes分$seconds秒',
  };
}
