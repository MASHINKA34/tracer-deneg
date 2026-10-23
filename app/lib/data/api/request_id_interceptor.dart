import 'package:dio/dio.dart';
import 'package:shared/logging.dart';

const String requestIdHeader = 'X-Request-Id';

const String apiRequestIdKey = 'milionchik.rid';

class RequestIdInterceptor extends Interceptor {
  const RequestIdInterceptor({this.generate = generateRequestId});

  final String Function() generate;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final current = options.extra[apiRequestIdKey];
    final rid = current is String && isValidRequestId(current)
        ? current
        : generate();
    options.extra[apiRequestIdKey] = rid;
    options.headers[requestIdHeader] = rid;
    handler.next(options);
  }
}

String? requestIdOfOptions(RequestOptions options) {
  final rid = options.extra[apiRequestIdKey];
  return rid is String ? rid : null;
}
