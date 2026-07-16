# SKALA 출결 도우미

SKALA LMS의 Google 인증을 거쳐 당일 출결 상태를 확인하는 Flutter 앱입니다.
Android와 iOS 프로젝트를 함께 관리하며, 현재 출결 이벤트 전송은 구현하지 않은
읽기 전용 단계입니다.

## 현재 기능

- 최초 실행 시 이름, 캠퍼스, 반 설정
- 저장된 사용자 정보 조회 및 변경
- 캠퍼스에 따른 반 선택 제한
  - 판교캠퍼스 4F: 1~5반
  - 판교캠퍼스 5F: 6~10반
- 외부 브라우저를 통한 Google OAuth
- Android App Link 콜백 수신 및 당일 출결 상태 조회

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
docs/      인증/API 조사 기록
```

인증 흐름과 확인된 API에 대한 자세한 내용은
[구현 조사 기록](docs/implementation-notes.md)을 참고하세요.

## 주의

- Google 비밀번호는 앱에 저장하지 않습니다.
- 인증 토큰 전문을 로그나 저장소에 남기지 않습니다.
- 현재 버전은 입실, 퇴실, 외출, 복귀 요청을 전송하지 않습니다.
