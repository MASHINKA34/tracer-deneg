import 'package:flutter/foundation.dart';

const String apiUrlDefine = String.fromEnvironment('API_URL');

const String debugApiUrl = 'http://10.0.2.2:8080/api/v1';

const String debugCleartextHost = '10.0.2.2';

const Duration apiConnectTimeout = Duration(seconds: 10);

const Duration apiReceiveTimeout = Duration(seconds: 30);

enum ApiConfigProblem { missing, invalid, insecure, cleartextHost }

final class ApiConfigException implements Exception {
  const ApiConfigException(this.problem, this.message);

  final ApiConfigProblem problem;
  final String message;

  @override
  String toString() => 'ApiConfigException: $message (${problem.name})';
}

final class ApiConfig {
  const ApiConfig({required this.baseUrl, required this.fromDefine});

  factory ApiConfig.resolve({
    String define = apiUrlDefine,
    bool debugBuild = kDebugMode,
  }) {
    final value = define.trim();
    if (value.isEmpty) {
      if (debugBuild) {
        return ApiConfig(baseUrl: Uri.parse(debugApiUrl), fromDefine: false);
      }
      throw const ApiConfigException(
        ApiConfigProblem.missing,
        'API_URL is not set: non-debug builds need '
        '--dart-define=API_URL=https://<host>/api/v1',
      );
    }

    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasScheme ||
        !(uri.isScheme('http') || uri.isScheme('https')) ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      throw ApiConfigException(
        ApiConfigProblem.invalid,
        'API_URL "$value" is not an absolute http(s) URL without '
        'query, fragment and credentials, expected https://<host>/api/v1',
      );
    }

    if (uri.isScheme('http')) {
      if (!debugBuild) {
        throw ApiConfigException(
          ApiConfigProblem.insecure,
          'API_URL "$value" uses http: non-debug builds talk to the server '
          'only over https',
        );
      }
      if (uri.host != debugCleartextHost) {
        throw ApiConfigException(
          ApiConfigProblem.cleartextHost,
          'API_URL "$value" uses http to host ${uri.host}: cleartext is '
          'allowed only to $debugCleartextHost in debug builds',
        );
      }
    }

    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return ApiConfig(baseUrl: uri.replace(path: path), fromDefine: true);
  }

  final Uri baseUrl;
  final bool fromDefine;

  String get baseUrlText => baseUrl.toString();

  @override
  String toString() =>
      'ApiConfig(baseUrl=$baseUrlText source=${fromDefine ? 'API_URL' : 'debug default'})';
}
