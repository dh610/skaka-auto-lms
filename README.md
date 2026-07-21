# SKALA 출결 도우미

SKALA LMS의 Google 인증을 거쳐 당일 출결 상태를 확인하고 출결 동작을 처리하는
Flutter 앱입니다. Android와 iOS 프로젝트를 함께 관리하며, 현재 앱 내 상태 조회와
출결 이벤트 전송은 Android에서 지원합니다.

## 현재 기능

- 최초 실행 시 이름, 캠퍼스, 반을 SKALA 사전 확인 API로 검증한 뒤 설정
- 저장된 사용자 정보를 조회하고, 변경 시에도 검증한 뒤 저장
- 시스템 설정, 라이트 모드, 다크 모드 중 앱 테마 선택 및 저장
- 출결 일정 생성, 수정, 활성화 및 삭제
- 일정 편집 중 고정 저장 버튼과 진입 시 스크롤 가능 여부 안내
- 요일·시각·동작별 일정 로컬 저장
- 요일 반복 일정의 2026년 과정 기간 공휴일 제외
- 과정 기간 내 특정 날짜 1회 일정
- 실제 발생 날짜와 시각이 겹치는 중복 일정 저장 방지
- 메인 화면에서 오늘 알림 일정의 예정·완료·시간 지남·건너뜀 상태 확인
- 시간 지남 일정을 발생 건별로 건너뜀 처리하거나 되돌리기
- 일정 알림을 통해 인증·브라우저 흐름을 시작한 상태를 발생 건별로 당일 보존하고 자정 이후 초기화
- Android/iOS 로컬 일정 알림
- 최초 사용자 정보 저장 후 알림·Android 인증 복귀 설정 안내
- 공휴일을 제외한 향후 일정 알림을 가까운 순서대로 최대 60건 선등록
- 캠퍼스에 따른 반 선택 제한
  - 판교캠퍼스 4F: 1~5반
  - 판교캠퍼스 5F: 6~10반
- Android Chrome Custom Tab 및 iOS 앱 내 Safari 화면을 통한 Google OAuth 시작
- Android App Link 콜백 수신 및 당일 출결 상태 조회
- Android에서 입실, 퇴실, 외출, 복귀 요청 및 반영 결과 확인
- 인증·상태 조회 실패에 대한 원인별 안내 및 안전한 재시도
- 예약 알림에서 Google 인증 후 예정된 출결 동작 연결
- 외출 및 오후 5시 50분 이전 퇴실에 대한 확인 절차

## 실행

```sh
flutter pub get
flutter run
```

검증 명령:

```sh
flutter analyze
flutter test
```

## 디렉터리

```text
android/   Android 플랫폼 코드 및 설정
ios/       iOS 플랫폼 코드 및 설정
lib/       Flutter 애플리케이션 코드
test/      위젯 및 모델 테스트
docs/      현재 구현, 설계 결정 및 과거 조사 기록
```

## 설계 문서

- [문서 안내](docs/README.md)
- [현재 구현 상태](docs/current-implementation.md)
- [UX 원칙과 설계 결정](docs/ux-guidelines.md)
- [초기 조사 및 구현 계획](docs/implementation-notes.md)
- [공휴일 데이터 운영 전략](docs/holiday-data-strategy.md)
- [Android와 iOS의 기능 차이](docs/platform-capability-differences.md)
- [Android APK 배포](docs/android-apk-distribution.md)

## 주의

- Google 비밀번호는 앱에 저장하지 않습니다.
- 인증 토큰 전문을 로그나 저장소에 남기지 않습니다.
- iOS에서는 현재 인증 후 앱 콜백과 앱 내 출결 요청을 지원하지 않습니다.
- 예약 알림은 무인 출결 실행이 아니라 사용자가 Google 인증을 시작하는 진입점입니다.
- Android에서 VPN이 활성화되면 SKALA 허용 네트워크 판별을 방해할 수 있으므로 필요하면 이 앱을 VPN 적용 대상에서 제외해야 합니다.
