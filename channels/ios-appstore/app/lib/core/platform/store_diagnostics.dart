import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/context_l10n.dart';

Future<Map<String, Object?>> readStoreDiagnostics() async {
  try {
    return await const MethodChannel('cardock/commercial_license')
            .invokeMapMethod<String, Object?>('storeDiagnostics')
            .timeout(const Duration(seconds: 35)) ??
        {'stage': 'bridge_empty_response'};
  } on MissingPluginException {
    return {'stage': 'bridge_missing'};
  } on TimeoutException {
    return {'stage': 'diagnostic_timeout', 'storefront': 'unknown'};
  } on PlatformException catch (error) {
    // Do not expose message/details: a platform error may carry personal data.
    return {
      'stage': 'bridge_error',
      'code': RegExp(r'^[A-Za-z0-9_.-]{1,100}$').hasMatch(error.code)
          ? error.code
          : 'redacted',
    };
  } on Object {
    return {'stage': 'invalid_diagnostic_response'};
  }
}

Future<void> showStoreDiagnostics(BuildContext context) async {
  final result = readStoreDiagnostics();
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.tr('本地购买诊断')),
      content: SizedBox(
        width: 520,
        child: FutureBuilder<Map<String, Object?>>(
          future: result,
          builder: (context, snapshot) => SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.tr('诊断仅在本机显示；可复制后自行发送。不会发起购买。')),
                const SizedBox(height: 12),
                if (snapshot.data case final data?)
                  SelectableText(
                    const JsonEncoder.withIndent('  ').convert(data),
                  )
                else
                  Text(context.tr('正在查询商店…')),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            final data = await result;
            if (!context.mounted) return;
            await Clipboard.setData(
              ClipboardData(
                text: const JsonEncoder.withIndent('  ').convert(data),
              ),
            );
          },
          child: Text(context.tr('复制')),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('关闭')),
        ),
      ],
    ),
  );
}
