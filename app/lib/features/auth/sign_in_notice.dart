import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

final _log = Logger('auth');

enum SignInNotice { accountDeleted }

final signInNoticeProvider =
    NotifierProvider<SignInNoticeController, SignInNotice?>(
      SignInNoticeController.new,
      name: 'signInNotice',
    );

final class SignInNoticeController extends Notifier<SignInNotice?> {
  @override
  SignInNotice? build() => null;

  void post(SignInNotice notice) {
    final replaced = state;
    state = notice;
    _log.fine(
      'sign-in notice ${notice.name} waits for the sign-in screen'
      '${replaced == null ? '' : ' (replaces ${replaced.name})'}',
    );
  }

  SignInNotice? take() {
    final notice = state;
    if (notice == null) return null;
    state = null;
    _log.fine('sign-in notice ${notice.name} taken by the sign-in screen');
    return notice;
  }
}
