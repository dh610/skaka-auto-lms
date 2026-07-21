# Android APK 배포

## 목적

이 문서는 교육생 대상 Android APK를 동일한 서명으로 반복 배포하기 위한 절차를
정리한다. 배포용 keystore와 비밀번호는 Git에 저장하지 않는다.

## 최초 1회 서명 준비

저장소 루트에서 다음 명령을 실행하고 비밀번호와 인증서 정보를 직접 입력한다.

```sh
keytool -genkeypair -v \
  -keystore android/app/release-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias skala-attendance
```

`android/key.properties.example`을 `android/key.properties`로 복사하고 실제 비밀번호를
입력한다. 다음 두 파일은 안전한 별도 위치에 백업한다.

- `android/app/release-keystore.jks`
- `android/key.properties`

keystore 또는 비밀번호를 잃으면 기존 설치 사용자에게 동일 앱의 업데이트 APK를
제공할 수 없다.

## 빌드와 검증

```sh
flutter analyze
flutter test
flutter build apk --release
```

결과물은 `build/app/outputs/flutter-apk/app-release.apk`에 생성된다. 배포 전에는 이
release APK를 실제 Android 기기에 설치하고 다음 항목을 확인한다.

1. 기존 버전 위에 업데이트 설치되는지 확인
2. 사용자 정보, 일정 및 테마가 유지되는지 확인
3. 알림 권한과 일정 알림 확인
4. Chrome Custom Tab에서 Google 인증 시작
5. 인증 후 Android App Link로 앱 복귀
6. 상태 조회 확인

신규 설치에서는 첫 Google 인증 전에 앱이 Android의 지원 링크 설정 화면으로 안내할 수
있다. `att.skala-ai.com` 링크를 이 앱에서 열도록 한 번 허용한 뒤 돌아오면 인증이
자동으로 이어져야 한다. SKALA 서버가 올바른 Digital Asset Links 파일을 제공하기
전까지는 이 최초 1회 허용이 필요하다.

실제 출결 동작은 테스트를 위해 임의로 전송하지 않는다.

알림 아이콘은 플러그인에서 리소스 이름 문자열로 참조하므로
`android/app/src/main/res/raw/keep.xml`에서 release 리소스 축소 대상에서 제외한다.
이 설정을 제거하면 debug에서는 정상이어도 release에서 `invalid_icon` 오류로 알림
예약이 실패할 수 있다.

## 새 버전 배포

새 APK를 배포할 때마다 `pubspec.yaml`의 build number를 증가시킨다.

```yaml
version: 1.0.1+2
```

같은 application ID와 동일한 release keystore를 계속 사용해야 기존 설치 위에
업데이트할 수 있다.

## 현재 release 인증서

최초 배포용 release 인증서의 SHA-256 지문은 다음과 같다. 이 값은 공개키 식별자이며
비밀번호나 개인키가 아니다.

```text
2E:AA:BC:49:A2:61:17:1C:6C:4A:75:17:B2:7B:83:37:
E8:18:EA:D8:86:C5:51:C1:F5:53:54:D0:B3:72:74:CB
```

기존 debug APK와 release APK는 서명이 다르므로 서로 덮어쓸 수 없다. 최초 release
실기기 검증 시에는 debug 앱을 삭제해야 하며 앱의 로컬 데이터도 함께 초기화된다.
