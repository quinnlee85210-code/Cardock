enum CardockDistributionChannel {
  development,
  website,
  googlePlay,
  appStore,
  unsupported,
}

extension CardockDistributionChannelValue on CardockDistributionChannel {
  String get wireValue => switch (this) {
    CardockDistributionChannel.development => 'development',
    CardockDistributionChannel.website => 'website',
    CardockDistributionChannel.googlePlay => 'google_play',
    CardockDistributionChannel.appStore => 'app_store',
    CardockDistributionChannel.unsupported => 'unsupported',
  };
  bool get isStore =>
      this == CardockDistributionChannel.googlePlay ||
      this == CardockDistributionChannel.appStore;
}

abstract interface class DistributionAwarePurchaseGateway {
  CardockDistributionChannel get distributionChannel;
}

abstract final class CardockDistributionConfig {
  static const String value = String.fromEnvironment(
    'CARDOCK_DISTRIBUTION',
    defaultValue: 'development',
  );
  static CardockDistributionChannel get channel => parse(value);
  static CardockDistributionChannel parse(String value) => switch (value) {
    'development' => CardockDistributionChannel.development,
    'website' => CardockDistributionChannel.website,
    'google_play' => CardockDistributionChannel.googlePlay,
    'app_store' => CardockDistributionChannel.appStore,
    _ => CardockDistributionChannel.unsupported,
  };
}
