import 'package:flutter/services.dart';

import '../domain/alarm_occurrence.dart';

typedef AlarmActionCallback = void Function(String payload);

abstract interface class AndroidAlarmPlatform {
  Future<void> initialize(AlarmActionCallback onAction);

  Future<void> sync(List<AlarmOccurrence> occurrences);

  Future<String?> takeLaunchPayload();

  Future<bool?> canUseFullScreenIntent();

  Future<void> openFullScreenIntentSettings();
}

class MethodChannelAndroidAlarmPlatform implements AndroidAlarmPlatform {
  MethodChannelAndroidAlarmPlatform([
    this._channel = const MethodChannel('skala_attendance/alarm'),
  ]);

  final MethodChannel _channel;

  @override
  Future<void> initialize(AlarmActionCallback onAction) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'alarmAction') return;
      final payload = call.arguments;
      if (payload is String && payload.isNotEmpty) onAction(payload);
    });
  }

  @override
  Future<void> sync(List<AlarmOccurrence> occurrences) {
    return _channel.invokeMethod<void>(
      'syncAlarms',
      occurrences.map((occurrence) => occurrence.toPlatformMap()).toList(),
    );
  }

  @override
  Future<String?> takeLaunchPayload() =>
      _channel.invokeMethod<String>('takeLaunchPayload');

  @override
  Future<bool?> canUseFullScreenIntent() =>
      _channel.invokeMethod<bool>('canUseFullScreenIntent');

  @override
  Future<void> openFullScreenIntentSettings() =>
      _channel.invokeMethod<void>('openFullScreenIntentSettings');
}
