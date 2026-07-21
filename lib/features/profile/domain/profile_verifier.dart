import 'user_profile.dart';

abstract interface class ProfileVerifier {
  Future<void> verify(UserProfile profile);

  void close();
}

sealed class ProfileVerificationException implements Exception {
  const ProfileVerificationException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class InvalidProfileException extends ProfileVerificationException {
  const InvalidProfileException()
    : super('등록된 수강생 정보를 찾을 수 없습니다. 이름, 캠퍼스와 반을 다시 확인해주세요.');
}

final class ProfileVerificationUnavailableException
    extends ProfileVerificationException {
  const ProfileVerificationUnavailableException([
    super.message = '사용자 정보를 확인할 수 없습니다. 네트워크 연결을 확인한 뒤 다시 시도해주세요.',
  ]);
}
