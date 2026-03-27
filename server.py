#!/usr/bin/env python3
"""Simple proxy server that serves the Flutter web app and proxies Google Maps API calls."""

import http.server
import urllib.request
import urllib.parse
import os

WEB_DIR = os.path.join(os.path.dirname(__file__), "build", "web")
PORT = 8080


class ProxyHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WEB_DIR, **kwargs)

    def do_GET(self):
        if self.path.startswith("/maps-proxy/"):
            self._proxy_to_google()
        else:
            super().do_GET()

    def _proxy_to_google(self):
        # Strip "/maps-proxy/" prefix and forward to Google
        google_path = self.path[len("/maps-proxy/"):]
        url = f"https://maps.googleapis.com/{google_path}"
        try:
            req = urllib.request.Request(url)
            with urllib.request.urlopen(req, timeout=10) as resp:
                body = resp.read()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(body)
        except Exception as e:
            self.send_response(502)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(f"Proxy error: {e}".encode())


if __name__ == "__main__":
    with http.server.HTTPServer(("0.0.0.0", PORT), ProxyHandler) as httpd:
        print(f"Serving on http://0.0.0.0:{PORT}")
        httpd.serve_forever()
