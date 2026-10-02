#!/usr/bin/env python3
"""Сервер превью UI: отдаёт корень проекта (нужны assets/fonts и assets/ui/icons)
и редиректит / на страницу превью. Запуск: python3 tools/ui-preview/serve.py [port]"""
import functools
import http.server
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent  # alchemists-loop/
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765


class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path in ("/", ""):
            self.send_response(302)
            self.send_header("Location", "/tools/ui-preview/index.html")
            self.end_headers()
            return
        super().do_GET()

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


if __name__ == "__main__":
    httpd = http.server.ThreadingHTTPServer(("0.0.0.0", PORT), functools.partial(Handler, directory=str(ROOT)))
    print(f"preview on http://0.0.0.0:{PORT}/ -> /tools/ui-preview/index.html")
    httpd.serve_forever()
