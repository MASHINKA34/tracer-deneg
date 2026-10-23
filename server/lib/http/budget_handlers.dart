import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:shared/shared.dart';
import 'package:shelf/shelf.dart';

import '../auth/auth_middleware.dart';
import '../budgets/budget_service.dart';
import 'json.dart';

final _log = Logger('budgets');

Handler createBudgetHandler(BudgetService budgets) => (Request request) async {
  const operation = 'budget create';
  final userId = authContextOf(request).userId;
  final body = await _readBody(request, operation, userId);
  if (body.error != null) return body.error!;
  final fields = body.fields!;
  final id = fields['id'];
  final name = fields['name'];
  final emoji = fields['emoji'];

  if (id is! String || !isUuid(id) || name is! String || emoji is! String) {
    return _badFields(operation, userId, [
      if (id is! String || !isUuid(id)) 'id',
      if (name is! String) 'name',
      if (emoji is! String) 'emoji',
    ]);
  }

  for (final (field, value) in [('name', name), ('emoji', emoji)]) {
    if (value.contains('\u0000')) {
      _log.warning(
        '$operation rejected reason=${ApiErrorCode.validationFailed.code} '
        'userId=$userId budgetId=$id field=$field problem=contains_nul',
      );
      return errorResponse(
        400,
        ApiErrorCode.validationFailed.code,
        'Данные не прошли проверку',
      );
    }
  }
  final problems = [
    ('name', validateBudgetName(name)),
    ('emoji', validateEmoji(emoji)),
  ];
  for (final (field, error) in problems) {
    if (error == null) continue;
    _log.warning(
      '$operation rejected reason=${error.code} userId=$userId '
      'budgetId=$id field=$field',
    );
    return errorResponse(400, error.code, _validationMessage(error));
  }

  try {
    final created = await budgets.create(
      userId: userId,
      budgetId: id,
      name: name,
      emoji: emoji,
    );
    return _noStore(
      jsonResponse(created.replayed ? 200 : 201, {
        'budget': created.budget.toJson(),
      }),
    );
  } on BudgetFailure catch (e) {
    return _failure(e);
  }
};

class _Body {
  const _Body.ok(this.fields) : error = null;
  const _Body.failed(this.error) : fields = null;

  final Map<String, Object?>? fields;
  final Response? error;
}

Future<_Body> _readBody(
  Request request,
  String operation,
  String userId,
) async {
  final Object? decoded;
  try {
    decoded = jsonDecode(await request.readAsString());
  } on FormatException catch (e) {
    _log.warning(
      '$operation rejected reason=${ApiErrorCode.badRequest.code} '
      'userId=$userId problem="body is not JSON: ${e.message}"',
    );
    return _Body.failed(
      errorResponse(
        400,
        ApiErrorCode.badRequest.code,
        'Неверный запрос: тело должно быть JSON',
      ),
    );
  }
  if (decoded is! Map<String, Object?>) {
    _log.warning(
      '$operation rejected reason=${ApiErrorCode.badRequest.code} '
      'userId=$userId problem="body is ${decoded.runtimeType}, not an object"',
    );
    return _Body.failed(
      errorResponse(
        400,
        ApiErrorCode.badRequest.code,
        'Неверный запрос: тело должно быть JSON-объектом',
      ),
    );
  }
  return _Body.ok(decoded);
}

Response _badFields(String operation, String userId, List<String> fields) {
  _log.warning(
    '$operation rejected reason=${ApiErrorCode.badRequest.code} '
    'userId=$userId fields=${fields.join(',')}',
  );
  return errorResponse(
    400,
    ApiErrorCode.badRequest.code,
    'Неверный запрос: проверь поля ${fields.join(', ')}',
  );
}

Response _failure(BudgetFailure failure) => switch (failure.reason) {
  BudgetFailureReason.notFound => errorResponse(
    404,
    ApiErrorCode.notFound.code,
    'Бюджет не найден',
  ),
  BudgetFailureReason.forbidden => errorResponse(
    403,
    ApiErrorCode.forbidden.code,
    'Это может сделать только создатель бюджета',
  ),
  BudgetFailureReason.personalBudget => errorResponse(
    403,
    ApiErrorCode.forbidden.code,
    'С личным бюджетом так нельзя: он только твой',
  ),
  BudgetFailureReason.inviteNotFound => errorResponse(
    404,
    ApiErrorCode.inviteNotFound.code,
    'Код не найден или истёк',
  ),
  BudgetFailureReason.memberNotFound => errorResponse(
    404,
    ApiErrorCode.notFound.code,
    'Участник не найден',
  ),
  BudgetFailureReason.removeSelf => errorResponse(
    400,
    ApiErrorCode.badRequest.code,
    'Себя исключить нельзя: выйди из бюджета',
  ),
  BudgetFailureReason.idTaken => errorResponse(
    409,
    ApiErrorCode.conflict.code,
    'Бюджет с таким id уже есть',
  ),
};

Response _noStore(Response response) =>
    response.change(headers: {'cache-control': 'no-store'});

String _validationMessage(ValidationError error) => switch (error) {
  ValidationError.budgetNameEmpty => 'Введи название бюджета',
  ValidationError.budgetNameTooLong =>
    'Название слишком длинное: не больше $budgetNameMaxLength символов',
  ValidationError.emojiEmpty => 'Выбери значок бюджета',
  ValidationError.emojiInvalid => 'Значок бюджета должен быть одним эмодзи',
  _ => 'Данные не прошли проверку',
};
