import 'dart:async';
import 'dart:convert';

import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';
import '../../../l10n/translations_records.dart';

import '../../../core/branding/brand_catalog.dart';
import '../../../core/branding/brand_catalog_loader.dart';
import '../../../core/branding/brand_matcher.dart';
import '../../../core/theme/cardock_tokens.dart';
import '../../../shared/widgets/cardock_platform_icon.dart';
import '../../../shared/widgets/cardock_ui.dart';
import '../../subscriptions/domain/subscription_record.dart';
import '../../subscriptions/presentation/subscription_form_fields.dart';
import '../domain/account_record.dart';
import '../../../core/platform/sensitive_clipboard.dart';
import 'account_custom_fields_editor.dart';
import 'password_generator_sheet.dart';

final class AccountEditorResult {
  const AccountEditorResult({
    required this.account,
    required this.passwordUpdateMode,
    this.initialSubscription,
    this.duplicateApprovedRevision,
  });

  final AccountDraft account;
  final AccountPasswordUpdateMode passwordUpdateMode;
  final SubscriptionDetailsDraft? initialSubscription;
  final int? duplicateApprovedRevision;
  AccountEditorResult copyWith({int? duplicateApprovedRevision}) =>
      AccountEditorResult(
        account: account,
        passwordUpdateMode: passwordUpdateMode,
        initialSubscription: initialSubscription,
        duplicateApprovedRevision:
            duplicateApprovedRevision ?? this.duplicateApprovedRevision,
      );
}

class AccountEditorPage extends StatefulWidget {
  const AccountEditorPage({
    this.existing,
    this.initialDraft,
    this.onDraftChanged,
    this.categoryOptions = accountCategories,
    this.defaultCurrency = 'CNY',
    this.defaultReminderDays = 7,
    this.brandCatalogFuture,
    this.canAddInitialSubscription = true,
    this.onInitialSubscriptionLimitReached,
    this.onBeforeSubmit,
    this.sensitiveClipboard = const PlatformSensitiveClipboard(),
    this.passwordRevealDuration = const Duration(seconds: 30),
    super.key,
  });

  final AccountRecord? existing;
  final Map<String, Object?>? initialDraft;
  final ValueChanged<Map<String, Object?>>? onDraftChanged;
  final List<String> categoryOptions;
  final String defaultCurrency;
  final int defaultReminderDays;
  final bool canAddInitialSubscription;
  final VoidCallback? onInitialSubscriptionLimitReached;
  final Future<AccountEditorResult?> Function(AccountEditorResult result)?
  onBeforeSubmit;
  final SensitiveClipboard sensitiveClipboard;
  final Duration passwordRevealDuration;

  /// Test seam for the bundled offline catalog. Production callers leave this
  /// null and use the packaged asset; no network or business storage is used.
  final Future<CardockBrandCatalog>? brandCatalogFuture;

  @override
  State<AccountEditorPage> createState() => _AccountEditorPageState();
}

class _AccountEditorPageState extends State<AccountEditorPage>
    with WidgetsBindingObserver {
  static const _customCategoryValue = '__custom_account_category__';

  final _formKey = GlobalKey<FormState>();
  final _platformController = TextEditingController();
  final _customCategoryController = TextEditingController();
  final _usernameController = TextEditingController();
  final _loginController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _websiteController = TextEditingController();
  final _notesController = TextEditingController();
  late final SubscriptionFormController _subscriptionController;
  late final Future<CardockBrandCatalog> _brandCatalogFuture;
  late final AccountCustomFieldsController _customFieldsController;
  Timer? _passwordRevealTimer;
  bool _generatedPassword = false;
  bool _submitting = false;
  Timer? _brandSuggestionDebounce;
  List<CardockBrandSuggestion> _brandSuggestions =
      const <CardockBrandSuggestion>[];
  int _brandSuggestionRequest = 0;

  String? _categorySelection;
  AccountPasswordUpdateMode _passwordUpdateMode =
      AccountPasswordUpdateMode.preserve;
  bool _passwordVisible = false;
  bool _hasSubscription = false;
  bool _additionalInformationExpanded = true;
  String? _subscriptionError;
  String? _accountError;

  bool _draftReady = false;
  String? _lastDraft;

  void _publishDraft() {
    if (!_draftReady) return;
    final fields = <String, Object?>{
      'texts': _controllers.map((item) => item.text).toList(),
      'categorySelection': _categorySelection,
      'passwordUpdateMode': _passwordUpdateMode.name,
      'hasSubscription': _hasSubscription,
      'additionalInformationExpanded': _additionalInformationExpanded,
      'subscription': _subscriptionController.exportEditorFields(),
      'customFields': _customFieldsController.exportEditorFields(),
      'generatedPassword': _generatedPassword,
    };
    final encoded = jsonEncode(fields);
    if (encoded == _lastDraft) return;
    _lastDraft = encoded;
    widget.onDraftChanged?.call(fields);
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _publishDraft();
  }

  bool get _isEditing => widget.existing != null;

  List<String> get _categoryOptions {
    final options = <String>[...widget.categoryOptions];
    final existingCategory = widget.existing?.category;
    if (existingCategory != null && !options.contains(existingCategory)) {
      options.add(existingCategory);
    }
    return options;
  }

  Iterable<TextEditingController> get _controllers => <TextEditingController>[
    _platformController,
    _customCategoryController,
    _usernameController,
    _loginController,
    _phoneController,
    _emailController,
    _passwordController,
    _websiteController,
    _notesController,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _customFieldsController = AccountCustomFieldsController(
      widget.existing?.customFields ?? const [],
    );
    _brandCatalogFuture =
        widget.brandCatalogFuture ?? const CardockBrandCatalogLoader().load();
    _subscriptionController = SubscriptionFormController(
      defaultCurrency: widget.defaultCurrency,
      defaultReminderDays: widget.defaultReminderDays,
    );
    final existing = widget.existing;
    if (existing == null) {
      _passwordUpdateMode = AccountPasswordUpdateMode.replace;
    } else {
      _platformController.text = existing.platformName;
      _usernameController.text = existing.username ?? '';
      _loginController.text = existing.loginAccount ?? '';
      _phoneController.text = existing.boundPhone ?? '';
      _emailController.text = existing.boundEmail ?? '';
      _websiteController.text = existing.website ?? '';
      _notesController.text = existing.notes ?? '';

      final category = existing.category;
      if (category != null && _categoryOptions.contains(category)) {
        _categorySelection = category;
      } else if (category != null) {
        _categorySelection = _customCategoryValue;
        _customCategoryController.text = category;
      }
    }
    final draft = widget.initialDraft;
    if (draft != null) {
      final texts = draft['texts'];
      final controllers = _controllers.toList();
      if (texts is List && texts.length == controllers.length) {
        for (var index = 0; index < texts.length; index++) {
          if (texts[index] is String) {
            controllers[index].text = texts[index] as String;
          }
        }
      }
      if (draft['categorySelection'] case final String value) {
        _categorySelection = value;
        if (value != _customCategoryValue &&
            !_categoryOptions.contains(value)) {
          _categorySelection = _customCategoryValue;
          _customCategoryController.text = value;
        }
      }
      _passwordUpdateMode =
          AccountPasswordUpdateMode.values
              .where((v) => v.name == draft['passwordUpdateMode'])
              .firstOrNull ??
          _passwordUpdateMode;
      _hasSubscription =
          draft['hasSubscription'] == true && widget.canAddInitialSubscription;
      _additionalInformationExpanded =
          draft['additionalInformationExpanded'] != false;
      if (draft['subscription'] case final Map<String, Object?> fields) {
        _subscriptionController.restoreEditorFields(fields);
      }
    }
    _customFieldsController.restoreEditorFields(draft?['customFields']);
    _generatedPassword = draft?['generatedPassword'] == true;
    _draftReady = true;
    for (final controller in [
      ..._controllers,
      ..._subscriptionController.textControllers,
    ]) {
      controller.addListener(_publishDraft);
    }
    _subscriptionController.onDraftChanged = _publishDraft;
    _customFieldsController.onDraftChanged = _publishDraft;
    _platformController.addListener(_onPlatformNameChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _passwordRevealTimer?.cancel();
    _draftReady = false;
    _lastDraft = null;
    for (final controller in [
      ..._controllers,
      ..._subscriptionController.textControllers,
    ]) {
      controller.removeListener(_publishDraft);
    }
    _subscriptionController.onDraftChanged = null;
    _brandSuggestionDebounce?.cancel();
    _platformController.removeListener(_onPlatformNameChanged);
    for (final controller in _controllers) {
      controller
        ..clear()
        ..dispose();
    }
    _subscriptionController.dispose();
    _customFieldsController.dispose();
    super.dispose();
  }

  void _onPlatformNameChanged() {
    _brandSuggestionDebounce?.cancel();
    final request = ++_brandSuggestionRequest;
    final query = _platformController.text.trim();
    if (mounted) {
      setState(() => _brandSuggestions = const <CardockBrandSuggestion>[]);
    }
    if (query.isEmpty) return;
    _brandSuggestionDebounce = Timer(
      const Duration(milliseconds: 160),
      () => _resolveBrandSuggestions(query, request),
    );
  }

  Future<void> _resolveBrandSuggestions(String query, int request) async {
    try {
      final catalog = await _brandCatalogFuture;
      final resolution = CardockBrandMatcher(catalog).resolve(
        query,
        category: _selectedCategory,
        includeSuggestions: true,
        suggestionLimit: 5,
      );
      if (!mounted ||
          request != _brandSuggestionRequest ||
          _platformController.text.trim() != query) {
        return;
      }
      setState(
        () => _brandSuggestions = List<CardockBrandSuggestion>.unmodifiable(
          resolution.suggestions.take(5),
        ),
      );
    } on Object {
      if (mounted && request == _brandSuggestionRequest) {
        setState(() => _brandSuggestions = const <CardockBrandSuggestion>[]);
      }
    }
  }

  void _selectBrandSuggestion(CardockBrandSuggestion suggestion) {
    final canonicalName = suggestion.entry.canonicalName;
    _platformController.value = TextEditingValue(
      text: canonicalName,
      selection: TextSelection.collapsed(offset: canonicalName.length),
    );
    setState(() => _brandSuggestions = const <CardockBrandSuggestion>[]);
  }

  String? get _selectedCategory => _categorySelection == _customCategoryValue
      ? _customCategoryController.text
      : _categorySelection;

  String? get _resolvedPassword {
    if (!_isEditing) {
      return _passwordController.text;
    }
    return switch (_passwordUpdateMode) {
      AccountPasswordUpdateMode.preserve => widget.existing!.password,
      AccountPasswordUpdateMode.replace => _passwordController.text,
      AccountPasswordUpdateMode.clear => null,
    };
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _passwordRevealTimer?.cancel();
      if (mounted) setState(() => _passwordVisible = false);
    }
  }

  void _togglePassword() {
    _passwordRevealTimer?.cancel();
    setState(() => _passwordVisible = !_passwordVisible);
    if (_passwordVisible) {
      _passwordRevealTimer = Timer(widget.passwordRevealDuration, () {
        if (mounted) setState(() => _passwordVisible = false);
      });
    }
  }

  Future<void> _generatePassword() async {
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.9,
        child: PasswordGeneratorSheet(
          sensitiveClipboard: widget.sensitiveClipboard,
          revealDuration: widget.passwordRevealDuration,
        ),
      ),
    );
    if (value == null || !mounted) return;
    _passwordController.text = value;
    setState(() {
      _passwordUpdateMode = AccountPasswordUpdateMode.replace;
      _generatedPassword = true;
      _passwordVisible = false;
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _accountError = null;
      _subscriptionError = null;
    });
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    SubscriptionDetailsDraft? initialSubscription;
    if (!_isEditing && _hasSubscription) {
      try {
        initialSubscription = _subscriptionController.toDraft();
      } on ArgumentError catch (error) {
        setState(() => _subscriptionError = error.message?.toString());
        return;
      }
    }

    try {
      final result = AccountEditorResult(
        account: AccountDraft(
          platformName: _platformController.text,
          category: _selectedCategory,
          username: _usernameController.text,
          loginAccount: _loginController.text,
          boundPhone: _phoneController.text,
          boundEmail: _emailController.text,
          password: _resolvedPassword,
          website: _websiteController.text,
          notes: _notesController.text,
          customFields: _customFieldsController.toFields(),
        ),
        passwordUpdateMode: _passwordUpdateMode,
        initialSubscription: initialSubscription,
      );
      if (_isEditing &&
          _generatedPassword &&
          _resolvedPassword != widget.existing!.password &&
          _resolvedPassword != null &&
          _resolvedPassword!.isNotEmpty) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('确认保存生成的密码'),
            content: const SingleChildScrollView(
              child: Text(generatedPasswordSaveNotice),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('返回核对'),
              ),
              FilledButton(
                key: const ValueKey('confirm-generated-password-save'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('我已知晓，保存记录'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }
      setState(() => _submitting = true);
      final approved = widget.onBeforeSubmit == null
          ? result
          : await widget.onBeforeSubmit!(result);
      if (!mounted) return;
      if (approved != null) {
        Navigator.of(context).pop(approved);
      } else {
        setState(() => _submitting = false);
      }
    } on ArgumentError catch (error) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _accountError = error.message?.toString();
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _submitting = false;
          _accountError = '保存前核对失败，请重试。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? '编辑账号' : '新增账号')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          key: const ValueKey<String>('account-editor-page'),
          padding: const EdgeInsets.fromLTRB(
            CardockLayout.screenHorizontal,
            8,
            CardockLayout.screenHorizontal,
            112,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _TemporaryDataNotice(),
              const SizedBox(height: 20),
              Text('基本信息', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              CardockSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _BrandPreview(
                      name: _platformController.text,
                      category: _selectedCategory,
                      catalogFuture: _brandCatalogFuture,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey<String>('platform-name-field'),
                      controller: _platformController,
                      autofocus: !_isEditing,
                      maxLength: 100,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: context.tr('平台或应用名称 *'),
                        helperText: context.tr('唯一必填项；同一平台可以建立多个账号记录。'),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return context.tr('请输入平台或应用名称');
                        }
                        return null;
                      },
                    ),
                    if (_brandSuggestions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _BrandSuggestionList(
                        suggestions: _brandSuggestions,
                        catalogFuture: _brandCatalogFuture,
                        onSelected: _selectBrandSuggestion,
                      ),
                    ],
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      key: const ValueKey<String>('account-category-field'),
                      initialValue: _categorySelection,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: context.tr('分类（可选）'),
                      ),
                      items: <DropdownMenuItem<String?>>[
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('不分类'),
                        ),
                        for (final category in _categoryOptions)
                          DropdownMenuItem<String?>(
                            value: category,
                            child: Text(
                              localizedAccountCategory(
                                context.l10n.language,
                                category,
                              ),
                              translate: false,
                            ),
                          ),
                        const DropdownMenuItem<String?>(
                          value: _customCategoryValue,
                          child: Text(
                            '自定义分类…',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() => _categorySelection = value);
                      },
                    ),
                    if (_categorySelection == _customCategoryValue) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const ValueKey<String>('custom-category-field'),
                        controller: _customCategoryController,
                        maxLength: 100,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: context.tr('自定义分类 *'),
                          helperText: context.tr('支持中文，例如“学习课程”或“开发者服务”。'),
                        ),
                        validator: (value) {
                          if (_categorySelection == _customCategoryValue &&
                              (value == null || value.trim().isEmpty)) {
                            return context.tr('请输入自定义分类');
                          }
                          return null;
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              CardockSurfaceCard(
                padding: EdgeInsets.zero,
                child: Material(
                  type: MaterialType.transparency,
                  child: ExpansionTile(
                    initiallyExpanded: _additionalInformationExpanded,
                    maintainState: true,
                    tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    leading: CardockSemanticIcon(
                      icon: Icons.manage_accounts_outlined,
                      color: palette.fieldLogin,
                    ),
                    title: const Text('账号与补充信息'),
                    subtitle: const Text('登录资料优先；手机号、邮箱、网址与备注均可留空'),
                    onExpansionChanged: (expanded) {
                      setState(() => _additionalInformationExpanded = expanded);
                    },
                    children: [
                      _PrivateTextField(
                        fieldKey: const ValueKey<String>('username-field'),
                        controller: _usernameController,
                        label: '用户名',
                        keyboardType: TextInputType.text,
                        maxLength: 512,
                        enableSuggestions: true,
                        helperText: '支持中文；可与登录账号分别记录。',
                      ),
                      const SizedBox(height: 12),
                      _PrivateTextField(
                        fieldKey: const ValueKey<String>('login-account-field'),
                        controller: _loginController,
                        label: '登录账号',
                        keyboardType: TextInputType.text,
                        maxLength: 512,
                        enableSuggestions: true,
                        helperText: '支持中文账号；输入法是否学习内容取决于系统设置。',
                      ),
                      const SizedBox(height: 12),
                      _PrivateTextField(
                        fieldKey: const ValueKey<String>('bound-phone-field'),
                        controller: _phoneController,
                        label: '绑定手机号',
                        keyboardType: TextInputType.phone,
                        maxLength: 100,
                      ),
                      const SizedBox(height: 12),
                      _PrivateTextField(
                        fieldKey: const ValueKey<String>('bound-email-field'),
                        controller: _emailController,
                        label: '绑定邮箱',
                        keyboardType: TextInputType.emailAddress,
                        maxLength: 320,
                      ),
                      const SizedBox(height: 12),
                      if (_isEditing) ...[
                        DropdownButtonFormField<AccountPasswordUpdateMode>(
                          key: const ValueKey<String>(
                            'password-update-mode-field',
                          ),
                          initialValue: _passwordUpdateMode,
                          decoration: InputDecoration(
                            labelText: context.tr('登录密码处理'),
                          ),
                          items: [
                            for (final mode in AccountPasswordUpdateMode.values)
                              DropdownMenuItem<AccountPasswordUpdateMode>(
                                value: mode,
                                child: Text(mode.label),
                              ),
                          ],
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() {
                              _passwordUpdateMode = value;
                              _passwordController.clear();
                              _passwordVisible = false;
                            });
                          },
                        ),
                        if (_passwordUpdateMode ==
                            AccountPasswordUpdateMode.clear) ...[
                          const SizedBox(height: 8),
                          Text(
                            '保存后将从本机加密库中移除这个账号的登录密码。',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        if (_passwordUpdateMode ==
                            AccountPasswordUpdateMode.replace)
                          const SizedBox(height: 12),
                      ],
                      if (!_isEditing ||
                          _passwordUpdateMode ==
                              AccountPasswordUpdateMode.replace)
                        TextFormField(
                          key: const ValueKey<String>('password-field'),
                          controller: _passwordController,
                          obscureText: !_passwordVisible,
                          keyboardType: TextInputType.text,
                          maxLength: 4096,
                          autocorrect: false,
                          enableSuggestions: false,
                          enableIMEPersonalizedLearning: false,
                          decoration: InputDecoration(
                            labelText: context.tr(
                              _isEditing ? '新登录密码 *' : '登录密码',
                            ),
                            helperText: context.tr('支持中文、空格和任意字符；仅保存在本机加密库。'),
                            counterText: '',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              key: const ValueKey<String>(
                                'toggle-password-visibility',
                              ),
                              tooltip: context.tr(
                                _passwordVisible ? '隐藏密码' : '显示密码',
                              ),
                              onPressed: _togglePassword,
                              icon: Icon(
                                _passwordVisible
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (_isEditing &&
                                _passwordUpdateMode ==
                                    AccountPasswordUpdateMode.replace &&
                                (value == null || value.isEmpty)) {
                              return context.tr('请输入新登录密码');
                            }
                            return null;
                          },
                        ),
                      const SizedBox(height: 8),
                      const Text(accountGeneratorNotice),
                      OutlinedButton.icon(
                        key: const ValueKey('open-account-password-generator'),
                        onPressed: _generatePassword,
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('生成密码'),
                      ),
                      const SizedBox(height: 12),
                      _PrivateTextField(
                        fieldKey: const ValueKey<String>('website-field'),
                        controller: _websiteController,
                        label: '官方网址或登录网址',
                        keyboardType: TextInputType.text,
                        maxLength: 2048,
                        enableSuggestions: true,
                        helperText: '支持中文域名，并按输入的原文保存在本机。',
                      ),
                      const SizedBox(height: 12),
                      _PrivateTextField(
                        fieldKey: const ValueKey<String>('notes-field'),
                        controller: _notesController,
                        label: '备注',
                        keyboardType: TextInputType.multiline,
                        maxLines: 4,
                        maxLength: 10000,
                        autocorrect: true,
                        enableSuggestions: true,
                        enableIMEPersonalizedLearning: true,
                        helperText: '支持中文、换行和任意字符；请勿填写验证码、恢复码或安全问题答案。',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              AccountCustomFieldsEditor(
                controller: _customFieldsController,
                revealDuration: widget.passwordRevealDuration,
              ),
              if (!_isEditing) ...[
                const SizedBox(height: 20),
                CardockSurfaceCard(
                  padding: EdgeInsets.zero,
                  child: Material(
                    type: MaterialType.transparency,
                    child: SwitchListTile(
                      key: const ValueKey<String>('account-has-subscription'),
                      title: const Text('这个账号已有订阅'),
                      subtitle: const Text('开启后，账号和首条订阅会一次性加密保存。'),
                      value: _hasSubscription,
                      onChanged: (value) {
                        if (value && !widget.canAddInitialSubscription) {
                          widget.onInitialSubscriptionLimitReached?.call();
                          return;
                        }
                        setState(() {
                          _hasSubscription = value;
                          _subscriptionError = null;
                        });
                      },
                    ),
                  ),
                ),
              ],
              if (!_isEditing && _hasSubscription) ...[
                const SizedBox(height: 12),
                CardockSurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '首条订阅信息',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      SubscriptionFormFields(
                        keyPrefix: 'initial-subscription',
                        controller: _subscriptionController,
                        allowStatus: false,
                      ),
                      if (_subscriptionError != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _subscriptionError!,
                          key: const ValueKey<String>(
                            'initial-subscription-error',
                          ),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (_accountError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _accountError!,
                  key: const ValueKey<String>('account-editor-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            CardockLayout.screenHorizontal,
            10,
            CardockLayout.screenHorizontal,
            12,
          ),
          child: FilledButton.icon(
            key: const ValueKey<String>('save-account-button'),
            onPressed: _submitting ? null : _submit,
            icon: const Icon(Icons.save_outlined),
            label: Text(_isEditing ? '保存修改' : '加密保存'),
          ),
        ),
      ),
    );
  }
}

class _BrandPreview extends StatelessWidget {
  const _BrandPreview({
    required this.name,
    required this.category,
    required this.catalogFuture,
  });

  final String name;
  final String? category;
  final Future<CardockBrandCatalog> catalogFuture;

  @override
  Widget build(BuildContext context) {
    final displayName = name.trim();
    return Semantics(
      container: true,
      label: displayName.isEmpty
          ? context.tr('离线品牌预览，等待输入平台名称')
          : context.tr('离线品牌预览，{name}', <String, Object?>{'name': displayName}),
      child: Row(
        key: const ValueKey<String>('account-brand-preview'),
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CardockResolvedPlatformIcon(
            key: const ValueKey<String>('account-brand-preview-icon'),
            name: displayName,
            category: category,
            size: 48,
            role: CardockPlatformIconRole.account,
            catalogFuture: catalogFuture,
            semanticLabel: displayName.isEmpty
                ? context.tr('平台品牌预览图标')
                : context.tr('{name}图标', <String, Object?>{
                    'name': displayName,
                  }),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('离线品牌预览', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  displayName.isEmpty ? '输入名称后实时匹配，未命中时使用字母标。' : displayName,
                  translate: displayName.isEmpty,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandSuggestionList extends StatelessWidget {
  const _BrandSuggestionList({
    required this.suggestions,
    required this.catalogFuture,
    required this.onSelected,
  });

  final List<CardockBrandSuggestion> suggestions;
  final Future<CardockBrandCatalog> catalogFuture;
  final ValueChanged<CardockBrandSuggestion> onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey<String>('account-brand-suggestions'),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CardockRadius.control),
        side: BorderSide(color: context.cardockTheme.palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Text('离线候选（仅在点选后替换输入）'),
          ),
          for (final suggestion in suggestions)
            ListTile(
              key: ValueKey<String>(
                'account-brand-suggestion-${suggestion.entry.brandId}',
              ),
              minTileHeight: 48,
              leading: CardockResolvedPlatformIcon(
                name: suggestion.entry.canonicalName,
                size: 32,
                catalogFuture: catalogFuture,
                semanticLabel: context.tr('{name}图标', <String, Object?>{
                  'name': suggestion.entry.canonicalName,
                }),
              ),
              title: Text(
                suggestion.entry.canonicalName,
                translate: false,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: const Text('模糊候选，不会自动绑定'),
              trailing: const Icon(Icons.arrow_forward_rounded),
              onTap: () => onSelected(suggestion),
            ),
        ],
      ),
    );
  }
}

class _TemporaryDataNotice extends StatelessWidget {
  const _TemporaryDataNotice();

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;

    return CardockSurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardockSemanticIcon(
            icon: Icons.lock_outline_rounded,
            color: palette.statusNormal,
            size: 36,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '记录只会写入本机加密库，不会上传。除平台名称外，其余字段均可留空。',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivateTextField extends StatelessWidget {
  const _PrivateTextField({
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.keyboardType,
    this.maxLines = 1,
    this.maxLength,
    this.helperText,
    this.autocorrect = false,
    this.enableSuggestions = false,
    this.enableIMEPersonalizedLearning = false,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final TextInputType keyboardType;
  final int maxLines;
  final int? maxLength;
  final String? helperText;
  final bool autocorrect;
  final bool enableSuggestions;
  final bool enableIMEPersonalizedLearning;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: fieldKey,
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      maxLength: maxLength,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      enableIMEPersonalizedLearning: enableIMEPersonalizedLearning,
      decoration: InputDecoration(
        labelText: context.tr(label),
        helperText: helperText == null ? null : context.tr(helperText!),
        counterText: '',
      ),
    );
  }
}
