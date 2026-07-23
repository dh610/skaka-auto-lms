# 필수 설정 복구와 알림 재예약 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 일반 알림·정확 알람·App Link를 모두 필수로 유지하고, 권한 복구 후 정확 알림 전체 재예약이 성공해야 메인 화면에 진입하게 한다.

**Architecture:** `ScheduleController`의 기존 단일 실행 동기화 대기열이 최종 재예약 성공 여부를 반환하게 한다. 앱 최상위 상태는 일정 초기 로딩을 기다린 뒤 이 결과를 초기 설정 완료 조건으로 사용하고, `InitialSetupScreen`은 건너뛰기 없이 실패 메시지와 재시도를 제공한다.

**Tech Stack:** Flutter, Dart, `flutter_local_notifications`, `shared_preferences`, Flutter widget/unit tests

## Global Constraints

- 일반 알림 권한, 정확 알람 특별 접근 권한, Android App Link는 모두 필수다.
- `나중에 설정`으로 메인 화면에 우회하는 경로를 제공하지 않는다.
- 필수 설정이 해제되면 저장된 초기 설정 완료 상태도 해제한다.
- 최신 저장 일정 전체 재예약이 성공해야 초기 설정을 완료한다.
- 재예약 실패는 일정 데이터를 되돌리지 않고 초기 설정 화면에서 재시도한다.
- 기존 재예약 직렬화와 최신 상태 합치기 규칙을 유지한다.
- 실제 출결 동작은 테스트하지 않는다.

---

### Task 1: 전체 재예약 성공 여부 반환

**Files:**
- Modify: `lib/features/schedule/application/schedule_controller.dart`
- Test: `test/schedule_reminder_test.dart`

**Interfaces:**
- Consumes: `NotificationScheduler.sync(List<AttendanceSchedule>)`
- Produces: `Future<bool> ScheduleController.resyncNotifications()`

- [ ] **Step 1: 재예약 실패와 재시도 결과를 검증하는 실패 테스트 작성**

테스트 스케줄러에 `bool failSync`와 `int syncCount`를 추가하고 다음 테스트를 작성한다.

```dart
test('explicit resync reports failure and later success', () async {
  final notifications = _FakeNotificationScheduler();
  final controller = ScheduleController(ScheduleStore(), notifications);
  await controller.load();

  notifications.failSync = true;
  expect(await controller.resyncNotifications(), isFalse);
  expect(controller.notificationMessage, startsWith('알림 예약 실패:'));

  notifications.failSync = false;
  expect(await controller.resyncNotifications(), isTrue);
  expect(notifications.syncCount, 3);
  controller.dispose();
});
```

- [ ] **Step 2: 실패 테스트 실행**

Run: `flutter test test/schedule_reminder_test.dart --plain-name 'explicit resync reports failure and later success'`

Expected: `ScheduleController.resyncNotifications`가 없어 컴파일 실패한다.

- [ ] **Step 3: 기존 직렬 대기열이 최종 성공 여부를 반환하게 변경**

`ScheduleController`의 동기화 Future와 메서드 반환형을 `bool`로 바꾼다.

```dart
Future<bool>? _notificationSyncFuture;

Future<bool> resyncNotifications() => _requestNotificationSync();

Future<bool> _requestNotificationSync() {
  _notificationSyncRequested = true;
  return _notificationSyncFuture ??= _drainNotificationSyncRequests();
}

Future<bool> _drainNotificationSyncRequests() async {
  var succeeded = true;
  try {
    while (_notificationSyncRequested) {
      _notificationSyncRequested = false;
      final snapshot = List<AttendanceSchedule>.unmodifiable(_schedules);
      succeeded = await _syncNotificationSnapshot(snapshot);
    }
    return succeeded;
  } finally {
    _notificationSyncFuture = null;
  }
}

Future<bool> _syncNotificationSnapshot(
  List<AttendanceSchedule> schedules,
) async {
  final scheduler = _notificationScheduler;
  if (scheduler == null) return true;
  try {
    _pendingNotificationCount = await scheduler.sync(schedules);
    _notificationMessage = _pendingNotificationCount > 0
        ? '설정한 일정의 알림이 예약되어 있습니다.'
        : '앞으로 예정된 알림이 없습니다.';
    return true;
  } catch (error) {
    _notificationMessage = '알림 예약 실패: $error';
    return false;
  }
}
```

- [ ] **Step 4: 단위 테스트와 기존 직렬화 테스트 실행**

Run: `flutter test test/schedule_reminder_test.dart`

Expected: 모든 일정 알림 단위 테스트 통과.

- [ ] **Step 5: 첫 구현 커밋**

```bash
git add lib/features/schedule/application/schedule_controller.dart test/schedule_reminder_test.dart
git commit -m "fix: report notification resync failures"
```

### Task 2: 초기 설정 완료 상태 영구 해제

**Files:**
- Modify: `lib/app/initial_setup_store.dart`
- Modify: `lib/app/app.dart`
- Test: `test/widget_test.dart`

**Interfaces:**
- Consumes: `InitialSetupStore.isCompleted()`
- Produces: `Future<void> InitialSetupStore.markIncomplete()`

- [ ] **Step 1: 권한 해제 시 저장된 완료 상태도 해제되는 실패 테스트 작성**

기존 `revoked permissions reopen initial setup on app resume` 테스트 마지막에 다음 검증을 추가한다.

```dart
final preferences = await SharedPreferences.getInstance();
expect(preferences.getBool('initialSetup.completed'), isFalse);
```

- [ ] **Step 2: 실패 테스트 실행**

Run: `flutter test test/widget_test.dart --plain-name 'revoked permissions reopen initial setup on app resume'`

Expected: 저장값이 여전히 `true`여서 실패한다.

- [ ] **Step 3: 저장소 해제 API와 앱의 해제 경로 구현**

```dart
Future<void> markIncomplete() async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.setBool(_completedKey, false);
}
```

앱 시작 검사에서 저장값은 완료지만 필수 설정이 준비되지 않은 경우와, 앱
복귀 검사에서 설정 해제를 발견한 경우 모두 `markIncomplete()`를 기다린 후
화면 상태를 미완료로 바꾼다.

- [ ] **Step 4: 대상 위젯 테스트 실행**

Run: `flutter test test/widget_test.dart --plain-name 'revoked permissions reopen initial setup on app resume'`

Expected: PASS.

- [ ] **Step 5: 완료 상태 해제 커밋**

```bash
git add lib/app/initial_setup_store.dart lib/app/app.dart test/widget_test.dart
git commit -m "fix: persist incomplete required setup"
```

### Task 3: 건너뛰기 제거와 재예약 성공 게이트

**Files:**
- Modify: `lib/app/app.dart`
- Modify: `lib/app/initial_setup_screen.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Consumes: `ScheduleController.resyncNotifications()`
- Changes: `InitialSetupScreen.onFinished` from `Future<void> Function()` to `Future<bool> Function()`
- Produces: `bool` 완료 결과로 오류 화면 유지와 재시도를 결정

- [ ] **Step 1: 건너뛰기 제거 실패 테스트 작성**

`initial setup requests notification permissions` 테스트의 초기 화면 검증에
다음을 추가한다.

```dart
expect(find.text('나중에 설정'), findsNothing);
expect(find.textContaining('나중에 설정해도'), findsNothing);
```

- [ ] **Step 2: 재예약 실패 후 화면 유지·재시도 성공 테스트 작성**

`_SetupNotificationScheduler`가 `syncCount`, `failSync`를 기록하도록 하고,
프로필과 세 준비 상태를 갖춘 앱을 실행한다.

```dart
testWidgets(
  'required setup waits for notification resync and retries failure',
  (tester) async {
    SharedPreferences.setMockInitialValues({
      'profile.name': '윤동현',
      'profile.region': 'P2',
      'profile.classNumber': 8,
    });
    final notifications = _SetupNotificationScheduler(
      granted: true,
      failSync: true,
    );

    await tester.pumpWidget(
      SkalaAttendanceApp(
        notificationScheduler: notifications,
        callbackLinkSettings: _FakeCallbackLinkSettings(enabled: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('초기 설정'), findsOneWidget);
    expect(find.textContaining('알림을 예약하지 못했습니다'), findsOneWidget);
    expect(find.text('윤동현님, 안녕하세요'), findsNothing);

    notifications.failSync = false;
    await tester.tap(find.text('설정 완료'));
    await tester.pumpAndSettle();

    expect(find.text('윤동현님, 안녕하세요'), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('initialSetup.completed'), isTrue);
  },
);
```

- [ ] **Step 3: 두 실패 테스트 실행**

Run: `flutter test test/widget_test.dart --plain-name 'initial setup requests notification permissions'`

Expected: 현재 `나중에 설정` 버튼이 있어 실패한다.

Run: `flutter test test/widget_test.dart --plain-name 'required setup waits for notification resync and retries failure'`

Expected: 현재 앱이 재예약 성공 여부를 기다리지 않고 메인 화면으로 이동해 실패한다.

- [ ] **Step 4: 앱에서 일정 로딩과 전체 재예약을 완료 조건으로 연결**

앱 초기화 Future를 보존하고 완료 콜백이 성공 여부를 반환하게 한다.

```dart
late final Future<void> _scheduleInitialization;

@override
void initState() {
  // 기존 컨트롤러 생성 이후
  _scheduleInitialization = _scheduleController.load();
}

Future<bool> _finishInitialSetup() async {
  await _scheduleInitialization;
  final synchronized = await _scheduleController.resyncNotifications();
  await _scheduleController.refreshNotificationStatus();
  if (!synchronized) return false;
  await _initialSetupStore.markCompleted();
  if (mounted) setState(() => _initialSetupCompleted = true);
  return true;
}
```

- [ ] **Step 5: 초기 설정 화면에서 건너뛰기를 제거하고 실패를 표시**

`InitialSetupScreen.onFinished`를 `Future<bool> Function()`으로 바꾸고, 모든
필수 설정이 준비된 완료 시도는 공통 메서드를 사용한다.

```dart
String? _completionError;

Future<void> _finishSetup() async {
  if (!_allReady) return;
  final completed = await widget.onFinished();
  if (!mounted) return;
  setState(() {
    _completionError = completed
        ? null
        : '알림을 예약하지 못했습니다. 설정을 확인한 뒤 다시 시도해 주세요.';
  });
}
```

`나중에 설정` 버튼, `_skip()` 메서드, 관련 안내 문구를 삭제한다. 오류 문구는
완료 버튼 위에 표시하고, 실패 후 `설정 완료` 버튼을 누르면 `_finishSetup()`을
다시 실행한다. `InitialSetupScreen`을 직접 생성하는 기존 위젯 테스트의
`onFinished` 콜백은 완료 여부에 맞춰 `true`를 반환하게 갱신한다.

- [ ] **Step 6: 초기 설정 관련 위젯 테스트 실행**

Run: `flutter test test/widget_test.dart`

Expected: 모든 위젯 테스트 통과.

- [ ] **Step 7: 기능 구현 커밋**

```bash
git add lib/app/app.dart lib/app/initial_setup_screen.dart test/widget_test.dart
git commit -m "fix: resync alarms before completing setup"
```

### Task 4: 문서·전체 검증·기기 업데이트

**Files:**
- Modify: `docs/current-implementation.md`
- Modify: `docs/README.md` only if document links or status need correction

**Interfaces:**
- Consumes: Tasks 1–3의 최종 동작
- Produces: 실제 구현과 일치하는 현재 상태 문서 및 설치 가능한 릴리스 APK

- [ ] **Step 1: 현재 구현 문서 갱신**

초기 설정 문단에 세 필수 설정 강제, 건너뛰기 제거, 권한 복구 후 재예약
성공 게이트를 기록하고 실제 최종 테스트 수로 갱신한다.

- [ ] **Step 2: 변경 Dart 파일 포맷**

Run: `dart format lib/app/app.dart lib/app/initial_setup_screen.dart lib/app/initial_setup_store.dart lib/features/schedule/application/schedule_controller.dart test/schedule_reminder_test.dart test/widget_test.dart`

Expected: 포맷 성공.

- [ ] **Step 3: 정적 분석과 전체 테스트**

Run: `flutter analyze`

Expected: `No issues found!`

Run: `flutter test`

Expected: 모든 테스트 통과.

- [ ] **Step 4: 릴리스 arm64 APK 빌드와 서명 확인**

Run: `flutter build apk --release --split-per-abi`

Expected: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` 생성.

Run: `apksigner verify --print-certs build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`

Expected: 설치본과 동일한 SHA-256 인증서 지문 `2eaabc49a261171c6c4a7517b27b8337e818ead886c551c1f55354d0b37274cb`.

- [ ] **Step 5: 문서와 최종 구현 커밋**

```bash
git add docs/current-implementation.md docs/README.md
git commit -m "docs: document required notification setup"
```

- [ ] **Step 6: ADB 업데이트 설치와 결과 확인**

Run: `adb -s 100.110.49.51:43143 install --no-streaming -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`

Expected: `Success`.

Run: `adb -s 100.110.49.51:43143 shell dumpsys package com.ddhhyy.skala_attendance | rg 'versionCode|versionName|lastUpdateTime'`

Expected: 최신 `lastUpdateTime`과 새 `versionCode` 출력.

- [ ] **Step 7: 작업 트리와 커밋 확인**

Run: `git diff --check && git status --short && git log -6 --oneline --decorate`

Expected: diff 오류와 미커밋 변경 없음.
