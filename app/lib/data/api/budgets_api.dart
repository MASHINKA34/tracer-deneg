import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import 'api_client.dart';
import 'api_exception.dart';
import 'api_providers.dart';

final _log = Logger('budgets');

const String budgetsPath = '/budgets';

const String joinBudgetPath = '/invites/join';

final class JoinedBudgetReply {
  const JoinedBudgetReply({
    required this.budget,
    required this.statusCode,
    required this.requestId,
  });

  final Budget budget;
  final int statusCode;
  final String requestId;

  @override
  String toString() =>
      'JoinedBudgetReply(budgetId=${budget.id} kind=${budget.kind.name} '
      'status=$statusCode rid=$requestId)';
}

final class CreatedBudgetReply {
  const CreatedBudgetReply({
    required this.budget,
    required this.statusCode,
    required this.requestId,
  });

  final Budget budget;
  final int statusCode;
  final String requestId;

  bool get replayed => statusCode == 200;

  @override
  String toString() =>
      'CreatedBudgetReply(budgetId=${budget.id} status=$statusCode '
      'rid=$requestId)';
}

class BudgetsApi {
  BudgetsApi(this._client);

  final ApiClient _client;

  Future<CreatedBudgetReply> create({
    required String id,
    required String name,
    required String emoji,
  }) async {
    final response = await _client.post(
      budgetsPath,
      body: {'id': id, 'name': name, 'emoji': emoji},
    );
    try {
      final reader = JsonReader.of(response.data, 'CreateBudgetResponse');
      final budget = Budget.fromJson(reader.json['budget']);
      if (budget.id != id) {
        throw FormatException(
          'CreateBudgetResponse.budget.id: expected the requested id, got '
          'another one',
        );
      }
      return CreatedBudgetReply(
        budget: budget,
        statusCode: response.statusCode,
        requestId: response.requestId,
      );
    } on FormatException catch (e) {
      _log.warning(
        'POST $budgetsPath ${response.statusCode} budgetId=$id answered '
        'without {budget} → bad response: ${e.message} '
        'rid=${response.requestId}',
      );
      throw ApiBadResponse(
        method: 'POST',
        path: '${_client.config.baseUrl.path}$budgetsPath',
        requestId: response.requestId,
        statusCode: response.statusCode,
        reason: 'create budget: ${e.message}',
      );
    }
  }

  Future<JoinedBudgetReply> join({required String code}) async {
    final response = await _client.post(joinBudgetPath, body: {'code': code});
    try {
      final reader = JsonReader.of(response.data, 'JoinBudgetResponse');
      final budget = Budget.fromJson(reader.json['budget']);
      return JoinedBudgetReply(
        budget: budget,
        statusCode: response.statusCode,
        requestId: response.requestId,
      );
    } on FormatException catch (e) {
      _log.warning(
        'POST $joinBudgetPath ${response.statusCode} code=${maskInviteCode(code)} '
        'answered without {budget} → bad response: ${e.message} '
        'rid=${response.requestId}',
      );
      throw ApiBadResponse(
        method: 'POST',
        path: '${_client.config.baseUrl.path}$joinBudgetPath',
        requestId: response.requestId,
        statusCode: response.statusCode,
        reason: 'join budget: ${e.message}',
      );
    }
  }
}

final budgetsApiProvider = Provider<BudgetsApi>(
  (ref) => BudgetsApi(ref.watch(apiClientProvider)),
  name: 'budgetsApi',
);
