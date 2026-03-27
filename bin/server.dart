import 'dart:io';

/// Simple server that:
/// 1. Serves the Flutter web build from build/web/
/// 2. Proxies /maps-proxy/* to maps.googleapis.com/* with the API key injected server-side
void main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 9090;
  final apiKey = Platform.environment['GOOGLE_MAPS_API_KEY'] ?? '';
  final webDir = Directory('build/web');

  if (apiKey.isEmpty) {
    stderr.writeln('WARNING: GOOGLE_MAPS_API_KEY not set. Maps API calls will fail.');
  }

  if (!webDir.existsSync()) {
    stderr.writeln('ERROR: build/web/ not found. Run "flutter build web" first.');
    exit(1);
  }

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  stderr.writeln('Delivery Router server listening on http://0.0.0.0:$port');

  await for (final request in server) {
    try {
      final path = request.uri.path;

      if (path.startsWith('/maps-proxy/')) {
        await _proxyMapsRequest(request, apiKey);
      } else {
        await _serveStatic(request, webDir);
      }
    } catch (e) {
      stderr.writeln('Error handling ${request.uri}: $e');
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write('Internal Server Error')
        ..close();
    }
  }
}

/// Proxies requests from /maps-proxy/maps/api/* to maps.googleapis.com/maps/api/*
/// Injects the API key server-side so it never reaches the frontend.
Future<void> _proxyMapsRequest(HttpRequest request, String apiKey) async {
  final googlePath = request.uri.path.replaceFirst('/maps-proxy', '');

  // Take query params from the request, replace/add the API key server-side
  final params = Map<String, String>.from(request.uri.queryParameters);
  params['key'] = apiKey;

  final googleUri = Uri.https('maps.googleapis.com', googlePath, params);

  final client = HttpClient();
  try {
    final proxyRequest = await client.getUrl(googleUri);

    final proxyResponse = await proxyRequest.close();
    request.response.statusCode = proxyResponse.statusCode;

    // Only forward safe headers — Google sends CSP/COOP headers that break XMLHttpRequest
    const safeHeaders = {'content-type', 'cache-control', 'expires', 'date', 'vary'};
    proxyResponse.headers.forEach((name, values) {
      if (safeHeaders.contains(name.toLowerCase())) {
        for (final v in values) {
          request.response.headers.add(name, v);
        }
      }
    });

    request.response.headers.set('Access-Control-Allow-Origin', '*');

    await proxyResponse.pipe(request.response);
  } finally {
    client.close();
  }
}

/// Serves static files from the build/web directory.
Future<void> _serveStatic(HttpRequest request, Directory webDir) async {
  request.response.headers.set('Access-Control-Allow-Origin', '*');

  var path = request.uri.path;
  if (path == '/') path = '/index.html';

  final file = File('${webDir.path}$path');

  if (await file.exists()) {
    final ext = path.split('.').last;
    request.response.headers.contentType = _contentType(ext);
    await file.openRead().pipe(request.response);
  } else {
    // SPA fallback: serve index.html for unmatched routes
    final index = File('${webDir.path}/index.html');
    request.response.headers.contentType = ContentType.html;
    await index.openRead().pipe(request.response);
  }
}

ContentType _contentType(String ext) {
  return switch (ext) {
    'html' => ContentType.html,
    'js' => ContentType('application', 'javascript', charset: 'utf-8'),
    'css' => ContentType('text', 'css', charset: 'utf-8'),
    'json' => ContentType.json,
    'png' => ContentType('image', 'png'),
    'jpg' || 'jpeg' => ContentType('image', 'jpeg'),
    'ico' => ContentType('image', 'x-icon'),
    'svg' => ContentType('image', 'svg+xml'),
    'wasm' => ContentType('application', 'wasm'),
    'otf' => ContentType('font', 'otf'),
    'ttf' => ContentType('font', 'ttf'),
    _ => ContentType.binary,
  };
}
