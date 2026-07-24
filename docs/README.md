# 문서 안내

문서는 현재 상태와 역사적 조사 기록을 구분한다.

현재 기준 문서는 2026-07-24 구현과 Android 실기기 검증 결과를 반영한다. iOS는 기존
시뮬레이터 검증 결과와 코드를 보존하지만 개발·실기기 검증·배포를 중단한 상태다.

## 현재 기준 문서

- [현재 구현 상태](current-implementation.md): 실제 구현 범위와 미구현 범위
- [UX 원칙과 설계 결정](ux-guidelines.md): 화면, 상태, 권한, 경고 및 상호작용 판단 기준
- [공휴일 데이터 운영 전략](holiday-data-strategy.md): 정적 공휴일 목록을 선택한 이유
- [Android와 iOS의 기능 차이](platform-capability-differences.md): 인증, 콜백 및 백그라운드 정책 차이
- [Android APK 배포](android-apk-distribution.md): release 서명, 빌드 및 교육생 배포 절차
- [무료 계정으로 개인 iPhone에 설치](ios-personal-device-installation.md): 공식 지원·배포가 아닌 Mac과 Xcode를 이용한 7일 제한 개인 설치 절차

## 역사적 기록

- [초기 조사 및 구현 계획](implementation-notes.md): 2026-07-16에 관찰한 API와 개발 시작 당시의 가설·계획

## 설계·작업 계획

- [출결 상태 확인 화면 UX 개선 설계](superpowers/specs/2026-07-24-attendance-status-ux-design.md): 인증·상태 카드 교체, 2×2 상태 타일 및 완료 피드백
- [출결 일정 네이티브 알람 설계](superpowers/specs/2026-07-24-native-alarm-design.md): 공통 알람 설정, Android 네이티브 실행 및 향후 iOS AlarmKit 연결
- [알림 재예약 일관성 개선 계획](superpowers/plans/2026-07-23-notification-sync-consistency.md): 재예약 직렬화, 앱 중간 종료 복구 및 과거 알림 검증 원칙
- [필수 설정 복구와 알림 재예약 구현 계획](superpowers/plans/2026-07-23-required-permissions-resync.md): 실패 테스트, 초기 설정 완료 게이트, 검증 및 기기 업데이트 순서
- [필수 설정 복구와 알림 재예약 설계](superpowers/specs/2026-07-23-required-permissions-resync-design.md): 세 필수 설정 강제, 권한 복구 후 전체 재예약 및 실패 처리 원칙

역사적 기록의 미완료 항목이나 목표를 현재 기능으로 해석하지 않는다. 구현 여부를
판단할 때는 현재 구현 상태 문서와 실제 코드를 기준으로 한다.
