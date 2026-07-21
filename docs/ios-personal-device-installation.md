# 무료 Apple 계정으로 개인 iPhone에 설치하기

## 문서 범위

이 문서는 Mac을 사용할 수 있는 사용자가 GitHub의 소스 코드를 직접 빌드하여 본인의
iPhone에 `SKALA 출결 도우미`를 설치하는 방법을 설명한다. TestFlight나 App Store
배포가 아니며, 다른 사람이 만든 IPA 파일을 내려받아 설치하는 절차도 아니다.

무료 Apple 계정의 Personal Team으로 설치한 앱과 프로비저닝 프로파일은 발급 후
7일이 지나면 만료된다. 계속 사용하려면 같은 Mac과 Apple 계정으로 앱을 다시 빌드해
설치해야 한다. Apple의 현재 무료 계정 제한은 다음과 같다.

- App ID 최대 10개, 각각 7일 후 만료
- 등록 기기 최대 3대, 각각 7일 후 만료
- 기기당 설치 앱 최대 3개
- TestFlight와 App Store 배포 불가

자세한 제한은 [Apple 개발자 계정 안내][apple-account]를 참고한다.

## iOS판의 기능 제한

iOS 개발과 사용자 배포는 현재 중단된 상태다. 저장소의 iOS 코드는 기존 기술 검증
결과를 보존하기 위해 남겨 두었다.

개인 iPhone에 설치하면 프로필 검증, 일정 관리, 공휴일 제외, 로컬 알림과 앱 내 Safari
화면은 사용할 수 있다. 그러나 Android처럼 Google 인증 후 앱으로 자동 복귀하여 상태를
조회하거나 출결 동작을 API로 전송하지 않는다. Safari 화면에서 사용자가 직접 출결을
처리해야 한다. 실제 iPhone에서 전체 흐름을 공식 지원하거나 보장하지 않는다.

## 준비물

- 최신 macOS가 설치된 Mac
- 최신 Xcode
- Flutter SDK
- Git
- 본인의 iPhone과 연결 케이블
- 이중 인증이 활성화된 본인의 Apple 계정
- 설치와 프로필 검증에 필요한 인터넷 및 SKALA 네트워크 환경

터미널에서 개발 환경을 확인한다.

```sh
flutter doctor
```

Flutter가 iOS 도구나 CocoaPods 문제를 표시하면 먼저 해당 항목을 해결한다. Flutter의
[공식 iOS 개발 환경 설정][flutter-ios-setup]도 함께 참고한다.

## 1. 소스 코드 받기

터미널에서 저장소를 복제하고 프로젝트 디렉터리로 이동한다.

```sh
git clone https://github.com/dh610/skaka-auto-lms.git
cd skaka-auto-lms
flutter pub get
```

이미 복제한 저장소가 있다면 최신 배포 태그로 이동할 수 있다.

```sh
git fetch --tags
git switch --detach v0.1.0-beta.2
flutter pub get
```

## 2. iPhone 연결과 개발자 모드 활성화

1. iPhone을 Mac에 연결한다.
2. iPhone에 `이 컴퓨터를 신뢰하시겠습니까?`가 표시되면 신뢰를 선택한다.
3. iPhone에서 `설정 → 개인정보 보호 및 보안 → 개발자 모드`를 켠다.
4. 안내에 따라 iPhone을 재시동한다.
5. 재시동 후 개발자 모드 활성화를 다시 확인하고 기기 암호를 입력한다.

개발자 모드는 Xcode로 직접 설치한 앱을 실행하기 위해 필요하다. 메뉴가 보이지 않으면
iPhone을 Mac 및 Xcode에 먼저 연결한다. 자세한 절차는 [Apple 개발자 모드 안내][developer-mode]를
참고한다.

## 3. Apple 계정을 Xcode에 등록

1. Xcode를 실행한다.
2. `Xcode → Settings → Accounts`를 연다.
3. 왼쪽 아래 `+`를 누르고 본인의 Apple 계정으로 로그인한다.
4. 계정 아래에 `Personal Team`이 표시되는지 확인한다.

Apple 계정 비밀번호나 인증 코드를 프로젝트 파일, 터미널 명령 또는 다른 사람에게
전달하지 않는다.

## 4. 프로젝트 서명 설정

Flutter 프로젝트 루트에서 다음 명령으로 Xcode 작업 공간을 연다.

```sh
open ios/Runner.xcworkspace
```

Xcode에서 다음 순서로 설정한다.

1. 왼쪽 프로젝트 탐색기에서 `Runner` 프로젝트를 선택한다.
2. `TARGETS`의 `Runner`를 선택한다.
3. `Signing & Capabilities` 탭을 연다.
4. `Automatically manage signing`을 켠다.
5. `Team`에서 본인의 `Personal Team`을 선택한다.
6. 서명 오류가 나면 `Bundle Identifier`를 본인만의 값으로 변경한다.

예시:

```text
com.myname.skalaAttendance
```

Bundle Identifier에는 공백이나 한글을 사용하지 않는다. 이후 재설치할 때 앱 데이터와
동일 앱 식별을 최대한 유지하려면 이 값을 임의로 바꾸지 않는다.

## 5. iPhone에 빌드 및 설치

1. Xcode 상단 실행 대상에서 연결한 본인의 iPhone을 선택한다.
2. Xcode의 실행 버튼을 누르거나 `Product → Run`을 선택한다.
3. Xcode가 인증서, 기기 등록 및 개발용 프로비저닝 프로파일을 자동으로 준비할 때까지
   기다린다.
4. 빌드가 성공하면 iPhone에서 앱이 자동으로 실행되는지 확인한다.

Xcode의 자동 서명 과정에 대한 설명은 [Apple의 실기기 실행 안내][apple-run-device]를
참고한다.

명령줄을 선호한다면 Xcode에서 최초 서명 설정을 마친 후 다음 방법도 사용할 수 있다.

```sh
flutter devices
flutter run -d <표시된-iPhone-device-id>
```

## 6. 앱 초기 설정

1. 앱에서 이름, 캠퍼스와 반을 입력한다.
2. 사용자 정보 검증이 성공하는지 확인한다.
3. 알림 권한을 허용한다.
4. 일정을 등록하고 로컬 알림을 확인한다.
5. 알림을 눌렀을 때 앱 내 Safari 화면에서 직접 출결을 처리한다.

iOS에서는 Android 전용 `인증 후 앱 복귀` 설정이 나타나지 않는 것이 정상이다.

## 7. 7일 후 다시 설치

앱이 더 이상 실행되지 않으면 무료 서명 또는 프로비저닝 프로파일이 만료됐을 가능성이
높다. iPhone을 같은 Mac에 연결하고 같은 Apple 계정, Team 및 Bundle Identifier를
사용하여 Xcode에서 `Product → Run`을 다시 실행한다.

덮어쓰기 설치 시 데이터가 유지될 수 있지만 설치 상태나 서명 변경에 따라 달라질 수
있으므로 일정과 설정 보존을 보장하지 않는다. 앱을 먼저 삭제하면 로컬 데이터도 함께
삭제된다.

## 자주 발생하는 문제

### iPhone이 실행 대상에 표시되지 않음

- 케이블 연결과 iPhone의 `이 컴퓨터 신뢰` 상태를 확인한다.
- iPhone 잠금을 해제한다.
- Xcode의 `Window → Devices and Simulators`에서 연결 상태를 확인한다.
- iPhone의 개발자 모드를 확인한다.

### 서명 또는 프로비저닝 오류

- Xcode `Accounts`에 Apple 계정이 로그인되어 있는지 확인한다.
- `Team`이 본인의 `Personal Team`인지 확인한다.
- `Automatically manage signing`을 켠다.
- Bundle Identifier를 본인만의 영문 식별자로 바꾼다.

### 앱은 설치됐지만 사용자 정보 검증이 실패함

- 이름, 캠퍼스와 반 조합을 다시 확인한다.
- 인터넷과 SKALA에서 요구하는 네트워크 연결을 확인한다.
- VPN이 SKALA 네트워크 판별을 방해하지 않는지 확인한다.

## 공식 참고 자료

- [Apple 개발자 계정과 무료 Personal Team 제한][apple-account]
- [Apple 실기기 빌드 및 실행][apple-run-device]
- [Apple 개발자 모드 활성화][developer-mode]
- [Flutter iOS 개발 환경 설정][flutter-ios-setup]

[apple-account]: https://developer.apple.com/help/account/basics/about-your-developer-account/
[apple-run-device]: https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices
[developer-mode]: https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device
[flutter-ios-setup]: https://docs.flutter.dev/platform-integration/ios/setup
