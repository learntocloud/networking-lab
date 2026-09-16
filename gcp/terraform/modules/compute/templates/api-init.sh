#!/bin/bash
# API server initialization script
set -e

apt-get update
apt-get install -y python3 python3-flask postgresql-client net-tools dnsutils \
    traceroute netcat-openbsd curl jq vim iputils-ping

mkdir -p /opt/api
cat > /opt/api/app.py << 'PYAPP'
from flask import Flask, jsonify
import os
import socket

app = Flask(__name__)

@app.route('/')
def home():
    return jsonify(service='API Server', status='running', hostname=socket.gethostname())

@app.route('/health')
def health():
    return jsonify(status='healthy')

@app.route('/db-check')
def db_check():
    host = os.environ.get('DB_HOST', 'db.internal.test')
    try:
        with socket.create_connection((host, 5432), timeout=5):
            return jsonify(database='reachable', host=host, port=5432)
    except OSError as error:
        return jsonify(database='unreachable', host=host, port=5432, error=str(error)), 503

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
Environment=DB_HOST=db.internal.test
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
  nc -zv db.internal.test 5432
  curl http://localhost:8080/

Before DNS is repaired, use the database private IP:
  pg_isready -h <database-private-ip> -p 5432 -t 3

============================================================
EOF

echo "API server setup complete"
touch /var/lib/netlab-startup-complete
