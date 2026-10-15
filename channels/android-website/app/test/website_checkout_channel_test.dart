import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:account_subscription_manager/core/entitlements/website_offline_browser.dart';
import 'package:account_subscription_manager/core/entitlements/website_purchase_error.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'purchase passes only the verified installation to the native launcher',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(WebsiteOfflineBrowser.channel, (
            call,
          ) async {
            calls.add(call);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(WebsiteOfflineBrowser.channel, null),
      );
      expect(await WebsiteOfflineBrowser().startPurchase('a' * 64), isTrue);
      expect(calls.single.method, 'startOfflinePurchase');
      expect(calls.single.arguments, {'installationKeySha256': 'a' * 64});
    },
  );
  test(
    'native failure stage is readable and never exposes platform details',
    () {
      final error = PlatformException(
        code: 'CHECKOUT_PREPARE',
        message: 'PRIVATE_VALUE',
      );
      final message = WebsitePurchaseException.from(error).message;
      expect(message, contains('P01'));
      expect(message, isNot(contains('PRIVATE_VALUE')));
    },
  );
}
