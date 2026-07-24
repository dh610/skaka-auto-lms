import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skala_attendance/features/attendance/data/attendance_status_store.dart';
import 'package:skala_attendance/features/attendance/domain/attendance_snapshot.dart';
import 'package:skala_attendance/features/attendance/domain/daily_attendance_status.dart';
import 'package:skala_attendance/features/schedule/domain/attendance_schedule.dart';

void main() {
  const storageKey = 'attendance.todayStatus';
  final koreaDate = DateTime(2026, 7, 24);
  final fetchedAt = DateTime.parse('2026-07-24T09:15:00+09:00');

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('returns an unqueried status when no stored value exists', () async {
    final status = await AttendanceStatusStore().loadFor(koreaDate);

    expect(status.koreaDate, koreaDate);
    expect(status.queried, isFalse);
    expect(status.fetchedAt, isNull);
    expect(status.sequenceAvailableActions, {AttendanceAction.checkIn});
  });

  test(
    'restores all attendance times and fetched time for the same date',
    () async {
      final store = AttendanceStatusStore();
      final saved = DailyAttendanceStatus.queried(
        koreaDate: koreaDate,
        fetchedAt: fetchedAt,
        checkInTime: '09:00',
        checkOutTime: '18:00',
        earlyLeaveTime: '13:00',
        returnTime: '14:00',
      );

      await store.save(saved);
      final restored = await store.loadFor(koreaDate);

      expect(restored.queried, isTrue);
      expect(restored.koreaDate, koreaDate);
      expect(restored.fetchedAt, fetchedAt);
      expect(restored.checkInTime, '09:00');
      expect(restored.checkOutTime, '18:00');
      expect(restored.earlyLeaveTime, '13:00');
      expect(restored.returnTime, '14:00');
    },
  );

  test('stores only the approved display status fields', () async {
    final store = AttendanceStatusStore();
    await store.save(
      DailyAttendanceStatus.fromSnapshot(
        koreaDate: koreaDate,
        fetchedAt: fetchedAt,
        snapshot: const AttendanceSnapshot(
          networkAllowed: false,
          checkInTime: '09:00',
        ),
      ),
    );
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(storageKey)!;
    final json = jsonDecode(encoded) as Map<String, dynamic>;

    expect(json.keys.toSet(), {'date', 'fetchedAt', 'checkInTime'});
    expect(json.containsKey('networkAllowed'), isFalse);
    expect(
      json.keys.any((key) => key.toLowerCase().contains('token')),
      isFalse,
    );
  });

  test('removes a stored status from another date', () async {
    SharedPreferences.setMockInitialValues({
      storageKey: jsonEncode({
        'date': '2026-07-23',
        'fetchedAt': fetchedAt.toIso8601String(),
        'checkInTime': '09:00',
      }),
    });

    final status = await AttendanceStatusStore().loadFor(koreaDate);
    final preferences = await SharedPreferences.getInstance();

    expect(status.queried, isFalse);
    expect(preferences.containsKey(storageKey), isFalse);
  });

  test('recovers from malformed JSON by clearing the stored value', () async {
    SharedPreferences.setMockInitialValues({storageKey: '{not json'});

    final status = await AttendanceStatusStore().loadFor(koreaDate);
    final preferences = await SharedPreferences.getInstance();

    expect(status.queried, isFalse);
    expect(status.koreaDate, koreaDate);
    expect(preferences.containsKey(storageKey), isFalse);
  });

  test('rejects an overflow calendar value in the fetched timestamp', () async {
    SharedPreferences.setMockInitialValues({
      storageKey: jsonEncode({
        'date': '2026-07-24',
        'fetchedAt': '2026-02-30T09:15:00.000',
        'checkInTime': '09:00',
      }),
    });

    final status = await AttendanceStatusStore().loadFor(koreaDate);
    final preferences = await SharedPreferences.getInstance();

    expect(status.queried, isFalse);
    expect(preferences.containsKey(storageKey), isFalse);
  });

  test('rejects a non-string present attendance time field', () async {
    SharedPreferences.setMockInitialValues({
      storageKey: jsonEncode({
        'date': '2026-07-24',
        'fetchedAt': fetchedAt.toIso8601String(),
        'checkInTime': 900,
      }),
    });

    final status = await AttendanceStatusStore().loadFor(koreaDate);
    final preferences = await SharedPreferences.getInstance();

    expect(status.queried, isFalse);
    expect(preferences.containsKey(storageKey), isFalse);
  });

  test('derives available actions from attendance time sequence only', () {
    DailyAttendanceStatus status({
      String? checkInTime,
      String? checkOutTime,
      String? earlyLeaveTime,
      String? returnTime,
    }) => DailyAttendanceStatus.queried(
      koreaDate: koreaDate,
      fetchedAt: fetchedAt,
      checkInTime: checkInTime,
      checkOutTime: checkOutTime,
      earlyLeaveTime: earlyLeaveTime,
      returnTime: returnTime,
    );

    expect(status(checkOutTime: '18:00').sequenceAvailableActions, isEmpty);
    expect(status().sequenceAvailableActions, {AttendanceAction.checkIn});
    expect(
      status(
        checkInTime: '09:00',
        earlyLeaveTime: '13:00',
      ).sequenceAvailableActions,
      {AttendanceAction.returnFromLeave},
    );
    expect(
      status(
        checkInTime: '09:00',
        earlyLeaveTime: '13:00',
        returnTime: '14:00',
      ).sequenceAvailableActions,
      {AttendanceAction.checkOut},
    );
    expect(status(checkInTime: '09:00').sequenceAvailableActions, {
      AttendanceAction.leave,
      AttendanceAction.checkOut,
    });
  });
}
