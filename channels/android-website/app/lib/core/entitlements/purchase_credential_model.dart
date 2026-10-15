import 'distribution_channel.dart';

enum PurchaseCredentialSource {
  none,
  website,
  googlePlay,
  appStore,
  promotion,
  developmentSimulation,
  unknownStore,
}

enum InstallationAuthorizationState { notConfigured, pending, active, invalid }

final class PurchaseCredentialSnapshot {
  const PurchaseCredentialSnapshot({
    required this.source,
    required this.authorizationState,
    this.orderReference,
    this.purchasedOn,
    this.verifiedOn,
    this.amountMinor,
    this.currency,
    this.authorizationId,
    this.remainingSlotsAtIssue,
  });

  const PurchaseCredentialSnapshot.none()
    : this(
        source: PurchaseCredentialSource.none,
        authorizationState: InstallationAuthorizationState.notConfigured,
      );

  factory PurchaseCredentialSnapshot.runtime({
    required bool hasStorePurchase,
    required bool isPromoActivated,
    required bool debugOverrideAvailable,
    required CardockDistributionChannel distributionChannel,
  }) {
    if (hasStorePurchase) {
      return PurchaseCredentialSnapshot(
        source: switch (distributionChannel) {
          CardockDistributionChannel.website =>
            PurchaseCredentialSource.website,
          CardockDistributionChannel.googlePlay =>
            PurchaseCredentialSource.googlePlay,
          CardockDistributionChannel.appStore =>
            PurchaseCredentialSource.appStore,
          CardockDistributionChannel.unsupported =>
            PurchaseCredentialSource.none,
          CardockDistributionChannel.development =>
            debugOverrideAvailable
                ? PurchaseCredentialSource.developmentSimulation
                : PurchaseCredentialSource.unknownStore,
        },
        authorizationState: InstallationAuthorizationState.active,
      );
    }
    if (isPromoActivated &&
        distributionChannel == CardockDistributionChannel.development) {
      return const PurchaseCredentialSnapshot(
        source: PurchaseCredentialSource.promotion,
        authorizationState: InstallationAuthorizationState.active,
      );
    }
    return PurchaseCredentialSnapshot(
      source: switch (distributionChannel) {
        CardockDistributionChannel.website => PurchaseCredentialSource.website,
        CardockDistributionChannel.googlePlay =>
          PurchaseCredentialSource.googlePlay,
        CardockDistributionChannel.appStore =>
          PurchaseCredentialSource.appStore,
        CardockDistributionChannel.unsupported => PurchaseCredentialSource.none,
        CardockDistributionChannel.development => PurchaseCredentialSource.none,
      },
      authorizationState: InstallationAuthorizationState.notConfigured,
    );
  }

  final PurchaseCredentialSource source;
  final InstallationAuthorizationState authorizationState;
  final String? orderReference;
  final DateTime? purchasedOn;
  final DateTime? verifiedOn;
  final int? amountMinor;
  final String? currency;
  final String? authorizationId;

  /// A historical value carried by the last website credential.
  ///
  /// It is never described as the website's live remaining quota.
  final int? remainingSlotsAtIssue;
}
