#!/bin/bash
# API server initialization script
set -e

# Install Python and tools
apt-get update
apt-get install -y \
    python3 \
    python3-flask \
    net-tools \
    dnsutils \
    traceroute \
    netcat-openbsd \
    curl \
    jq \
    vim

# Create simple API application
mkdir -p /opt/api
cat > /opt/api/app.py << 'PYAPP'
from flask import Flask, jsonify
import socket
import os

app = Flask(__name__)

@app.route('/')
def home():
    return jsonify({
        'service': 'API Server',
        'status': 'running',
        'hostname': socket.gethostname()
    })

@app.route('/health')
def health():
    return jsonify({'status': 'healthy'})

@app.route('/db-check')
def db_check():
    """Try to connect to database server"""
    import socket
    db_host = os.environ.get('DB_HOST', 'db.internal.local')
    db_port = 5432

    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5)
        result = sock.connect_ex((db_host, db_port))
        sock.close()

        if result == 0:
            return jsonify({'database': 'reachable', 'host': db_host, 'port': db_port})
        else:
            return jsonify({'database': 'unreachable', 'host': db_host, 'port': db_port, 'error': 'connection refused'}), 503
    except socket.gaierror:
        return jsonify({'database': 'unreachable', 'host': db_host, 'error': 'DNS resolution failed'}), 503
    except Exception as e:
        return jsonify({'database': 'unreachable', 'error': str(e)}), 503

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
PYAPP

# Create systemd service
cat > /etc/systemd/system/api.service << 'SVCFILE'
[Unit]
Description=Networking Lab API Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/api
Environment=DB_HOST=db.internal.local
ExecStart=/usr/bin/python3 /opt/api/app.py
Restart=always

[Install]
WantedBy=multi-user.target
SVCFILE

systemctl daemon-reload
systemctl enable api
systemctl start api

# Create MOTD
cat > /etc/motd << 'EOF'
============================================================
   NETWORKING LAB - API SERVER
============================================================

You are on the API server in the PRIVATE subnet.
This server runs a Flask API on port 8080.

Check API service:
  sudo systemctl status api
  curl http://localhost:8080/health
  curl http://localhost:8080/db-check

Test connectivity:
  nc -zv db.internal.local 5432
  curl http://localhost:8080/

============================================================
EOF

echo "API server setup complete"
