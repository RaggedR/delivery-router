FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app
COPY . .

RUN flutter build web --release
RUN dart pub get && dart compile exe bin/server.dart -o bin/server

## Minimal runtime — use Debian slim since 'scratch' needs /runtime/ from dart:stable
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/bin/server /app/bin/server
COPY --from=build /app/build/web/ /app/build/web/

WORKDIR /app
EXPOSE 8080
ENV PORT=8080
CMD ["/app/bin/server"]
