## Stage 1: Build Flutter web app + compile Dart server
FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app
COPY . .

# Build Flutter web
RUN flutter build web

# Compile the server to a native executable
RUN dart pub get --directory=. && \
    dart compile exe bin/server.dart -o bin/server

## Stage 2: Minimal runtime image
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/bin/server /app/bin/server
COPY --from=build /app/build/web/ /app/build/web/

WORKDIR /app
EXPOSE 8080
ENV PORT=8080
CMD ["/app/bin/server"]
