import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:shared/logging.dart';

final _log = Logger('api');

const Set<String> _secretKeys = {
  'accessToken',
  'refreshToken',
  'token',
  'password',
  'newPassword',
};

const Set<String> _tokenResponseKeys = {'accessToken', 'refreshToken'};

const Set<String> _personalTextKeys = {
  'comment',
  'displayName',
  'name',
  'title',
};

const Set<String> _codeParentsKeptAsIs = {'error', 'rejected'};

Object? maskJsonForLog(Object? value, [String? parentKey]) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        '${entry.key}': _maskField('${entry.key}', entry.value, parentKey),
    };
  }
  if (value is List) {
    return [for (final item in value) maskJsonForLog(item, parentKey)];
  }
  return value;
}

Object? _maskField(String key, Object? value, String? parentKey) {
  if (value == null) return null;
  if (_secretKeys.contains(key)) return maskToken(_text(value));
  if (key == 'recoveryCode') return maskRecoveryCode(_text(value));
  if (key == 'login') return maskLogin(_text(value));
  if (key == 'code' && !_codeParentsKeptAsIs.contains(parentKey)) {
    return maskInviteCode(_text(value));
  }
  if (_personalTextKeys.contains(key)) return maskToken(_text(value));
  return maskJsonForLog(value, key);
}

String _text(Object value) => value is String ? value : jsonEncode(value);

String? requestBodyForLog(Object? data) {
  if (data == null) return null;
  if (data is Map || data is List) {
    return truncateBody(jsonEncode(maskJsonForLog(data)));
  }
  if (data is String) {
    if (data.isEmpty) return null;
    final decoded = _tryDecode(data);
    if (decoded == null) return truncateBody(data);
    return truncateBody(jsonEncode(maskJsonForLog(decoded)));
  }
  return '<${data.runtimeType}>';
}

String? responseBodyForLog(Object? data) {
  if (data == null) return null;
  final Object? json;
  if (data is String) {
    if (data.isEmpty) return null;
    json = _tryDecode(data);
    if (json == null) return truncateBody(data);
  } else if (data is Map || data is List) {
    json = data;
  } else {
    return '<${data.runtimeType}>';
  }
  if (json is Map && json.keys.any(_tokenResponseKeys.contains)) {
    return '<omitted: response with tokens>';
  }
  return truncateBody(jsonEncode(maskJsonForLog(json)));
}

Object? _tryDecode(String text) {
  try {
    return jsonDecode(text);
  } on FormatException catch (e) {
    _log.fine(
      'body for log is not JSON (${e.message}) → logging raw text '
      'bytes=${utf8.encode(text).length}',
    );
    return null;
  }
}
