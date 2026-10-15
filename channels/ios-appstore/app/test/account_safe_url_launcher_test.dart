import 'package:account_subscription_manager/core/platform/safe_url_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('无协议、中文域名及端口会规范为外部 https 地址', () {
    expect(normalizeExternalHttpUrl('中文域名.cn/登录入口').scheme, 'https');
    expect(
      normalizeExternalHttpUrl('example.com:8443/path').toString(),
      'https://example.com:8443/path',
    );
    expect(
      normalizeExternalHttpUrl('//example.com/path').toString(),
      'https://example.com/path',
    );
    expect(
      normalizeExternalHttpUrl('http://example.com/path').toString(),
      'http://example.com/path',
    );
  });

  test('拒绝非 http 协议、用户信息、空白与反斜杠混淆', () {
    for (final value in <String>[
      'javascript:alert(1)',
      'file:///tmp/test',
      'data:text/plain,hello',
      'https://user:password@example.com',
      'https://example.com/has space',
      r'https://example.com\@evil.example',
      '',
    ]) {
      expect(
        () => normalizeExternalHttpUrl(value),
        throwsA(isA<FormatException>()),
        reason: value,
      );
    }
  });
}
