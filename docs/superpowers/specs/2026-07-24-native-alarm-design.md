# 출결 일정 네이티브 알람 설계

## 배경

현재 일정 알림은 높은 중요도의 로컬 알림을 지정 시각에 게시한다. 사용자는 알림을
직접 눌러야 앱을 열고 Google 인증을 시작할 수 있다. 출결 시각을 놓치지 않게 하는
앱의 목적을 고려하면, 화면이 꺼졌거나 잠긴 상태에서는 일반 알림보다 기본 시계 앱과
유사한 알람 경험이 적합하다.

Android와 iOS는 백그라운드 실행, 잠금화면 표시, 알람 권한 및 소리 재생 API가
서로 다르다. 일정과 알람 옵션은 Flutter에서 공통으로 관리하되 실제 알람 실행은
각 OS의 공식 네이티브 API로 구현한다.

## 목표

- 앱 프로세스가 종료됐거나 기기가 잠긴 상태에서도 지정 시각에 안정적으로 알린다.
- 일정마다 알람음, 음량, 진동 및 다시 알림 규칙을 설정할 수 있게 한다.
- 사용자가 중지할 때까지 알람음과 진동을 반복한다.
- 알람 중지, 다시 알림 및 Google 인증 시작을 명확히 분리한다.
- 알람 조작만으로 출결 API를 전송하거나 실제 출결 완료로 기록하지 않는다.
- 공통 일정 모델은 Android와 향후 iOS 구현에서 재사용한다.

## 플랫폼 범위와 작업 순서

첫 구현 대상은 현재 배포 플랫폼인 Android다. 현재 출결 상태 UX 브랜치가 실기기
확인과 사용자 승인을 거쳐 `main`에 병합된 뒤 별도 `feat/android-native-alarm`
브랜치에서 구현한다.

iOS 개발을 재개할 때는 별도 브랜치에서 iOS 26 이상의 AlarmKit 구현을 추가한다.
iOS 26 미만에서는 동일한 시스템 알람을 제공할 수 없으므로 기존 일반 로컬 알림만
지원한다. 현재 중단된 iOS 배포 범위를 이 Android 작업에서 암묵적으로 확대하지 않는다.

참고:

- [Android 정확 알람](https://developer.android.com/develop/background-work/services/alarms)
- [Android 전체 화면 알림](https://developer.android.com/develop/ui/views/notifications/time-sensitive)
- [Apple AlarmKit](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit)

## 공통 경계

Flutter 영역은 플랫폼 구현을 직접 알지 않고 다음 공통 경계를 사용한다.

- `AlarmSettings`: 일정별 소리, 음량, 진동 및 다시 알림 옵션
- `AlarmOccurrence`: 일정 ID, 출결 동작, 예정 발생 시각과 설정을 묶은 예약 단위
- `AlarmScheduler`: 발생 건 전체 동기화, 취소 및 플랫폼 권한 상태를 제공하는 인터페이스

Android 구현은 플랫폼 채널 뒤에서 `AlarmManager`를 사용하고, 향후 iOS 구현은 같은
인터페이스 뒤에서 AlarmKit을 사용한다. 일정 편집 화면과 알림 계획 알고리즘은
플랫폼별 실행 세부사항에 의존하지 않는다.

## 공통 알람 설정

각 `AttendanceSchedule`은 다음 알람 설정을 가진다.

| 설정 | 값 | 새 일정 기본값 |
|---|---|---|
| 알람음 | OS 시스템 알람음 URI 또는 시스템 기본값 | 시스템 기본 알람음 |
| 음량 | 기기 알람 음량에 적용할 0~100% 비율 | 100% |
| 진동 | 켜기 또는 끄기 | 켜기 |
| 점점 크게 | 켜기 또는 끄기 | 끄기 |
| 다시 알림 간격 | 1, 3, 5, 10, 15분 | 5분 |
| 최대 다시 알림 횟수 | 0~10회 또는 제한 없음 | 3회 |
| 볼륨 버튼 동작 | 다시 알림, 끄기, 아무 동작 안 함 | 다시 알림 |

알람음은 Android 시스템 알람음 선택기를 사용한다. 앱이 시스템 전체 알람 음량을
임의로 변경하지 않고, 선택한 일정별 비율을 현재 알람 스트림 음량에 곱한다.
`점점 크게`를 사용하면 반복 재생의 첫 30초 동안 0에서 설정 음량까지 선형으로
증가시킨다.

기존 저장 일정에는 위 기본값을 적용해 하위 호환한다. 새 일정은 마지막으로 저장한
알람 설정을 초기값으로 사용하되 사용자가 저장하기 전에는 다른 일정에 영향을 주지
않는다.

## 일정 편집 화면

기존 반복 규칙과 시각 아래에 `알람 설정` 구역을 둔다.

```text
알람음                 시스템 기본 알람음 >
음량                   ───────── 100%
진동                   켜짐
점점 크게              꺼짐
다시 알림              5분 · 최대 3회 >
볼륨 버튼              다시 알림 >
```

알람음 행은 OS 선택기를 연다. 진동과 점점 크게는 스위치로 제공하고, 다시 알림과
볼륨 버튼은 선택창에서 변경한다. 설정은 일정과 함께 저장되며 일정 중복 판정에는
영향을 주지 않는다.

## Android 실행 구조

Android는 기존 일반 로컬 알림 예약 대신 사용자 알람에 맞는 네이티브 경로를 사용한다.

```text
Flutter 일정과 알람 설정 저장
→ 플랫폼 채널로 향후 발생 건 최대 60개 전달
→ AlarmManager.setAlarmClock()로 각 발생 건 예약
→ AlarmReceiver가 예약 payload 검증
→ AlarmRingingService를 foreground로 시작
→ 선택한 알람음과 진동 반복
→ 전체 화면 알람 또는 확장 heads-up 알림 표시
```

네이티브 저장소에는 알람 실행에 필요한 최소 정보만 미러링한다.

- 일정 ID
- 출결 동작
- 예정 발생 시각
- 알람 설정
- 다시 알림 사용 횟수

사용자 이름, Google 인증 정보, 토큰 및 출결 상태는 저장하지 않는다.

`AlarmRingingService`는 알람용 오디오 속성과 진동을 사용하고, 실행 중임을 알리는
ongoing 알림을 유지한다. 알림 채널 자체의 소리는 끄고 서비스에서 선택한 알람음을
한 번만 재생해 이중 소리를 방지한다.

## 알람 화면과 동작

잠금화면 알람은 개인정보 없이 예정 시각과 동작만 표시한다.

```text
오전 8:50
입실 시간입니다

[끄기]              [다시 알림]
[Google 인증 시작]
```

### 끄기

- 서비스, 소리, 진동 및 현재 ongoing 알림을 종료한다.
- 일정 발생 건을 실제 출결 완료로 표시하지 않는다.
- 인증 흐름도 시작하지 않는다.
- 홈에서는 기존 규칙대로 시간이 지나면 `시간 지남`으로 보인다.

### 다시 알림

- 현재 소리와 진동을 중지한다.
- 설정한 간격 뒤 동일 발생 건의 일회성 알람을 예약한다.
- 사용 횟수를 증가시키고 최대 횟수에 도달하면 다음 알람 화면에서 버튼을 숨긴다.
- 최대 횟수에 도달해도 알람은 사용자가 끄거나 인증을 시작할 때까지 계속 울린다.

### Google 인증 시작

- 먼저 알람을 종료한다.
- 잠긴 기기에서는 사용자 인증과 잠금 해제를 요구한다.
- 기존 알림 payload 처리 경로로 앱을 열어 현재 저장 일정과 ID, 동작, 발생 시각을
  다시 검증한다.
- 검증에 성공한 경우에만 기존 Google 인증 흐름을 시작한다.
- 알람 화면이나 네이티브 서비스가 출결 API를 직접 호출하지 않는다.

볼륨 버튼은 일정 설정에 따라 다시 알림, 끄기 또는 무동작으로 처리한다. 전원 버튼은
OS 기본 동작을 유지하며 출결이나 다시 알림 상태를 변경하지 않는다.

## 화면 상태에 따른 표시

- 화면 꺼짐 또는 잠금: 화면을 켜고 잠금화면 위에 전체 화면 알람 표시
- 다른 앱 사용 중: OS 정책을 존중해 전체 화면을 강제하지 않고 확장 heads-up 알림
  표시
- 출결 앱 사용 중: 알람 화면을 표시하되 현재 저장 중인 일정 변경을 손상시키지 않음
- 전체 화면 권한 없음: 소리와 진동은 유지하고 확장 알림의 동작 버튼으로 대체

사용자가 기기 사용 중일 때 전체 화면을 강제로 탈취하지 않는 Android 정책을 UX
원칙으로 수용한다.

## 권한과 초기 설정

기존 Android 필수 설정 세 가지는 유지한다.

1. 일반 알림
2. 정확한 알람
3. 인증 후 앱 복귀 링크

Android 14 이상에서는 다음을 네 번째 필수 설정으로 추가한다.

4. 전체 화면 알림

앱 시작과 복귀 때 네 설정을 확인한다. 전체 화면 권한이 해제되면 초기 설정으로
돌아가 이유와 설정 경로를 안내한다. 권한을 복구하면 최신 일정 기준으로 전체 알람을
재예약한다. 플랫폼 오류로 전체 화면이 실행되지 않는 경우에도 소리, 진동 및 확장
알림은 가능한 범위에서 유지한다.

방해 금지 모드 우회용 별도 권한이나 배터리 최적화 제외 권한은 요구하지 않는다.
알람 오디오 속성과 사용자가 지정한 시스템 설정을 존중한다.

## 예약 일관성과 복구

- Flutter 일정 저장을 먼저 완료한 뒤 네이티브 알람 동기화를 실행한다.
- 동기화는 한 번에 하나만 실행하고, 진행 중 일정이 바뀌면 최신 상태로 한 번 더
  실행한다.
- 앱 시작, 일정 변경, 기기 재부팅, 앱 업데이트 및 권한 복구 시 전체 재예약한다.
- 기존 최대 60개 선등록과 공휴일 제외 원칙은 유지한다.
- 예약 payload는 실행 직전에 현재 네이티브 미러와 다시 대조한다.
- 변경·삭제·비활성화됐거나 예정 시각이 달라진 발생 건은 울리지 않는다.
- 다시 알림은 원래 반복 일정과 분리된 해당 발생 건 전용 일회성 알람이다.
- 사용자가 원래 일정을 삭제하거나 비활성화하면 남은 다시 알림도 함께 취소한다.

## iOS AlarmKit 연결

향후 iOS 26 이상에서는 공통 알람 설정과 발생 건을 AlarmKit 구성으로 변환한다.

- 일정: 한 번 또는 주간 반복 AlarmKit schedule
- 다시 알림: post-alert countdown
- 중지·다시 알림: AlarmKit 시스템 버튼과 App Intent
- 앱 열기: 사용자 지정 보조 버튼으로 출결 앱 열기
- 알람음: 시스템 기본값 또는 앱이 제공할 수 있는 사용자 지정 sound
- 표시: Lock Screen, Dynamic Island, StandBy 및 연결된 Apple Watch

iOS는 Android foreground service나 전체 화면 권한을 재사용하지 않는다. AlarmKit
권한, App Intent 및 필요한 경우 Live Activity/Widget Extension을 별도 구현한다.

## 오류와 안전 원칙

- 네이티브 예약 실패 시 일정은 저장된 상태를 유지하고 홈과 일정 화면에 재동기화
  오류를 표시한다.
- 알람음 URI를 더 이상 열 수 없으면 시스템 기본 알람음으로 대체한다.
- 서비스 시작 또는 오디오 재생 실패 시 진동과 확장 알림을 가능한 범위에서 유지한다.
- 앱 프로세스 종료, 재부팅 또는 업데이트 후에도 저장된 발생 건을 복구한다.
- 알람 중지·다시 알림은 출결 성공으로 오인하지 않는다.
- 실제 출결 API는 기존 Flutter 인증·확인 흐름에서 사용자 의사에 따라 실행한다.
- 자동 테스트나 실기기 검증을 위해 실제 출결 동작을 보내지 않는다.

## 검증

### 자동 테스트

- 기존 일정 JSON에 기본 알람 설정이 적용되는지
- 일정별 알람 설정 저장과 복원이 되는지
- 최대 60개 발생 건과 각 설정이 네이티브 예약 요청으로 변환되는지
- 동기화 중 변경이 최신 예약으로 다시 반영되는지
- 중지, 다시 알림 및 인증 시작 payload가 서로 구분되는지
- 다시 알림 간격과 최대 횟수가 정확한지
- 변경·삭제·비활성화된 발생 건과 다시 알림이 울리지 않는지
- 권한 해제와 복구 후 전체 재예약되는지
- Android와 iOS 구현이 동일한 공통 인터페이스 계약을 따르는지

### Android 실기기

- 화면 꺼짐, 잠금, 잠금 해제 및 다른 앱 사용 중 표시
- 앱 프로세스 종료 후 알람 실행
- 선택한 소리, 음량, 진동 및 점점 크게
- 끄기 전까지 반복 재생
- 다시 알림 간격, 횟수 제한 및 볼륨 버튼 동작
- 재부팅과 앱 업데이트 후 예약 복구
- 일반 알림, 정확 알람 및 전체 화면 권한 각각의 해제·복구
- 알람에서 인증 시작 후 기존 App Link 복귀
- 기존 사용자 정보와 일정 유지

실기기에서는 가까운 테스트 전용 일정을 사용하되 Google 인증 이후 실제 출결 동작은
보내지 않는다.

## 구현 계획 및 사용자 검증 게이트

이 절은 별도 계획 문서를 만들지 않고 본 설계를 실제 구현 순서의 단일 기준으로
사용하기 위한 체크리스트다. 첫 번째 완료 지점은 Android release APK를 실기기에
설치해 사용자가 직접 알람을 확인하는 시점이다. 전체 회귀 검증과 별도 코드 점검은
사용자가 기능을 확인한 뒤 진행한다.

### 전역 제약

- 이번 브랜치에서는 Android만 네이티브 알람으로 전환한다.
- iOS는 기존 `flutter_local_notifications` 예약을 유지한다.
- 최대 60개 선등록, 공휴일 제외, 일정 저장 후 직렬 재동기화 원칙을 유지한다.
- 네이티브 영역에는 이름, Google 인증 정보, 토큰 및 출결 상태를 저장하지 않는다.
- 알람 동작이나 테스트가 실제 출결 API를 자동 전송하지 않는다.
- Android 14 이상 전체 화면 알림 권한은 일반 알림·정확 알람·앱 복귀 링크와 함께
  필수 설정으로 취급한다.

### Task 1: 공통 알람 설정과 저장 호환성

**파일**

- 생성: `lib/features/schedule/domain/alarm_settings.dart`
- 수정: `lib/features/schedule/domain/attendance_schedule.dart`
- 수정: `lib/features/schedule/data/schedule_store.dart`
- 수정: `lib/features/schedule/application/schedule_controller.dart`
- 테스트: `test/schedule_controller_test.dart`
- 테스트: `test/schedule_reminder_test.dart`

**인터페이스**

```dart
enum AlarmVolumeButtonAction { snooze, dismiss, none }

class AlarmSound {
  const AlarmSound({this.uri, required this.label});
  const AlarmSound.systemDefault();
  final String? uri;
  final String label;
  Map<String, dynamic> toJson();
  factory AlarmSound.fromJson(Map<String, dynamic>? json);
}

class AlarmSettings {
  const AlarmSettings({
    this.sound = const AlarmSound.systemDefault(),
    this.volumePercent = 100,
    this.vibrationEnabled = true,
    this.gradualVolumeEnabled = false,
    this.snoozeMinutes = 5,
    this.maximumSnoozeCount = 3,
    this.volumeButtonAction = AlarmVolumeButtonAction.snooze,
  });
  final AlarmSound sound;
  final int volumePercent;
  final bool vibrationEnabled;
  final bool gradualVolumeEnabled;
  final int snoozeMinutes;
  final int? maximumSnoozeCount;
  final AlarmVolumeButtonAction volumeButtonAction;
  Map<String, dynamic> toJson();
  factory AlarmSettings.fromJson(Map<String, dynamic>? json);
}
```

`AttendanceSchedule`에 `alarmSettings`를 추가한다. 기존 JSON에 필드가 없거나 손상된
경우 `const AlarmSettings()`를 사용한다. `copyWith`와 JSON 왕복에 모든 알람 설정을
포함한다.

`ScheduleStore`는 마지막으로 저장한 알람 설정을
`attendance.lastAlarmSettings`에 별도로 저장하고 읽는다. `ScheduleController`는
일정을 저장할 때 이 기본값도 갱신하고, 새 일정 편집 화면에
`defaultAlarmSettings`로 제공한다.

**검증**

- 기존 일정 JSON이 기본 알람 설정으로 복원된다.
- 사용자 설정 전체가 일정 JSON과 마지막 기본값에 왕복 저장된다.
- 음량은 0~100, 다시 알림 간격은 1·3·5·10·15분, 최대 횟수는 0~10 또는 `null`만
  허용한다.

### Task 2: 일정 편집 화면과 시스템 알람음 선택

**파일**

- 생성: `lib/features/schedule/application/alarm_sound_picker.dart`
- 생성: `lib/features/schedule/data/platform_alarm_sound_picker.dart`
- 수정: `lib/features/schedule/application/schedule_controller.dart`
- 수정: `lib/features/schedule/presentation/schedule_list_screen.dart`
- 수정: `lib/features/schedule/presentation/schedule_edit_screen.dart`
- 수정: `lib/app/app.dart`
- 수정: `android/app/src/main/kotlin/com/ddhhyy/skala_attendance/MainActivity.kt`
- 테스트: `test/widget_test.dart`

**인터페이스**

```dart
abstract interface class AlarmSoundPicker {
  Future<AlarmSound?> pick(AlarmSound current);
}

class PlatformAlarmSoundPicker implements AlarmSoundPicker {
  static const channel = MethodChannel('skala_attendance/alarm');
}
```

Android 채널의 `pickAlarmSound`는 `RingtoneManager.ACTION_RINGTONE_PICKER`를 열고
선택 결과의 URI와 표시 이름을 반환한다. 취소는 `null`, 더 이상 접근할 수 없는 URI는
시스템 기본 알람음으로 정규화한다.

일정 편집 화면의 `알람 설정` 구역은 다음을 제공한다.

- 알람음 행: 시스템 선택기
- 음량: 0~100% Slider와 현재 백분율
- 진동·점점 크게: Switch
- 다시 알림: 1·3·5·10·15분과 최대 0~10회/제한 없음 선택창
- 볼륨 버튼: 다시 알림·끄기·아무 동작 안 함 선택창

기존 일정은 자체 설정으로, 새 일정은 `defaultAlarmSettings`로 시작한다. 저장 전
변경은 다른 일정이나 기본값에 영향을 주지 않는다.

### Task 3: Flutter 발생 건과 Android 예약 브리지

**파일**

- 생성: `lib/features/schedule/domain/alarm_occurrence.dart`
- 생성: `lib/features/schedule/data/android_alarm_platform.dart`
- 수정: `lib/features/schedule/data/local_notification_scheduler.dart`
- 수정: `lib/features/schedule/domain/schedule_reminder.dart`
- 테스트: `test/schedule_reminder_test.dart`
- 테스트: `test/settings_data_interfaces_test.dart`

**인터페이스**

```dart
class AlarmOccurrence {
  const AlarmOccurrence({
    required this.scheduleId,
    required this.action,
    required this.scheduledAt,
    required this.settings,
    this.snoozeCount = 0,
  });
  String get occurrenceKey;
  Map<String, dynamic> toPlatformMap();
}

abstract interface class AndroidAlarmPlatform {
  Future<void> initialize(ValueChanged<String> onActionPayload);
  Future<void> sync(List<AlarmOccurrence> occurrences);
  Future<String?> takeLaunchPayload();
}
```

`LocalNotificationScheduler`는 Android에서 `ScheduleReminderPlanner` 결과를
`AlarmOccurrence`로 변환해 `skala_attendance/alarm` 채널의 `sync`로 전달한다.
iOS에서는 기존 `zonedSchedule`을 유지한다. Android 알람 화면의
`Google 인증 시작` payload는 기존 `tapPayload`에 전달해 현재 Flutter 검증·인증
경로를 그대로 사용한다.

### Task 4: Android 예약 저장·예약·복구

**파일**

- 생성:
  `android/app/src/main/kotlin/com/ddhhyy/skala_attendance/alarm/AlarmContract.kt`
- 생성:
  `android/app/src/main/kotlin/com/ddhhyy/skala_attendance/alarm/AlarmOccurrence.kt`
- 생성:
  `android/app/src/main/kotlin/com/ddhhyy/skala_attendance/alarm/AlarmStore.kt`
- 생성:
  `android/app/src/main/kotlin/com/ddhhyy/skala_attendance/alarm/AlarmScheduler.kt`
- 생성:
  `android/app/src/main/kotlin/com/ddhhyy/skala_attendance/alarm/AlarmReceiver.kt`
- 생성:
  `android/app/src/main/kotlin/com/ddhhyy/skala_attendance/alarm/AlarmRestoreReceiver.kt`
- 수정: `android/app/src/main/kotlin/com/ddhhyy/skala_attendance/MainActivity.kt`
- 수정: `android/app/src/main/AndroidManifest.xml`
- 수정: `android/app/build.gradle.kts`
- 테스트:
  `android/app/src/test/kotlin/com/ddhhyy/skala_attendance/alarm/AlarmOccurrenceTest.kt`
- 테스트:
  `android/app/src/test/kotlin/com/ddhhyy/skala_attendance/alarm/AlarmPolicyTest.kt`

`sync`는 기존 native mirror와 PendingIntent를 취소한 뒤 새 목록을 원자적으로 저장하고
각 발생 건을 `AlarmManager.setAlarmClock()`으로 예약한다. PendingIntent는
`occurrenceKey` 기반의 안정적인 request code와 data URI를 사용한다.

`AlarmReceiver`는 실행 시 mirror에 동일한 발생 건과 시각이 남아 있는지 확인한 뒤에만
울림 서비스를 시작한다. `AlarmRestoreReceiver`는 `BOOT_COMPLETED`,
`MY_PACKAGE_REPLACED`, 빠른 부팅 이벤트에서 미래 발생 건과 남은 다시 알림을
재예약한다.

### Task 5: 울림 서비스·알람 화면·동작 버튼

**파일**

- 생성:
  `android/app/src/main/kotlin/com/ddhhyy/skala_attendance/alarm/AlarmRingingService.kt`
- 생성:
  `android/app/src/main/kotlin/com/ddhhyy/skala_attendance/alarm/AlarmActivity.kt`
- 생성:
  `android/app/src/main/kotlin/com/ddhhyy/skala_attendance/alarm/AlarmActionReceiver.kt`
- 생성: `android/app/src/main/res/layout/activity_alarm.xml`
- 생성: `android/app/src/main/res/drawable/alarm_background.xml`
- 수정: `android/app/src/main/AndroidManifest.xml`
- 수정: `android/app/src/main/res/values/styles.xml`
- 테스트:
  `android/app/src/test/kotlin/com/ddhhyy/skala_attendance/alarm/AlarmPolicyTest.kt`

서비스는 alarm audio attributes의 반복 `MediaPlayer`, 반복 진동, ongoing 알림을
소유한다. 알림 채널은 무음으로 두어 서비스 재생과 중복되지 않게 한다. 점점 크게는
30초 동안 설정 비율까지 선형으로 증가한다.

알람 화면과 heads-up 알림은 `끄기`, `다시 알림`, `Google 인증 시작`을 분리한다.

- 끄기: 울림만 종료
- 다시 알림: 설정 간격 뒤 일회성 발생 건 예약, 횟수 증가
- 인증 시작: 울림 종료 후 MainActivity에 기존 일정 payload 전달

최대 다시 알림 횟수에 도달하면 다시 알림 버튼을 숨긴다. 볼륨 버튼은
`AlarmVolumeButtonAction`에 따라 같은 끄기/다시 알림 명령을 호출하며 전원 버튼은
처리하지 않는다.

### Task 6: 전체 화면 권한과 필수 설정 복구

**파일**

- 수정: `lib/features/schedule/application/notification_scheduler.dart`
- 수정: `lib/features/schedule/data/local_notification_scheduler.dart`
- 수정: `lib/features/settings/application/settings_controller.dart`
- 수정: `lib/features/settings/presentation/settings_screen.dart`
- 수정: `lib/app/initial_setup_screen.dart`
- 수정: `lib/app/app.dart`
- 수정: `android/app/src/main/kotlin/com/ddhhyy/skala_attendance/MainActivity.kt`
- 수정: `android/app/src/main/AndroidManifest.xml`
- 테스트: `test/settings_data_interfaces_test.dart`
- 테스트: `test/settings_controller_test.dart`
- 테스트: `test/settings_screen_test.dart`
- 테스트: `test/widget_test.dart`

`NotificationPermissionStatus.android`에 nullable
`fullScreenAlarmsAllowed`를 추가하고 Android 준비 상태는 세 권한이 모두 `true`일
때만 통과한다. `NotificationPermissionSettings`에는
`openFullScreenAlarmSettings()`를 추가한다.

Android 14 이상 상태는 `NotificationManager.canUseFullScreenIntent()`로 확인하고
`ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT`로 이동한다. 그 미만은 적용 대상이 아니므로
허용으로 처리한다. 통합 설정 화면에는 `전체 화면 알람 권한` 행을 추가한다.

초기 설정에서 일반 알림·정확 알람 요청 후 전체 화면 권한이 없으면 해당 설정 화면을
열고, 앱 복귀 시 전체 상태를 다시 확인한다. 권한이 해제되면 기존 완료 상태를
무효화하고, 복구 후 최신 일정 전체 재예약이 성공해야 홈으로 돌아간다.

### Task 7: 1차 자동 검증·release APK·사용자 ADB 검증

**파일**

- 수정: `README.md`
- 수정: `docs/current-implementation.md`
- 수정: `docs/android-apk-distribution.md`
- 수정: `pubspec.yaml`

구현 범위의 Dart 테스트, Android unit test, `flutter analyze`,
`flutter build apk --release --split-per-abi`를 실행한다. build number를 증가시키고
기존 release 인증서 SHA-256과 동일한지 확인한 뒤 연결된 arm64 기기에 `adb install -r`
로 업데이트한다.

사용자는 실기기에서 가까운 테스트 일정을 만들어 다음을 먼저 확인한다.

1. 화면 켜짐·꺼짐·잠금 상태에서 표시
2. 소리·음량·진동·점점 크게
3. 끄기·다시 알림·볼륨 버튼
4. 다른 앱 사용 중 heads-up 표시
5. Google 인증 시작 시 알람 종료와 기존 인증 화면 진입
6. 앱 강제 종료 뒤 알람 실행

이 지점에서는 실제 출결 동작을 보내지 않는다. 사용자가 기능을 확인하기 전에는
feature 브랜치를 push하거나 `main`에 병합하지 않는다.

### Task 8: 사용자 확인 후 사후 FULL 점검

사용자가 1차 기능을 확인한 뒤에만 진행한다.

- 전체 Flutter 테스트와 Android unit test 재실행
- 예약/울림/권한/복구 경계 코드 별도 검토
- 권한 해제·복구, 재부팅, 앱 업데이트, 삭제·비활성화 일정 회귀 확인
- 발견된 문제 수정 후 release APK 재설치
- 사용자 최종 승인 뒤 feature 브랜치 push, `main` 병합, 병합 결과 검증 및 push
