#!/usr/bin/env python3
"""fixture_server.py — 教务协议 fixture HTTP 服务器(T6.5b 教务链 XCUITest 的对端)
服务 fixtures/{wisedu,qz,zf,urp}/ 下的登录页+课表页快照。
用法: python3 scripts/fixture_server.py [port]   (默认 8765)
路由:
  GET /{proto}/login       → 登录页 HTML(表单 POST /{proto}/doLogin)
  POST /{proto}/doLogin    → 302 设置 session cookie → /{proto}/kb
  GET /{proto}/kb          → 课表页(需 cookie;无 cookie → 302 回 login)
fixtures 不存在时用内嵌最小样本自动生成(D0 验收: 返回一登录页+一课表页)。
"""
import http.server, os, sys, socketserver

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8791  # 8765 被本机网关占用
BASE = os.path.join(os.path.dirname(__file__), '..', 'fixtures')

LOGIN_TEMPLATES = {
    'wisedu': '<html><body><form method="POST" action="/wisedu/doLogin"><input name="username"/><input name="password" type="password"/><button id="loginBtn">登录</button></form></body></html>',
    'qz':     '<html><body><form method="POST" action="/qz/doLogin"><input name="user"/><input name="pass" type="password"/><button>登录</button></form></body></html>',
    'zf':     '<html><body><form method="POST" action="/zf/doLogin"><input name="yhm"/><input name="mm" type="password"/><button id="login_subnetlogin</button></form></body></html>',
    'urp':    '<html><body><form method="POST" action="/urp/doLogin"><input name="j_username"/><input name="j_password" type="password"/><button>登录</button></form></body></html>',
}
KB_TEMPLATES = {
    'wisedu': '{"kbList":[{"kcmc":"高等数学","jsxm":"张三","jsmc":"A101","xqj":"1","jcdm":"1-2","zcd":"1-16周"}]}',
    'qz':     '<html><body><table id="kbtable"><tr><td>高等数学;张三;A101;周一第1,2节{1-16周}</td></tr></table></body></html>',
    'zf':     '<html><body><table id="kblist"><tr><td>高等数学</td><td>张三</td><td>A101</td><td>星期一第1,2节</td><td>1-16周</td></tr></table></body></html>',
    'urp':    '<html><body><table><tr><td>高等数学 张三 A101 一 1-2节 1-16周</td></tr></table></body></html>',
}

def ensure_fixtures():
    for proto in LOGIN_TEMPLATES:
        d = os.path.join(BASE, proto)
        os.makedirs(d, exist_ok=True)
        lp, kp = os.path.join(d, 'login.html'), os.path.join(d, 'kb.html')
        if not os.path.exists(lp):
            open(lp, 'w', encoding='utf-8').write(LOGIN_TEMPLATES[proto])
        if not os.path.exists(kp):
            open(kp, 'w', encoding='utf-8').write(KB_TEMPLATES[proto])

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        sys.stderr.write("[fixture] %s\n" % (fmt % args))

    def _serve(self, body, ctype='text/html; charset=utf-8', code=200, headers=None):
        data = body.encode('utf-8') if isinstance(body, str) else body
        self.send_response(code)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(data)))
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(data)

    def _proto(self, path):
        for p in LOGIN_TEMPLATES:
            if path.startswith('/' + p + '/'):
                return p
        return None

    def do_GET(self):
        path = self.path.split('?')[0]
        proto = self._proto(path)
        if proto is None:
            return self._serve('not found', code=404)
        if path == f'/{proto}/login':
            return self._serve(open(f'{BASE}/{proto}/login.html', encoding='utf-8').read())
        if path == f'/{proto}/kb':
            if 'Cookie' not in self.headers or 'JSESSIONID' not in (self.headers.get('Cookie') or ''):
                self.send_response(302)
                self.send_header('Location', f'/{proto}/login')
                self.end_headers()
                return
            ct = 'application/json' if proto == 'wisedu' else 'text/html; charset=utf-8'
            return self._serve(open(f'{BASE}/{proto}/kb.html', encoding='utf-8').read(), ctype=ct)
        return self._serve('not found', code=404)

    def do_POST(self):
        path = self.path.split('?')[0]
        proto = self._proto(path)
        if proto and path == f'/{proto}/doLogin':
            length = int(self.headers.get('Content-Length') or 0)
            self.rfile.read(length)  # 接受任意账密: 测试只验链路
            self.send_response(302)
            self.send_header('Set-Cookie', 'JSESSIONID=fixture-session-123; Path=/')
            self.send_header('Location', f'/{proto}/kb')
            self.end_headers()
            return
        return self._serve('not found', code=404)

class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True

if __name__ == '__main__':
    ensure_fixtures()
    with Server(('127.0.0.1', PORT), Handler) as httpd:
        print(f'fixture server on http://127.0.0.1:{PORT}  protocols: {list(LOGIN_TEMPLATES)}')
        httpd.serve_forever()
