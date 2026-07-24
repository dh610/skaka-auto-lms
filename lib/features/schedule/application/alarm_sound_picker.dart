import '../domain/alarm_settings.dart';

abstract interface class AlarmSoundPicker {
  Future<AlarmSound?> pick(AlarmSound current);
}
