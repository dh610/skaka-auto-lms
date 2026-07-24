import 'package:flutter/services.dart';

import '../application/alarm_sound_picker.dart';
import '../domain/alarm_settings.dart';

class PlatformAlarmSoundPicker implements AlarmSoundPicker {
  const PlatformAlarmSoundPicker();

  static const _channel = MethodChannel('skala_attendance/alarm');

  @override
  Future<AlarmSound?> pick(AlarmSound current) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'pickAlarmSound',
      {'uri': current.uri},
    );
    if (result == null) return null;
    final label = result['label'];
    final uri = result['uri'];
    if (label is! String || label.isEmpty) {
      return const AlarmSound.systemDefault();
    }
    return AlarmSound(
      uri: uri is String && uri.isNotEmpty ? uri : null,
      label: label,
    );
  }
}
