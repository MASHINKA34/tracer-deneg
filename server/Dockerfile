FROM dart:3.13.6 AS build

WORKDIR /src
COPY shared/pubspec.yaml shared/
COPY server/pubspec.yaml server/pubspec.lock server/
RUN dart pub get --enforce-lockfile --directory=server

COPY shared/lib/ shared/lib/
COPY server/bin/ server/bin/
COPY server/lib/ server/lib/
RUN mkdir -p /out && dart compile exe server/bin/server.dart -o /out/server

FROM busybox:1.38.0-musl

COPY --from=build /runtime/ /
RUN addgroup -S -g 10001 milionchik \
 && adduser -S -D -H -u 10001 -G milionchik -s /bin/false milionchik

WORKDIR /app
COPY --from=build /out/server /app/server
COPY server/migrations/ /app/migrations/

USER 10001:10001
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --start-interval=2s --retries=3 \
  CMD wget -q -Y off -O /dev/null "http://127.0.0.1:${PORT:-8080}/api/v1/health" || exit 1
ENTRYPOINT ["/app/server"]
