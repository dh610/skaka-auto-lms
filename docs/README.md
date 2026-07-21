# 문서 안내

문서는 현재 상태와 역사적 조사 기록을 구분한다.

현재 기준 문서는 2026-07-21 구현과 Android 실기기 검증 결과를 반영한다. iOS는 기존
시뮬레이터 검증 결과와 코드를 보존하지만 개발·실기기 검증·배포를 중단한 상태다.

## 현재 기준 문서

- [현재 구현 상태](current-implementation.md): 실제 구현 범위와 미구현 범위
- [UX 원칙과 설계 결정](ux-guidelines.md): 화면, 상태, 권한, 경고 및 상호작용 판단 기준
- [공휴일 데이터 운영 전략](holiday-data-strategy.md): 정적 공휴일 목록을 선택한 이유
- [Android와 iOS의 기능 차이](platform-capability-differences.md): 인증, 콜백 및 백그라운드 정책 차이
- [Android APK 배포](android-apk-distribution.md): release 서명, 빌드 및 교육생 배포 절차
- [무료 계정으로 개인 iPhone에 설치](ios-personal-device-installation.md): Mac과 Xcode를 이용한 7일 제한 개인 설치 절차

## 역사적 기록

- [초기 조사 및 구현 계획](implementation-notes.md): 2026-07-16에 관찰한 API와 개발 시작 당시의 가설·계획

역사적 기록의 미완료 항목이나 목표를 현재 기능으로 해석하지 않는다. 구현 여부를
판단할 때는 현재 구현 상태 문서와 실제 코드를 기준으로 한다.
