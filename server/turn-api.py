#!/usr/bin/env python3
"""Authenticated TURN credentials and a bounded HTTPS signaling mailbox."""
import base64
import hashlib
import hmac
import json
import queue
import secrets
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

CONFIG = json.loads(Path('/etc/dante-live/private.json').read_text())
WEB = Path('/opt/dante-live/GuestWeb')
REQUESTS = queue.Queue(maxsize=24)
PENDING = {}
LOCK = threading.Lock()
GUEST_PATHS = {'/join', '/offer', '/ice', '/status', '/leave'}
FILES = {'/': ('index.html', 'text/html; charset=utf-8'),
         '/guest.js': ('guest.js', 'text/javascript; charset=utf-8'),
         '/guest.css': ('guest.css', 'text/css; charset=utf-8')}

class Handler(BaseHTTPRequestHandler):
    server_version = 'DanteLiveGuestGateway/2'
    sys_version = ''
    def log_message(self, *_args):
        pass
    def authorized(self):
        return hmac.compare_digest(self.headers.get('Authorization', ''),
                                   'Bearer ' + CONFIG['connection_token'])
    def do_GET(self):
        if self.path in FILES:
            name, kind = FILES[self.path]
            try:
                data = (WEB / name).read_bytes()
            except OSError:
                self.reply(503, {'error': 'guest_page_unavailable'})
                return
            self.send(200, data, kind)
            return
        if not self.authorized():
            self.reply(401, {'error': 'unauthorized'})
            return
        if self.path == '/api/health':
            self.reply(200, {'status': 'ready', 'protocol': 2})
        elif self.path == '/api/turn':
            expiry = int(time.time()) + 12 * 60 * 60
            username = f'{expiry}:{secrets.token_hex(8)}'
            digest = hmac.new(CONFIG['turn_secret'].encode(), username.encode(), hashlib.sha1).digest()
            address = CONFIG['public_ip']
            self.reply(200, {'expiresAt': expiry, 'iceServers': [
                {'urls': [f'turn:{address}:3478?transport=udp',
                          f'turn:{address}:3478?transport=tcp',
                          f'turns:{address}:5349?transport=tcp'],
                 'username': username, 'credential': base64.b64encode(digest).decode()}
            ]})
        elif self.path == '/api/poll':
            try:
                request = REQUESTS.get(timeout=20)
            except queue.Empty:
                request = None
            self.reply(200, {'request': request})
        else:
            self.reply(404, {'error': 'not_found'})
    def do_POST(self):
        try:
            size = int(self.headers.get('Content-Length', '-1'))
        except ValueError:
            size = -1
        if size < 0 or size > 90000 or self.headers.get('Content-Type', '').split(';')[0] != 'application/json':
            self.reply(400, {'error': 'invalid_request'})
            return
        try:
            body = json.loads(self.rfile.read(size))
        except (ValueError, UnicodeDecodeError):
            self.reply(400, {'error': 'invalid_json'})
            return
        if self.path == '/api/reply':
            if not self.authorized() or not isinstance(body, dict):
                self.reply(401, {'error': 'unauthorized'})
                return
            with LOCK:
                pending = PENDING.get(body.get('id'))
                if pending and pending['answer'] is None:
                    pending['answer'] = body
                    pending['event'].set()
            self.reply(200, {'ok': bool(pending)})
            return
        if self.path not in GUEST_PATHS or not isinstance(body, dict):
            self.reply(404, {'error': 'not_found'})
            return
        origin = 'https://' + CONFIG['public_ip']
        token = self.headers.get('Authorization', '')
        if self.headers.get('Origin') != origin or not token.startswith('Bearer ') or len(token) != 71:
            self.reply(403, {'error': 'forbidden'})
            return
        ident = secrets.token_hex(16)
        pending = {'event': threading.Event(), 'answer': None}
        with LOCK:
            PENDING[ident] = pending
        try:
            REQUESTS.put_nowait({'id': ident, 'path': self.path, 'token': token[7:], 'payload': body})
        except queue.Full:
            with LOCK:
                PENDING.pop(ident, None)
            self.reply(503, {'error': 'room_busy'})
            return
        pending['event'].wait(timeout=22)
        with LOCK:
            PENDING.pop(ident, None)
        answer = pending['answer']
        if not answer:
            self.reply(503, {'error': 'presenter_offline'})
            return
        try:
            status = int(answer['status'])
            content = base64.b64decode(answer['body'], validate=True)
            if status < 200 or status > 599 or len(content) > 90000:
                raise ValueError()
        except (KeyError, ValueError, TypeError):
            self.reply(502, {'error': 'invalid_presenter_reply'})
            return
        self.send(status, content, 'application/json')
    def reply(self, status, value):
        self.send(status, json.dumps(value, separators=(',', ':')).encode(), 'application/json')
    def send(self, status, body, kind):
        self.send_response(status)
        self.send_header('Content-Type', kind)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Referrer-Policy', 'no-referrer')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('X-Frame-Options', 'DENY')
        self.send_header('Permissions-Policy', 'camera=(self), microphone=(self), display-capture=(self)')
        self.send_header('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; media-src 'self' blob:; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'none'")
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1', 8765), Handler).serve_forever()
