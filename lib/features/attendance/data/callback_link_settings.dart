import 'dart:io';

import 'package:flutter/services.dart';

abstract interface class CallbackLinkSettings {
  Future<bool> isEnabled();

  Future<void> open();
}

class PlatformCallbackLinkSettings implements CallbackLinkSettings {
  PlatformCallbackLinkSettings({bool? isAndroid})
    : _isAndroid = isAndroid ?? Platform.isAndroid;

  static const _channel = MethodChannel('skala_attendance/browser');

  final bool _isAndroid;

  @override
  Future<bool> isEnabled() async {
    if (!_isAndroid) return true;
    return await _channel.invokeMethod<bool>('isAppLinkEnabled') ?? false;
  }

  @override
  Future<void> open() async {
    if (!_isAndroid) return;
    await _channel.invokeMethod<void>('openAppLinkSettings');
  }
}
