import 'browser_password_csv.dart';
import '../security/account_comparison.dart';

import 'import_models.dart';

final class ImportDuplicateDetector {
  const ImportDuplicateDetector();

  List<ImportDuplicateCandidate> detect({
    required List<AccountImportDraft> imported,
    required List<ExistingAccountSummary> existing,
  }) {
    final indexes = _DuplicateIndexes();
    for (final account in existing) {
      indexes.add(_DuplicateReference.existing(account));
    }

    final output = <ImportDuplicateCandidate>[];
    for (final draft in imported) {
      final reference = _DuplicateReference.imported(draft);
      final matches = indexes.find(reference);
      for (final match in matches) {
        if (isBrowserPasswordSourceId(draft.adapterId) &&
            reference.loginExact.isNotEmpty &&
            match.reference.loginExact.isNotEmpty &&
            reference.loginExact != match.reference.loginExact) {
          continue;
        }
        output.add(
          ImportDuplicateCandidate(
            id: _candidateId(draft.originalRowNumber, match.reference),
            importRowNumber: draft.originalRowNumber,
            origin: match.reference.origin,
            confidence: match.confidence,
            matchingFields: match.matchingFields,
            conflictingFields: _conflictingFields(reference, match.reference),
            existingAccountId: match.reference.existing?.id,
            duplicateImportRowNumber:
                match.reference.importedDraft?.originalRowNumber,
            passwordComparison: _passwordComparison(
              reference.password,
              match.reference.password,
            ),
            hasExistingPassword: match.reference.existing?.hasPassword ?? false,
          ),
        );
      }
      indexes.add(reference);
    }
    return List<ImportDuplicateCandidate>.unmodifiable(output);
  }

  String _candidateId(int rowNumber, _DuplicateReference reference) {
    final target = reference.origin == ImportDuplicateOrigin.existingVault
        ? 'existing:${reference.existing!.id}'
        : 'row:${reference.importedDraft!.originalRowNumber}';
    return 'row:$rowNumber|$target';
  }

  Set<String> _conflictingFields(
    _DuplicateReference left,
    _DuplicateReference right,
  ) {
    final conflicts = <String>{};
    void compare(String name, String importedValue, String existingValue) {
      if (importedValue.isEmpty) return;
      if (importedValue != existingValue) conflicts.add(name);
    }

    compare('platformName', left.platform, right.platform);
    compare('loginAccount', left.loginExact, right.loginExact);
    compare('email', left.email, right.email);
    compare('phone', left.phone, right.phone);
    compare('url', left.rawUrl, right.rawUrl);
    compare('password', left.password, right.password);
    compare('notes', left.notes, right.notes);
    return conflicts;
  }

  ImportPasswordComparison _passwordComparison(
    String imported,
    String existing,
  ) {
    if (imported.isEmpty && existing.isEmpty) {
      return ImportPasswordComparison.bothEmpty;
    }
    if (existing.isEmpty) return ImportPasswordComparison.existingEmpty;
    if (imported.isEmpty) return ImportPasswordComparison.importedEmpty;
    return imported == existing
        ? ImportPasswordComparison.same
        : ImportPasswordComparison.different;
  }
}

final class _DuplicateIndexes {
  final Map<String, List<_DuplicateReference>> _high =
      <String, List<_DuplicateReference>>{};
  final Map<String, List<_DuplicateReference>> _medium =
      <String, List<_DuplicateReference>>{};
  final Map<String, List<_DuplicateReference>> _related =
      <String, List<_DuplicateReference>>{};

  void add(_DuplicateReference reference) {
    for (final key in reference.highKeys) {
      _high
          .putIfAbsent(key.value, () => <_DuplicateReference>[])
          .add(reference);
    }
    for (final key in reference.mediumKeys) {
      _medium
          .putIfAbsent(key.value, () => <_DuplicateReference>[])
          .add(reference);
    }
    for (final key in reference.relatedKeys) {
      _related
          .putIfAbsent(key.value, () => <_DuplicateReference>[])
          .add(reference);
    }
  }

  List<_DuplicateMatch> find(_DuplicateReference reference) {
    final builders = <_DuplicateReference, _DuplicateMatchBuilder>{};

    void collect(
      Iterable<_DuplicateKey> keys,
      Map<String, List<_DuplicateReference>> index,
      ImportDuplicateConfidence confidence,
    ) {
      for (final key in keys) {
        final matches = index[key.value];
        if (matches == null) continue;
        for (final match in matches) {
          final builder = builders.putIfAbsent(
            match,
            () => _DuplicateMatchBuilder(match),
          );
          builder.add(confidence, key.matchingField);
        }
      }
    }

    collect(reference.highKeys, _high, ImportDuplicateConfidence.high);
    collect(reference.mediumKeys, _medium, ImportDuplicateConfidence.medium);
    collect(reference.relatedKeys, _related, ImportDuplicateConfidence.related);
    return builders.values.map((builder) => builder.build()).toList();
  }
}

final class _DuplicateMatchBuilder {
  _DuplicateMatchBuilder(this.reference);

  final _DuplicateReference reference;
  ImportDuplicateConfidence confidence = ImportDuplicateConfidence.related;
  final Set<String> matchingFields = <String>{};

  void add(ImportDuplicateConfidence value, String matchingField) {
    if (value.index > confidence.index) confidence = value;
    matchingFields.add(matchingField);
  }

  _DuplicateMatch build() => _DuplicateMatch(
    reference: reference,
    confidence: confidence,
    matchingFields: Set<String>.unmodifiable(matchingFields),
  );
}

final class _DuplicateMatch {
  const _DuplicateMatch({
    required this.reference,
    required this.confidence,
    required this.matchingFields,
  });

  final _DuplicateReference reference;
  final ImportDuplicateConfidence confidence;
  final Set<String> matchingFields;
}

final class _DuplicateReference {
  _DuplicateReference._({
    required this.origin,
    required this.platform,
    required this.loginExact,
    required this.loginFolded,
    required this.email,
    required this.phone,
    required this.domain,
    required this.rawUrl,
    required this.password,
    required this.notes,
    this.existing,
    this.importedDraft,
  });

  factory _DuplicateReference.existing(ExistingAccountSummary account) =>
      _DuplicateReference._(
        origin: ImportDuplicateOrigin.existingVault,
        platform: AccountComparison.platform(account.platformName),
        loginExact: _normalizeText(account.loginAccount),
        loginFolded: _normalizeText(account.loginAccount, lowercase: true),
        email: _normalizeText(account.email, lowercase: true),
        phone: _normalizePhone(account.phone),
        domain: _normalizeDomain(account.url),
        rawUrl: account.url.trim(),
        password: account.password,
        notes: account.notes,
        existing: account,
      );

  factory _DuplicateReference.imported(AccountImportDraft draft) =>
      _DuplicateReference._(
        origin: ImportDuplicateOrigin.currentImport,
        platform: AccountComparison.platform(draft.platformName),
        loginExact: _normalizeText(draft.loginAccount),
        loginFolded: _normalizeText(draft.loginAccount, lowercase: true),
        email: _normalizeText(draft.email, lowercase: true),
        phone: _normalizePhone(draft.phone),
        domain: _normalizeDomain(draft.url),
        rawUrl: draft.url.trim(),
        password: draft.password,
        notes: draft.notes,
        importedDraft: draft,
      );

  final ImportDuplicateOrigin origin;
  final String platform;
  final String loginExact;
  final String loginFolded;
  final String email;
  final String phone;
  final String domain;
  final String rawUrl;
  final String password;
  final String notes;
  final ExistingAccountSummary? existing;
  final AccountImportDraft? importedDraft;

  Iterable<_DuplicateKey> get highKeys sync* {
    // Manual save and import use the same conservative identity analyzer.
    // Import retains its existing additional domain/contact review hints.
    for (final entry in AccountComparison.duplicateKeysFromNormalized(
      platformValue: platform,
      loginValue: loginExact,
      emailValue: email,
      phoneValue: phone,
      domainValue: domain,
    ).entries) {
      yield _DuplicateKey(entry.key, entry.value);
    }
    if (domain.isEmpty) return;
    if (loginExact.isNotEmpty) {
      yield _DuplicateKey('d:$domain|l:$loginExact', 'domain+loginAccount');
    }
    if (email.isNotEmpty) {
      yield _DuplicateKey('d:$domain|e:$email', 'domain+email');
    }
    if (phone.isNotEmpty) {
      yield _DuplicateKey('d:$domain|p:$phone', 'domain+phone');
    }
  }

  Iterable<_DuplicateKey> get mediumKeys sync* {
    if (platform.isNotEmpty) {
      if (loginExact.isNotEmpty) {
        yield _DuplicateKey(
          'n:$platform|l:$loginExact',
          'platformName+loginAccount',
        );
      }
      if (email.isNotEmpty) {
        yield _DuplicateKey('n:$platform|e:$email', 'platformName+email');
      }
      if (phone.isNotEmpty) {
        yield _DuplicateKey('n:$platform|p:$phone', 'platformName+phone');
      }
    }
    if (domain.isNotEmpty && loginFolded.isNotEmpty) {
      yield _DuplicateKey(
        'dc:$domain|l:$loginFolded',
        'domain+caseInsensitiveLoginAccount',
      );
    }
  }

  Iterable<_DuplicateKey> get relatedKeys sync* {
    if (domain.isNotEmpty) yield _DuplicateKey('d:$domain', 'domain');
    if (platform.isNotEmpty) {
      yield _DuplicateKey('n:$platform', 'platformName');
    }
  }
}

final class _DuplicateKey {
  const _DuplicateKey(this.value, this.matchingField);

  final String value;
  final String matchingField;
}

String _normalizeText(String value, {bool lowercase = false}) =>
    lowercase ? AccountComparison.email(value) : AccountComparison.login(value);
String _normalizePhone(String value) => AccountComparison.phone(value);
String _normalizeDomain(String value) => AccountComparison.domain(value);
