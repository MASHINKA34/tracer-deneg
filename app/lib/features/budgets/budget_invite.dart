import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared/shared.dart';

import '../../data/session/session_providers.dart';

final _log = Logger('budgets');

final class BudgetInvite {
  const BudgetInvite({required this.code, required this.expiresAt});

  final String code;
  final DateTime expiresAt;

  bool activeAt(DateTime now) => now.isBefore(expiresAt);

  @override
  String toString() =>
      'BudgetInvite(code=${maskInviteCode(code)} '
      'expiresAt=${encodeInstant(expiresAt)})';
}

final budgetInvitesProvider =
    NotifierProvider<BudgetInvites, Map<String, BudgetInvite>>(
      BudgetInvites.new,
      name: 'budgetInvites',
    );

final class BudgetInvites extends Notifier<Map<String, BudgetInvite>> {
  @override
  Map<String, BudgetInvite> build() {
    final userId = ref.watch(sessionProvider.select((s) => s.userId));
    _log.fine(
      'invite codes in memory reset for userId=${userId ?? '-'}: codes live '
      'only until the app is closed',
    );
    return const {};
  }

  void remember(String budgetId, BudgetInvite invite) {
    state = {...state, budgetId: invite};
    _log.fine('invite code kept in memory budgetId=$budgetId $invite');
  }

  void forget(String budgetId, {required String reason}) {
    if (!state.containsKey(budgetId)) return;
    state = {
      for (final entry in state.entries)
        if (entry.key != budgetId) entry.key: entry.value,
    };
    _log.fine('invite code forgotten budgetId=$budgetId: $reason');
  }
}

abstract interface class InviteCodeSharer {
  Future<ShareResult> share(String text);
}

final class SharePlusInviteCodeSharer implements InviteCodeSharer {
  const SharePlusInviteCodeSharer();

  @override
  Future<ShareResult> share(String text) =>
      SharePlus.instance.share(ShareParams(text: text));
}

final inviteCodeSharerProvider = Provider<InviteCodeSharer>(
  (ref) => const SharePlusInviteCodeSharer(),
  name: 'inviteCodeSharer',
);
