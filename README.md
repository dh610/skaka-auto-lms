# SKALA 출결 도우미

SKALA LMS의 Google 인증을 거쳐 당일 출결 상태를 확인하고 출결 동작을 처리하는
Flutter 앱입니다. Android와 iOS 프로젝트를 함께 관리하며, 현재 앱 내 상태 조회와
출결 이벤트 전송은 Android에서 지원합니다.

## 현재 기능

- 최초 실행 시 이름, 캠퍼스, 반 설정
- 저장된 사용자 정보 조회 및 변경
- 출결 일정 생성, 수정, 활성화 및 삭제
- 요일·시각·동작별 일정 로컬 저장
- 요일 반복 일정의 2026년 과정 기간 공휴일 제외
- 과정 기간 내 특정 날짜 1회 일정
- 메인 화면에서 오늘 예정된 출결 동작 확인
- Android/iOS 로컬 일정 알림
- 공휴일을 제외한 향후 일정 알림 자동 재예약
- 캠퍼스에 따른 반 선택 제한
  - 판교캠퍼스 4F: 1~5반
  - 판교캠퍼스 5F: 6~10반
- 외부 브라우저를 통한 Google OAuth
- Android App Link 콜백 수신 및 당일 출결 상태 조회
- Android에서 입실, 퇴실, 외출, 복귀 요청 및 반영 결과 확인
- 예약 알림에서 Google 인증 후 예정된 출결 동작 연결
- 외출 및 17시 50분 이전 퇴실에 대한 확인 절차

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
- [초기 조사 및 구현 계획](docs/implementation-notes.md)
- [공휴일 데이터 운영 전략](docs/holiday-data-strategy.md)
- [Android와 iOS의 기능 차이](docs/platform-capability-differences.md)

## 주의

- Google 비밀번호는 앱에 저장하지 않습니다.
- 인증 토큰 전문을 로그나 저장소에 남기지 않습니다.
- iOS에서는 현재 인증 후 앱 콜백과 앱 내 출결 요청을 지원하지 않습니다.
- 예약 알림은 무인 출결 실행이 아니라 사용자가 Google 인증을 시작하는 진입점입니다.
