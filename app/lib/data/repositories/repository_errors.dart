import 'package:shared/shared.dart';

enum RepositoryFailure {
  validation('validation'),
  notFound('not_found'),
  systemCategory('system_category'),
  otherCategoryMissing('other_category_missing');

  const RepositoryFailure(this.code);

  final String code;
}

final class RepositoryException implements Exception {
  const RepositoryException(
    this.failure, {
    required this.entity,
    this.id,
    this.validation,
  });

  const RepositoryException.validation(
    ValidationError this.validation, {
    required this.entity,
    this.id,
  }) : failure = RepositoryFailure.validation;

  final RepositoryFailure failure;
  final String entity;
  final String? id;
  final ValidationError? validation;

  String get code => validation?.code ?? failure.code;

  @override
  String toString() =>
      'RepositoryException(${failure.code} entity=$entity id=${id ?? '-'}'
      '${validation == null ? '' : ' validation=${validation!.code}'})';
}

void checkValid(ValidationError? error, {required String entity, String? id}) {
  if (error != null) {
    throw RepositoryException.validation(error, entity: entity, id: id);
  }
}
