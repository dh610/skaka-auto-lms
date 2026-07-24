class AlarmSound {
  const AlarmSound({required this.uri, required this.label});

  const AlarmSound.systemDefault() : uri = null, label = '시스템 기본 알람음';

  final String? uri;
  final String label;

  factory AlarmSound.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AlarmSound.systemDefault();
    final label = json['label'];
    final uri = json['uri'];
    if (label is! String || label.trim().isEmpty) {
      return const AlarmSound.systemDefault();
    }
    return AlarmSound(
      uri: uri is String && uri.isNotEmpty ? uri : null,
      label: label,
    );
  }

  Map<String, dynamic> toJson() => {'uri': uri, 'label': label};

  @override
  bool operator ==(Object other) =>
      other is AlarmSound && other.uri == uri && other.label == label;

  @override
  int get hashCode => Object.hash(uri, label);
}

class AlarmSettings {
  const AlarmSettings({
    this.sound = const AlarmSound.systemDefault(),
    this.volumePercent = 100,
    this.vibrationEnabled = true,
    this.gradualVolumeEnabled = false,
    this.snoozeMinutes = 5,
    this.maximumSnoozeCount = 3,
  }) : assert(volumePercent >= 0 && volumePercent <= 100),
       assert(
         snoozeMinutes == 1 ||
             snoozeMinutes == 3 ||
             snoozeMinutes == 5 ||
             snoozeMinutes == 10 ||
             snoozeMinutes == 15,
       ),
       assert(
         maximumSnoozeCount == null ||
             (maximumSnoozeCount >= 0 && maximumSnoozeCount <= 10),
       );

  final AlarmSound sound;
  final int volumePercent;
  final bool vibrationEnabled;
  final bool gradualVolumeEnabled;
  final int snoozeMinutes;
  final int? maximumSnoozeCount;

  factory AlarmSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AlarmSettings();
    final volume = json['volumePercent'];
    final snooze = json['snoozeMinutes'];
    final maximum = json['maximumSnoozeCount'];
    final sound = switch (json['sound']) {
      final Map<String, dynamic> value => value,
      _ => null,
    };
    return AlarmSettings(
      sound: AlarmSound.fromJson(sound),
      volumePercent: volume is int && volume >= 0 && volume <= 100
          ? volume
          : 100,
      vibrationEnabled: json['vibrationEnabled'] as bool? ?? true,
      gradualVolumeEnabled: json['gradualVolumeEnabled'] as bool? ?? false,
      snoozeMinutes: snooze is int && const {1, 3, 5, 10, 15}.contains(snooze)
          ? snooze
          : 5,
      maximumSnoozeCount: json.containsKey('maximumSnoozeCount')
          ? maximum == null || (maximum is int && maximum >= 0 && maximum <= 10)
                ? maximum as int?
                : 3
          : 3,
    );
  }

  AlarmSettings copyWith({
    AlarmSound? sound,
    int? volumePercent,
    bool? vibrationEnabled,
    bool? gradualVolumeEnabled,
    int? snoozeMinutes,
    int? maximumSnoozeCount,
    bool clearMaximumSnoozeCount = false,
  }) {
    return AlarmSettings(
      sound: sound ?? this.sound,
      volumePercent: volumePercent ?? this.volumePercent,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      gradualVolumeEnabled: gradualVolumeEnabled ?? this.gradualVolumeEnabled,
      snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
      maximumSnoozeCount: clearMaximumSnoozeCount
          ? null
          : maximumSnoozeCount ?? this.maximumSnoozeCount,
    );
  }

  Map<String, dynamic> toJson() => {
    'sound': sound.toJson(),
    'volumePercent': volumePercent,
    'vibrationEnabled': vibrationEnabled,
    'gradualVolumeEnabled': gradualVolumeEnabled,
    'snoozeMinutes': snoozeMinutes,
    'maximumSnoozeCount': maximumSnoozeCount,
  };

  @override
  bool operator ==(Object other) =>
      other is AlarmSettings &&
      other.sound == sound &&
      other.volumePercent == volumePercent &&
      other.vibrationEnabled == vibrationEnabled &&
      other.gradualVolumeEnabled == gradualVolumeEnabled &&
      other.snoozeMinutes == snoozeMinutes &&
      other.maximumSnoozeCount == maximumSnoozeCount;

  @override
  int get hashCode => Object.hash(
    sound,
    volumePercent,
    vibrationEnabled,
    gradualVolumeEnabled,
    snoozeMinutes,
    maximumSnoozeCount,
  );
}
