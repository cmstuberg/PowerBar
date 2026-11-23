# -*- coding: utf-8 -*-
# Test server for nettest.sh (MacPorts python2.7). Serves ROOT over:
#   https://127.0.0.1:PORT_A   files, /redirect/<f> -> https://localhost:PORT_B/<f>
#                              (another host name, like GitHub's release redirects),
#                              /to-http/<f> -> http://127.0.0.1:PORT_C/<f> (a downgrade),
#                              /hang (accepts, never answers)
#   https://localhost:PORT_B   files
#   http://127.0.0.1:PORT_C    files
# Every request path is appended to LOG. Writes READY once all three listen.
#
#   python2.7 https-server.py ROOT CERT KEY PORT_A PORT_B PORT_C LOG READY
import BaseHTTPServer, SocketServer, ssl, sys, os, time, threading

root, cert, key, pa, pb, pc, log, ready = sys.argv[1:9]
log_lock = threading.Lock()

class Handler(BaseHTTPServer.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def redirect(self, to):
        self.send_response(302)
        self.send_header('Location', to)
        self.send_header('Content-Length', '0')
        self.end_headers()

    def do_GET(self):
        path = self.path.split('?')[0]
        with log_lock:
            open(log, 'a').write('%s %s\n' % (self.server.server_address[1], path))
        if path.startswith('/redirect/'):
            return self.redirect('https://localhost:%s/%s' % (pb, path[len('/redirect/'):]))
        if path.startswith('/to-http/'):
            return self.redirect('http://127.0.0.1:%s/%s' % (pc, path[len('/to-http/'):]))
        if path == '/hang':
            time.sleep(120)
            return
        name = os.path.join(root, os.path.basename(path))
        if not os.path.isfile(name):
            return self.send_error(404)
        data = open(name, 'rb').read()
        types = {'.xml': 'application/xml', '.html': 'text/html; charset=utf-8',
                 '.png': 'image/png', '.zip': 'application/zip'}
        self.send_response(200)
        self.send_header('Content-Type', types.get(os.path.splitext(name)[1], 'application/octet-stream'))
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

class Server(SocketServer.ThreadingMixIn, BaseHTTPServer.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

def serve(port, tls):
    s = Server(('127.0.0.1', int(port)), Handler)
    if tls:
        s.socket = ssl.wrap_socket(s.socket, certfile=cert, keyfile=key, server_side=True)
    t = threading.Thread(target=s.serve_forever)
    t.daemon = True
    t.start()

serve(pa, True)
serve(pb, True)
serve(pc, False)
open(ready, 'w').write('ok\n')
while True:
    time.sleep(3600)
